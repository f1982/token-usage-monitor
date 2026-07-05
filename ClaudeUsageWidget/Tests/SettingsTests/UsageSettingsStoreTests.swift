import XCTest

@MainActor
final class UsageSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UsageSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultSettingsAreSafe() {
        let store = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.quotaSourceMode, .officialStatuslineOnly)
        XCTAssertFalse(store.settings.localProjectAnalyticsEnabled, "local analytics must default to off")
        XCTAssertFalse(store.settings.experimentalOAuthEnabled, "experimental OAuth must default to off")
        XCTAssertEqual(store.settings.claudeProjectsPath, "~/.claude/projects")
        XCTAssertEqual(store.settings.projectAnalyticsDefaultRange, .last7Days)
    }

    func testSettingsPersistAndReload() {
        let store = UsageSettingsStore(defaults: defaults)
        store.settings.quotaSourceMode = .statuslineThenLocalThenOAuth
        store.settings.localProjectAnalyticsEnabled = true
        store.settings.claudeProjectsPath = "~/custom/projects"
        store.settings.experimentalOAuthEnabled = true

        let reloaded = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.settings.quotaSourceMode, .statuslineThenLocalThenOAuth)
        XCTAssertTrue(reloaded.settings.localProjectAnalyticsEnabled)
        XCTAssertEqual(reloaded.settings.claudeProjectsPath, "~/custom/projects")
        XCTAssertTrue(reloaded.settings.experimentalOAuthEnabled)
    }

    func testCorruptStoredSettingsFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: UsageSettingsStore.storageKey)

        let store = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, .default)
    }

    func testUnknownStoredValuesFallBackToDefaults() {
        let json = #"{"quotaSourceMode":"someFutureMode","localProjectAnalyticsEnabled":true}"#
        defaults.set(Data(json.utf8), forKey: UsageSettingsStore.storageKey)

        let store = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.quotaSourceMode, .officialStatuslineOnly)
        XCTAssertTrue(store.settings.localProjectAnalyticsEnabled)
    }
}
