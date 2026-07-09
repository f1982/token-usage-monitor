import SwiftUI
import WidgetKit

@main
struct TokenUsageMonitorApp: App {
    @StateObject private var settingsStore: UsageSettingsStore
    @StateObject private var refreshService: UsageRefreshService
    @StateObject private var projectAnalytics: ProjectAnalyticsViewModel
    @StateObject private var codexSessionMonitor: CodexSessionMonitor

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
            codexUsageProvider: CodexSessionUsageProvider(
                sessionsDirectory: {
                    URL(
                        fileURLWithPath: (settingsStore.settings.codexSessionsPath as NSString).expandingTildeInPath,
                        isDirectory: true
                    )
                }
            ),
            cacheStore: UsageCacheStore(),
            reloadWidgets: reloadWidgets
        ))
        let codexProvider = CodexSessionUsageProvider(
            sessionsDirectory: {
                URL(
                    fileURLWithPath: (settingsStore.settings.codexSessionsPath as NSString).expandingTildeInPath,
                    isDirectory: true
                )
            }
        )

        _projectAnalytics = StateObject(wrappedValue: ProjectAnalyticsViewModel(
            settingsStore: settingsStore,
            reloadWidgets: reloadWidgets
        ))
        _codexSessionMonitor = StateObject(wrappedValue: CodexSessionMonitor(provider: codexProvider))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(refreshService)
                .environmentObject(projectAnalytics)
                .environmentObject(codexSessionMonitor)
        }
        .windowResizability(.contentSize)
    }
}
