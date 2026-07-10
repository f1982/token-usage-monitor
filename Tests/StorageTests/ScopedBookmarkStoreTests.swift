import XCTest

final class ScopedBookmarkStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "ScopedBookmarkStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
    }

    func testRemoveDeletesBookmarkWithoutRestoringAPath() {
        let store = ScopedBookmarkStore(defaults: defaults)
        defaults.set(Data("not a bookmark".utf8), forKey: "scoped-bookmark-claudeProjects-v1")

        XCTAssertTrue(store.hasBookmark(for: .claudeProjects))
        store.remove(.claudeProjects)
        XCTAssertFalse(store.hasBookmark(for: .claudeProjects))
        XCTAssertNil(store.resolve(.claudeProjects))
    }

    func testMissingBookmarkDoesNotRunOperation() {
        let store = ScopedBookmarkStore(defaults: defaults)
        var didRun = false

        let result = store.withAccess(for: .statusline) { _ in
            didRun = true
        }

        XCTAssertNil(result)
        XCTAssertFalse(didRun)
    }
}
