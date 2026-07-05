import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case projects
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .projects: return "Projects"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.needle"
        case .projects: return "folder"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var analytics: ProjectAnalyticsViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: AppSection = .overview

    private let autoRefreshTimer = Timer.publish(
        every: UsageRefreshService.cacheTTL,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch selection {
            case .overview:
                ScrollView {
                    UsageOverviewView()
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                }
            case .projects:
                ProjectsView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .task {
            await refreshService.refresh()
        }
        .task {
            // Background prefetch so the Projects tab is warm on first open.
            await analytics.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshService.refresh() }
        }
        .onReceive(autoRefreshTimer) { _ in
            Task { await refreshService.refresh() }
        }
    }
}
