import AppKit
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: UsageSettingsStore
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var analytics: ProjectAnalyticsViewModel

    var body: some View {
        Form {
            quotaSourceSection
            projectAnalyticsSection
            experimentalSection
            privacySection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: settingsStore.settings.quotaSourceMode) { _, _ in
            Task { await refreshService.refresh(force: true) }
        }
        .onChange(of: settingsStore.settings.experimentalOAuthEnabled) { _, _ in
            Task { await refreshService.refresh(force: true) }
        }
        .onChange(of: settingsStore.settings.localProjectAnalyticsEnabled) { _, _ in
            // The widget shows/hides its projects section based on this setting.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Sections

    private var quotaSourceSection: some View {
        Section("Usage Source") {
            Picker("Quota Source Mode", selection: $settingsStore.settings.quotaSourceMode) {
                ForEach(QuotaSourceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text("The official Claude Code statusline is always tried first. Fallback sources are only used when you enable them here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var projectAnalyticsSection: some View {
        Section("Local Project Analytics") {
            Toggle("Enable Local Project Analytics", isOn: $settingsStore.settings.localProjectAnalyticsEnabled)
            Text("Reads local Claude Code JSONL files under ~/.claude/projects to calculate per-project token usage. Prompt and message content are not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Claude Projects Path", text: $settingsStore.settings.claudeProjectsPath)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            HStack {
                Button("Open Claude Projects Folder") {
                    openProjectsFolder()
                }
                Button("Refresh Project Analytics") {
                    Task { await analytics.refresh() }
                }
                .disabled(!settingsStore.settings.localProjectAnalyticsEnabled || analytics.isScanning)
            }

            if settingsStore.settings.localProjectAnalyticsEnabled, !analytics.hasScanned {
                Text("Click Refresh to scan local logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var experimentalSection: some View {
        Section("Experimental") {
            Toggle("Enable Experimental OAuth Usage API", isOn: $settingsStore.settings.experimentalOAuthEnabled)
            Text("Uses Claude Code's local OAuth token and an undocumented Anthropic usage endpoint. This may break without notice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Text("All data stays on this Mac. Raw logs, prompt text, and message content are never stored or uploaded. Only aggregated token totals are cached for the widget.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openProjectsFolder() {
        let path = (settingsStore.settings.claudeProjectsPath as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
