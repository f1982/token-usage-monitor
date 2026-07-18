import XCTest

final class CodexSessionUsageProviderTests: XCTestCase {
    func testParsesLatestTokenCountRateLimits() {
        let jsonl = """
        {"timestamp":"2026-07-06T09:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":21.0,"window_minutes":300,"resets_at":1783338000},"secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1783942800}}}}
        {"timestamp":"2026-07-06T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":34.0,"window_minutes":300,"resets_at":1783341600},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1783946400}}}}
        """

        let limits = CodexSessionUsageProvider.limits(fromJSONL: jsonl)

        XCTAssertEqual(limits.count, 2)
        XCTAssertEqual(limits[0].id, "codex-codex-300")
        XCTAssertEqual(limits[0].kind, "codex_codex_300")
        XCTAssertEqual(limits[0].label, "Codex 5h")
        XCTAssertEqual(limits[0].percent, 34)
        XCTAssertEqual(limits[0].resetsAt, Date(timeIntervalSince1970: 1_783_341_600))
        XCTAssertEqual(limits[1].label, "Codex weekly")
        XCTAssertEqual(limits[1].percent, 12)
    }

    func testReturnsEmptyWhenNoRateLimitsExist() {
        let jsonl = """
        {"timestamp":"2026-07-06T09:00:00Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"hello"}}
        """

        XCTAssertTrue(CodexSessionUsageProvider.limits(fromJSONL: jsonl).isEmpty)
    }

    func testSkipsSparseLatestEventAndUsesLastCompleteSnapshot() {
        let jsonl = """
        {"timestamp":"2026-07-18T04:49:59Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":4.0,"window_minutes":10080,"resets_at":1784954930},"secondary":null}}}
        {"timestamp":"2026-07-18T04:50:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":null,"secondary":null}}}
        """

        let limits = CodexSessionUsageProvider.limits(fromJSONL: jsonl)

        XCTAssertEqual(limits.map(\.percent), [4])
    }

    func testParsesWeeklyOnlyRateLimitWhenSecondaryIsNull() {
        let jsonl = """
        {"timestamp":"2026-07-18T04:49:59Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1784954930},"secondary":null}}}
        """

        let limits = CodexSessionUsageProvider.limits(fromJSONL: jsonl)

        XCTAssertEqual(limits.count, 1)
        guard let limit = limits.first else { return }
        XCTAssertEqual(limit.label, "Codex weekly")
        XCTAssertEqual(limit.percent, 1)
        XCTAssertEqual(limit.resetsAt, Date(timeIntervalSince1970: 1_784_954_930))
    }

    func testLabelsWindowsByDurationInsteadOfPrimarySecondaryPosition() {
        let jsonl = """
        {"timestamp":"2026-07-18T04:49:59Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":8.0,"window_minutes":10080,"resets_at":1784954930},"secondary":{"used_percent":21.0,"window_minutes":300,"resets_at":1784360000}}}}
        """

        let limits = CodexSessionUsageProvider.limits(fromJSONL: jsonl)

        XCTAssertEqual(limits.map(\.label), ["Codex 5h", "Codex weekly"])
        XCTAssertEqual(limits.map(\.percent), [21, 8])
    }

    func testFallsBackToNewestSessionFileContainingRateLimits() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSessionUsageProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = directory.appendingPathComponent("older.jsonl")
        let newer = directory.appendingPathComponent("newer.jsonl")
        try """
        {"timestamp":"2026-07-18T04:49:59Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1784954930},"secondary":null}}}
        """.write(to: older, atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-07-18T05:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        """.write(to: newer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newer.path)

        let limits = await CodexSessionUsageProvider(sessionsDirectory: directory).fetchCodexLimits()

        XCTAssertEqual(limits.map(\.percent), [3])
    }

    func testParsesActiveSessionMetadataAndUsage() {
        let jsonl = """
        {"timestamp":"2026-07-10T00:00:00Z","type":"session_meta","payload":{"session_id":"session-1","cwd":"/tmp/token-usage-monitor","originator":"Codex Desktop","model_provider":"openai"}}
        {"timestamp":"2026-07-10T00:00:10Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
        {"timestamp":"2026-07-10T00:00:12Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1234},"model_context_window":353400}}}
        """

        let session = CodexSessionUsageProvider.activeSession(fromJSONL: jsonl)

        XCTAssertEqual(session?.sessionID, "session-1")
        XCTAssertEqual(session?.provider, "openai")
        XCTAssertEqual(session?.model, "gpt-5.6-luna")
        XCTAssertEqual(session?.client, "Codex Desktop")
        XCTAssertEqual(session?.workingDirectory, "/tmp/token-usage-monitor")
        XCTAssertEqual(session?.totalTokens, 1234)
        XCTAssertEqual(session?.contextWindow, 353400)
    }
}
