import SwiftUI
import WidgetKit

@main
struct TokenUsageMonitorApp: App {
    @StateObject private var settingsStore: UsageSettingsStore
    @StateObject private var refreshService: UsageRefreshService
    @StateObject private var projectAnalytics: ProjectAnalyticsViewModel
    @StateObject private var codexSessionMonitor: CodexSessionMonitor
    @State private var menuBarUsageInserted = false

    init() {
        let settingsStore = UsageSettingsStore()
        let bookmarkStore = ScopedBookmarkStore()
        let reloadWidgets = { WidgetCenter.shared.reloadAllTimelines() }
        _menuBarUsageInserted = State(initialValue: settingsStore.settings.menuBarUsageEnabled)

        let aggregator = UsageAggregatorService(
            settingsProvider: { settingsStore.settings },
            providers: [
                StatuslineUsageProvider(fileURL: {
                    bookmarkStore.resolve(.statusline)?.appendingPathComponent("latest.json")
                }),
                OAuthUsageProvider(),
            ]
        )

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _refreshService = StateObject(wrappedValue: UsageRefreshService(
            aggregator: aggregator,
            codexUsageProvider: CodexSessionUsageProvider(
                sessionsDirectory: {
                    bookmarkStore.resolve(.codexSessions)
                }
            ),
            cacheStore: UsageCacheStore(),
            reloadWidgets: reloadWidgets
        ))
        let codexProvider = CodexSessionUsageProvider(
            sessionsDirectory: {
                bookmarkStore.resolve(.codexSessions)
            }
        )

        _projectAnalytics = StateObject(wrappedValue: ProjectAnalyticsViewModel(
            settingsStore: settingsStore,
            bookmarkStore: bookmarkStore,
            reloadWidgets: reloadWidgets
        ))
        _codexSessionMonitor = StateObject(wrappedValue: CodexSessionMonitor(provider: codexProvider))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(menuBarUsageInserted: $menuBarUsageInserted)
                .environmentObject(settingsStore)
                .environmentObject(refreshService)
                .environmentObject(projectAnalytics)
                .environmentObject(codexSessionMonitor)
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $menuBarUsageInserted) {
            MenuBarUsageView()
                .environmentObject(settingsStore)
                .environmentObject(refreshService)
                .environmentObject(codexSessionMonitor)
        } label: {
            MenuBarUsageLabel()
                .environmentObject(settingsStore)
                .environmentObject(refreshService)
                .environmentObject(codexSessionMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct AppRootView: View {
    @EnvironmentObject private var settingsStore: UsageSettingsStore
    @Binding var menuBarUsageInserted: Bool

    var body: some View {
        ContentView()
            .onChange(of: settingsStore.settings.menuBarUsageEnabled) { _, enabled in
                menuBarUsageInserted = enabled
            }
    }
}
