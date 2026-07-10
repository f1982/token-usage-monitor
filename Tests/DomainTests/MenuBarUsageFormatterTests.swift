import XCTest

final class MenuBarUsageFormatterTests: XCTestCase {
    func testFormatsClaudeAndCodexSessionUsage() {
        let snapshot = ClaudeUsageSnapshot(
            available: true,
            session: UsageLimit(id: "session", kind: "session", label: "Session", percent: 34, resetsAt: nil),
            weekly: nil,
            weeklyScoped: [],
            codex: [],
            fetchedAt: Date()
        )
        let codex = CodexActiveSession(
            sessionID: "session-1",
            provider: "openai",
            model: "gpt-5",
            client: nil,
            workingDirectory: nil,
            lastEventAt: Date(),
            totalTokens: 12_340,
            contextWindow: 100_000
        )

        let values = MenuBarUsageFormatter.values(
            snapshot: snapshot,
            codexSession: codex,
            visibleSources: [.claudeCode, .codex]
        )

        XCTAssertEqual(values.map(\.name), ["Claude Code", "Codex"])
        XCTAssertEqual(values[0].detail, "Session 34% used")
        XCTAssertEqual(values[1].detail, "12k/100k (12%)")
        XCTAssertEqual(MenuBarUsageFormatter.label(snapshot: snapshot, codexSession: codex, visibleSources: [.claudeCode, .codex]), "Cl Session 34% used · Cx 12k/100k (12%)")
    }

    func testHiddenSourcesAreNotFormatted() {
        XCTAssertTrue(MenuBarUsageFormatter.values(snapshot: nil, codexSession: nil, visibleSources: []).isEmpty)
        XCTAssertEqual(MenuBarUsageFormatter.label(snapshot: nil, codexSession: nil, visibleSources: []), "Usage —")
    }
}
