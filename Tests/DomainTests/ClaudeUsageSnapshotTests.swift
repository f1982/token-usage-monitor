import XCTest

final class ClaudeUsageSnapshotTests: XCTestCase {
    func testFilteredCanShowOnlyClaudeCodeUsage() {
        let snapshot = makeSnapshot()

        let filtered = snapshot.filtered(visibleSources: [.claudeCode])

        XCTAssertTrue(filtered.hasAnyUsage)
        XCTAssertNotNil(filtered.session)
        XCTAssertNotNil(filtered.weekly)
        XCTAssertTrue(filtered.codex.isEmpty)
    }

    func testFilteredCanShowOnlyCodexUsage() {
        let snapshot = makeSnapshot()

        let filtered = snapshot.filtered(visibleSources: [.codex])

        XCTAssertTrue(filtered.hasAnyUsage)
        XCTAssertNil(filtered.session)
        XCTAssertNil(filtered.weekly)
        XCTAssertTrue(filtered.weeklyScoped.isEmpty)
        XCTAssertEqual(filtered.codex.count, 1)
    }

    private func makeSnapshot() -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: true,
            session: UsageLimit(id: "session", kind: "session", label: "Session", percent: 25, resetsAt: nil),
            weekly: UsageLimit(id: "weekly", kind: "weekly_all", label: "All models", percent: 40, resetsAt: nil),
            weeklyScoped: [],
            codex: [
                UsageLimit(id: "codex-primary", kind: "codex_primary", label: "Codex 5h", percent: 12, resetsAt: nil),
            ],
            note: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_751_700_000)
        )
    }
}
