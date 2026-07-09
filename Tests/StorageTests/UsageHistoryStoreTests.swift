import XCTest

final class UsageHistoryStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageHistoryStoreTests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
        try super.tearDownWithError()
    }

    private func snapshot(percent: Double) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: true,
            session: UsageLimit(id: "session", kind: "session", label: "Session", percent: percent, resetsAt: nil),
            weekly: UsageLimit(id: "weekly", kind: "weekly_all", label: "All models", percent: percent + 10, resetsAt: nil),
            weeklyScoped: [],
            fetchedAt: Date()
        )
    }

    func testAppendRoundTripsAndReplacesPointsWithinFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = UsageHistoryStore(fileURL: fileURL, now: { now })

        store.append(snapshot: snapshot(percent: 10))
        store.append(snapshot: snapshot(percent: 20))

        let points = store.read()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.sessionPercent, 20)
    }

    func testAppendPrunesPointsOlderThanRetention() {
        let oldPoint = UsageHistoryPoint(
            snapshot: snapshot(percent: 10),
            timestamp: Date(timeIntervalSince1970: 1_800_000_000 - UsageHistoryStore.retention - 1)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode([oldPoint]).write(to: fileURL)

        let store = UsageHistoryStore(
            fileURL: fileURL,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        store.append(snapshot: snapshot(percent: 30))

        XCTAssertEqual(store.read().count, 1)
        XCTAssertEqual(store.read().first?.sessionPercent, 30)
    }
}
