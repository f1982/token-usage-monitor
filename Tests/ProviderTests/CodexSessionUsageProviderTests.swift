import XCTest

final class CodexSessionUsageProviderTests: XCTestCase {
    func testParsesLatestTokenCountRateLimits() {
        let jsonl = """
        {"timestamp":"2026-07-06T09:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":21.0,"window_minutes":300,"resets_at":1783338000},"secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1783942800}}}}
        {"timestamp":"2026-07-06T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":34.0,"window_minutes":300,"resets_at":1783341600},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1783946400}}}}
        """

        let limits = CodexSessionUsageProvider.limits(fromJSONL: jsonl)

        XCTAssertEqual(limits.count, 2)
        XCTAssertEqual(limits[0].id, "codex-primary")
        XCTAssertEqual(limits[0].kind, "codex_primary")
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
