import XCTest

final class LocalProjectUsageProviderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalProjectUsageProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func writeJSONL(_ lines: [String], projectDirectory: String, file: String = "session.jsonl") throws {
        let directory = root.appendingPathComponent(projectDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(lines.joined(separator: "\n").utf8).write(to: directory.appendingPathComponent(file))
    }

    func testMissingRootThrowsRootNotFound() async {
        let provider = LocalProjectUsageProvider(rootPath: root.appendingPathComponent("nope").path)

        do {
            _ = try await provider.fetchProjectSummaries(range: .all, now: Date())
            XCTFail("expected rootNotFound")
        } catch let error as ProjectScanError {
            guard case .rootNotFound = error else {
                return XCTFail("unexpected error \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testScansFilesAndSkipsBadLines() async throws {
        try writeJSONL([
            #"{"message":{"usage":{"input_tokens":100,"output_tokens":10},"id":"m1"},"requestId":"r1","cwd":"/dev/alpha","timestamp":"2026-07-01T10:00:00Z"}"#,
            "this line is not json at all",
            #"{"type":"summary","no":"usage here"}"#,
            #"{"message":{"usage":{"input_tokens":100,"output_tokens":10},"id":"m1"},"requestId":"r1","cwd":"/dev/alpha","timestamp":"2026-07-01T10:00:00Z"}"#,
            #"{"message":{"usage":{"input_tokens":5,"output_tokens":5},"id":"m2"},"requestId":"r2","cwd":"/dev/alpha","timestamp":"2026-07-02T10:00:00Z"}"#,
        ], projectDirectory: "-dev-alpha")
        try writeJSONL([
            #"{"message":{"usage":{"input_tokens":7,"output_tokens":3},"id":"m3"},"requestId":"r3","cwd":"/dev/beta","timestamp":"2026-07-02T11:00:00Z"}"#,
        ], projectDirectory: "-dev-beta")

        let provider = LocalProjectUsageProvider(rootPath: root.path)
        let summaries = try await provider.fetchProjectSummaries(range: .all, now: Date())

        XCTAssertEqual(summaries.count, 2)
        let alpha = try XCTUnwrap(summaries.first { $0.projectName == "alpha" })
        // Duplicate m1/r1 line counted once; bad lines skipped without failing.
        XCTAssertEqual(alpha.messageCount, 2)
        XCTAssertEqual(alpha.totalTokens, 120)
        let beta = try XCTUnwrap(summaries.first { $0.projectName == "beta" })
        XCTAssertEqual(beta.totalTokens, 10)
        XCTAssertEqual(summaries.map(\.projectName), ["alpha", "beta"], "sorted by total tokens descending")
    }

    func testEmptyRootReturnsNoSummaries() async throws {
        let provider = LocalProjectUsageProvider(rootPath: root.path)
        let summaries = try await provider.fetchProjectSummaries(range: .all, now: Date())
        XCTAssertTrue(summaries.isEmpty)
    }

    func testIgnoresNonJSONLFiles() async throws {
        let directory = root.appendingPathComponent("-dev-alpha")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"usage":{"input_tokens":1}}"#.utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let provider = LocalProjectUsageProvider(rootPath: root.path)
        let summaries = try await provider.fetchProjectSummaries(range: .all, now: Date())

        XCTAssertTrue(summaries.isEmpty)
    }
}
