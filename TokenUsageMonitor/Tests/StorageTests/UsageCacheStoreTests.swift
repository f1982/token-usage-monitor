import XCTest

final class UsageCacheStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageCacheStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private var fileURL: URL {
        tempDirectory.appendingPathComponent("claude-usage-snapshot.json")
    }

    private func makeSnapshot() -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: true,
            session: UsageLimit(id: "session-0", kind: "session", label: "Session", percent: 42, resetsAt: nil),
            weekly: UsageLimit(id: "weekly_all-1", kind: "weekly_all", label: "All models", percent: 31, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
            weeklyScoped: [
                UsageLimit(id: "weekly_scoped-2", kind: "weekly_scoped", label: "Fable", percent: 12, resetsAt: nil)
            ],
            note: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_751_700_000)
        )
    }

    func testWriteThenReadRoundTrips() {
        let store = UsageCacheStore(fileURL: fileURL)
        let snapshot = makeSnapshot()

        store.write(snapshot)
        let loaded = store.read()

        XCTAssertEqual(loaded, snapshot)
    }

    func testMissingFileReturnsNil() {
        let store = UsageCacheStore(fileURL: fileURL)
        XCTAssertNil(store.read())
    }

    func testCorruptJSONReturnsNil() throws {
        try Data("{not valid json!!".utf8).write(to: fileURL)
        let store = UsageCacheStore(fileURL: fileURL)
        XCTAssertNil(store.read())
    }

    func testNilFileURLIsSafe() {
        let store = UsageCacheStore(fileURL: nil)
        store.write(makeSnapshot())
        XCTAssertNil(store.read())
    }

    func testCreatesIntermediateDirectories() {
        let nested = tempDirectory.appendingPathComponent("a/b/claude-usage-snapshot.json")
        let store = UsageCacheStore(fileURL: nested)
        store.write(makeSnapshot())
        XCTAssertNotNil(store.read())
    }

    func testCacheFileNeverContainsToken() throws {
        let store = UsageCacheStore(fileURL: fileURL)
        store.write(makeSnapshot())

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(contents.lowercased().contains("accesstoken"))
        XCTAssertFalse(contents.lowercased().contains("token"))
    }
}
