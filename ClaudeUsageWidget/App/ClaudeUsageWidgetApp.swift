import SwiftUI
import WidgetKit

@main
struct ClaudeUsageWidgetApp: App {
    @StateObject private var settingsStore: UsageSettingsStore
    @StateObject private var refreshService: UsageRefreshService
    @StateObject private var projectAnalytics: ProjectAnalyticsViewModel

    init() {
        let settingsStore = UsageSettingsStore()
        let reloadWidgets = { WidgetCenter.shared.reloadAllTimelines() }

        let aggregator = UsageAggregatorService(
            settingsProvider: { settingsStore.settings },
            providers: [
                StatuslineUsageProvider(),
                OAuthUsageProvider(),
            ]
        )

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _refreshService = StateObject(wrappedValue: UsageRefreshService(
            aggregator: aggregator,
            cacheStore: UsageCacheStore(),
            reloadWidgets: reloadWidgets
        ))
        _projectAnalytics = StateObject(wrappedValue: ProjectAnalyticsViewModel(
            settingsStore: settingsStore,
            reloadWidgets: reloadWidgets
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(refreshService)
                .environmentObject(projectAnalytics)
        }
        .windowResizability(.contentSize)
    }
}
