import XCTest

final class AppDataStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDataStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testClearCachesRemovesAllSharedDataFiles() throws {
        let urls = (0..<3).map { directory.appendingPathComponent("cache-\($0).json") }
        for url in urls {
            try Data("aggregate data".utf8).write(to: url)
        }

        AppDataStore(fileURLs: urls.map(Optional.some)).clearCaches()

        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testClearCachesIsIdempotent() {
        let urls = [directory.appendingPathComponent("missing.json")]

        AppDataStore(fileURLs: urls.map(Optional.some)).clearCaches()

        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
    }
}
