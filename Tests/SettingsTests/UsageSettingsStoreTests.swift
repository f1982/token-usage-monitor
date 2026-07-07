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
        XCTAssertEqual(store.settings.visibleUsageSources, Set(UsageDisplaySource.allCases))
        XCTAssertEqual(store.settings.claudeProjectsPath, "~/.claude/projects")
        XCTAssertEqual(store.settings.codexSessionsPath, "~/.codex/sessions")
        XCTAssertEqual(store.settings.projectAnalyticsDefaultRange, .last7Days)
        XCTAssertEqual(store.settings.usageChartStyle, .progressBar, "chart style must default to the linear progress bar")
    }

    func testSettingsPersistAndReload() {
        let store = UsageSettingsStore(defaults: defaults)
        store.settings.quotaSourceMode = .statuslineThenLocalThenOAuth
        store.settings.localProjectAnalyticsEnabled = true
        store.settings.claudeProjectsPath = "~/custom/projects"
        store.settings.codexSessionsPath = "~/custom/codex/sessions"
        store.settings.experimentalOAuthEnabled = true
        store.settings.usageChartStyle = .donut
        store.settings.visibleUsageSources = [.codex]

        let reloaded = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.settings.quotaSourceMode, .statuslineThenLocalThenOAuth)
        XCTAssertTrue(reloaded.settings.localProjectAnalyticsEnabled)
        XCTAssertEqual(reloaded.settings.claudeProjectsPath, "~/custom/projects")
        XCTAssertEqual(reloaded.settings.codexSessionsPath, "~/custom/codex/sessions")
        XCTAssertTrue(reloaded.settings.experimentalOAuthEnabled)
        XCTAssertEqual(reloaded.settings.usageChartStyle, .donut)
        XCTAssertEqual(reloaded.settings.visibleUsageSources, [.codex])
    }

    func testMissingChartStyleFallsBackToProgressBar() {
        // Settings persisted before this feature won't have the key.
        let json = #"{"quotaSourceMode":"officialStatuslineOnly"}"#
        defaults.set(Data(json.utf8), forKey: UsageSettingsStore.storageKey)

        let store = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.usageChartStyle, .progressBar)
        XCTAssertEqual(store.settings.visibleUsageSources, Set(UsageDisplaySource.allCases))
        XCTAssertEqual(store.settings.codexSessionsPath, "~/.codex/sessions")
    }

    func testEmptyVisibleSourcesFallsBackToAllSources() {
        let json = #"{"visibleUsageSources":[]}"#
        defaults.set(Data(json.utf8), forKey: UsageSettingsStore.storageKey)

        let store = UsageSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.visibleUsageSources, Set(UsageDisplaySource.allCases))
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
