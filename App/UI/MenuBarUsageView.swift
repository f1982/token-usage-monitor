import AppKit
import SwiftUI

/// The compact menu bar label intentionally shows only session usage. The
/// detailed menu keeps the same values readable and offers a manual refresh.
struct MenuBarUsageLabel: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var codexSessionMonitor: CodexSessionMonitor
    @EnvironmentObject private var settingsStore: UsageSettingsStore

    var body: some View {
        Text(MenuBarUsageFormatter.label(
            snapshot: refreshService.snapshot,
            codexSession: codexSessionMonitor.session,
            visibleSources: settingsStore.settings.visibleUsageSources
        ))
        .monospacedDigit()
    }
}

struct MenuBarUsageView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var codexSessionMonitor: CodexSessionMonitor
    @EnvironmentObject private var settingsStore: UsageSettingsStore

    var body: some View {
        let usage = MenuBarUsageFormatter.values(
            snapshot: refreshService.snapshot,
            codexSession: codexSessionMonitor.session,
            visibleSources: settingsStore.settings.visibleUsageSources
        )

        VStack(alignment: .leading, spacing: 8) {
            Text("Current session")
                .font(.headline)

            if usage.isEmpty {
                Text("No session usage available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usage) { item in
                    HStack {
                        Text(item.name)
                        Spacer(minLength: 24)
                        Text(item.detail)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Button("Refresh") {
                Task {
                    await refreshService.refresh(force: true)
                    await codexSessionMonitor.refresh()
                }
            }
            .disabled(refreshService.isRefreshing)

            Button("Quit Token Usage Monitor") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
