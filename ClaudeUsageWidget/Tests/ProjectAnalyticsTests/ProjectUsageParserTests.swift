import XCTest

final class ProjectUsageParserTests: XCTestCase {
    private let filePath = "/Users/me/.claude/projects/-Users-me-dev-alpha/session-1.jsonl"

    private func parse(_ line: String, lineNumber: Int = 1) -> ProjectUsageEvent? {
        ProjectUsageParser.parseLine(line, filePath: filePath, lineNumber: lineNumber)
    }

    // MARK: - Token extraction

    func testExtractsTopLevelUsageTokens() throws {
        let event = try XCTUnwrap(parse(
            #"{"usage":{"input_tokens":100,"output_tokens":50},"cwd":"/Users/me/dev/alpha"}"#
        ))
        XCTAssertEqual(event.inputTokens, 100)
        XCTAssertEqual(event.outputTokens, 50)
        XCTAssertEqual(event.cacheCreationTokens, 0)
        XCTAssertEqual(event.cacheReadTokens, 0)
        XCTAssertEqual(event.totalTokens, 150)
    }

    func testExtractsCacheTokens() throws {
        let event = try XCTUnwrap(parse(
            #"{"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":30,"cache_read_input_tokens":200}}"#
        ))
        XCTAssertEqual(event.cacheCreationTokens, 30)
        XCTAssertEqual(event.cacheReadTokens, 200)
        XCTAssertEqual(event.totalTokens, 233)
    }

    func testExtractsNestedMessageUsage() throws {
        let event = try XCTUnwrap(parse(
            #"{"message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":2}}}"#
        ))
        XCTAssertEqual(event.inputTokens, 10)
        XCTAssertEqual(event.outputTokens, 5)
        XCTAssertEqual(event.cacheCreationTokens, 1)
        XCTAssertEqual(event.cacheReadTokens, 2)
    }

    // MARK: - Model extraction

    func testExtractsModelFromSupportedLocations() throws {
        let topLevel = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"model":"claude-sonnet-5"}"#))
        XCTAssertEqual(topLevel.model, "claude-sonnet-5")

        let inMessage = try XCTUnwrap(parse(#"{"message":{"usage":{"input_tokens":1},"model":"claude-haiku-4-5"}}"#))
        XCTAssertEqual(inMessage.model, "claude-haiku-4-5")

        let inRequest = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"request":{"model":"claude-fable-5"}}"#))
        XCTAssertEqual(inRequest.model, "claude-fable-5")
    }

    // MARK: - Timestamp extraction

    func testExtractsTimestampFromSupportedLocations() throws {
        let expected = ISO8601Parsing.date(from: "2026-07-01T10:00:00Z")

        let topLevel = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"timestamp":"2026-07-01T10:00:00Z"}"#))
        XCTAssertEqual(topLevel.timestamp, expected)

        let createdAt = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"created_at":"2026-07-01T10:00:00Z"}"#))
        XCTAssertEqual(createdAt.timestamp, expected)

        let inMessage = try XCTUnwrap(parse(#"{"message":{"usage":{"input_tokens":1},"timestamp":"2026-07-01T10:00:00Z"}}"#))
        XCTAssertEqual(inMessage.timestamp, expected)
    }

    func testParsesFractionalSecondTimestamps() throws {
        let event = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"timestamp":"2026-07-01T10:00:00.123Z"}"#))
        XCTAssertNotNil(event.timestamp)
    }

    // MARK: - Project extraction

    func testExtractsProjectFromCwd() throws {
        let event = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"cwd":"/Users/me/dev/alpha"}"#))
        XCTAssertEqual(event.projectName, "alpha")
        XCTAssertEqual(event.projectPath, "/Users/me/dev/alpha")
    }

    func testExtractsProjectFromProjectPath() throws {
        let event = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"project_path":"/Users/me/dev/beta"}"#))
        XCTAssertEqual(event.projectName, "beta")
        XCTAssertEqual(event.projectPath, "/Users/me/dev/beta")
    }

    func testExtractsProjectFromWorkspaceCwd() throws {
        let event = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1},"workspace":{"cwd":"/Users/me/dev/gamma"}}"#))
        XCTAssertEqual(event.projectName, "gamma")
        XCTAssertEqual(event.projectPath, "/Users/me/dev/gamma")
    }

    func testDerivesProjectFromFilePathWhenNoProjectField() throws {
        let event = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1}}"#))
        XCTAssertEqual(event.projectName, "-Users-me-dev-alpha")
        XCTAssertNil(event.projectPath, "path is not reliably known when derived from the file path")
    }

    // MARK: - Invalid lines

    func testIgnoresInvalidJSON() {
        XCTAssertNil(parse("{not json"))
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("[1, 2, 3]"))
    }

    func testIgnoresLineWithNoTokenUsage() {
        XCTAssertNil(parse(#"{"type":"summary","cwd":"/Users/me/dev/alpha"}"#))
        XCTAssertNil(parse(#"{"usage":{},"cwd":"/Users/me/dev/alpha"}"#))
    }

    // MARK: - Stable IDs

    func testStableIDPrefersMessageAndRequestIDs() throws {
        let event = try XCTUnwrap(parse(
            #"{"message":{"usage":{"input_tokens":1},"id":"msg_123"},"requestId":"req_456"}"#
        ))
        XCTAssertEqual(event.stableID, "msg:msg_123|req:req_456")
    }

    func testStableIDSupportsSnakeCaseIDs() throws {
        let event = try XCTUnwrap(parse(
            #"{"usage":{"input_tokens":1},"message_id":"msg_a","request_id":"req_b"}"#
        ))
        XCTAssertEqual(event.stableID, "msg:msg_a|req:req_b")
    }

    func testStableIDFallsBackToFilePathAndLineNumber() throws {
        let event = try XCTUnwrap(parse(#"{"usage":{"input_tokens":1}}"#, lineNumber: 7))
        XCTAssertEqual(event.stableID, "file:\(filePath)#L7")
    }

    func testDuplicateLinesProduceSameStableID() throws {
        let line = #"{"message":{"usage":{"input_tokens":1},"id":"msg_dup"},"requestId":"req_dup"}"#
        let first = try XCTUnwrap(parse(line, lineNumber: 1))
        let second = try XCTUnwrap(parse(line, lineNumber: 2))
        XCTAssertEqual(first.stableID, second.stableID)
    }
}
