import XCTest

final class ProjectUsageCacheStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectUsageCacheStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var fileURL: URL { directory.appendingPathComponent("project-usage-summary.json") }

    private func makeCache() -> ProjectUsageCache {
        ProjectUsageCache(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_751_700_000),
            rootPath: "~/.claude/projects",
            timeRange: .last7Days,
            summaries: [
                ProjectUsageSummary(
                    id: "abc123",
                    projectName: "alpha",
                    projectPath: "/dev/alpha",
                    totalTokens: 1234,
                    inputTokens: 1000,
                    outputTokens: 200,
                    cacheCreationTokens: 30,
                    cacheReadTokens: 4,
                    messageCount: 12,
                    models: ["claude-sonnet-5"],
                    firstUsedAt: Date(timeIntervalSince1970: 1_751_000_000),
                    lastUsedAt: Date(timeIntervalSince1970: 1_751_690_000),
                    source: .localEstimate
                ),
            ]
        )
    }

    func testWritesAndReadsCache() {
        let store = ProjectUsageCacheStore(fileURL: fileURL)
        let cache = makeCache()

        store.write(cache)
        let read = store.read()

        XCTAssertEqual(read, cache)
    }

    func testMissingCacheReturnsNil() {
        let store = ProjectUsageCacheStore(fileURL: fileURL)
        XCTAssertNil(store.read())
    }

    func testCorruptCacheReturnsNil() throws {
        try Data("not json at all".utf8).write(to: fileURL)
        let store = ProjectUsageCacheStore(fileURL: fileURL)
        XCTAssertNil(store.read())
    }

    func testNilFileURLIsSafe() {
        let store = ProjectUsageCacheStore(fileURL: nil)
        store.write(makeCache())
        XCTAssertNil(store.read())
    }

    /// Privacy guard: the encoded cache may only contain aggregate fields —
    /// no raw JSONL lines, prompt text, or message content keys.
    func testEncodedCacheContainsOnlyAggregateFields() throws {
        let store = ProjectUsageCacheStore(fileURL: fileURL)
        store.write(makeCache())

        let data = try Data(contentsOf: fileURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summaries = try XCTUnwrap(object["summaries"] as? [[String: Any]])
        let summaryKeys = Set(summaries[0].keys)

        let allowedKeys: Set<String> = [
            "id", "projectName", "projectPath",
            "totalTokens", "inputTokens", "outputTokens",
            "cacheCreationTokens", "cacheReadTokens",
            "messageCount", "models", "firstUsedAt", "lastUsedAt", "source",
        ]
        XCTAssertTrue(summaryKeys.isSubset(of: allowedKeys), "unexpected keys: \(summaryKeys.subtracting(allowedKeys))")

        let encodedText = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in ["prompt", "content", "message\":", "toolUse", "tool_use"] {
            XCTAssertFalse(encodedText.contains(forbidden), "cache must not contain \(forbidden)")
        }
    }
}
