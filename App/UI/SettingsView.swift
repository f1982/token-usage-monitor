import AppKit
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: UsageSettingsStore
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var analytics: ProjectAnalyticsViewModel

    var body: some View {
        Form {
            displaySection
            quotaSourceSection
            codexSection
            appearanceSection
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
        .onChange(of: settingsStore.settings.visibleUsageSources) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: settingsStore.settings.codexSessionsPath) { _, _ in
            Task { await refreshService.refresh(force: true) }
        }
        .onChange(of: settingsStore.settings.localProjectAnalyticsEnabled) { _, _ in
            // The widget shows/hides its projects section based on this setting.
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: settingsStore.settings.usageChartStyle) { _, _ in
            // The widget renders usage in the selected chart style.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Sections

    private var displaySection: some View {
        Section("Display") {
            Toggle("Show Claude Code", isOn: sourceBinding(.claudeCode))
            Toggle("Show Codex", isOn: sourceBinding(.codex))
            Text("Choose which usage products appear in the overview and widget. At least one source stays enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quotaSourceSection: some View {
        Section("Claude Code Source") {
            statuslineConnectionRow
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

    private var statuslineConnectionRow: some View {
        let exists = FileManager.default.fileExists(atPath: StatuslineUsageProvider.defaultFileURL.path)
        return VStack(alignment: .leading, spacing: 6) {
            Label(
                exists ? "Statusline detected" : "Statusline not detected",
                systemImage: exists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(exists ? .green : .orange)

            Text(
                exists
                    ? "Claude Code is writing local usage data. The app will use it automatically when the file is fresh."
                    : "Install the statusline helper and run Claude Code once to start receiving official usage data."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Open Statusline Folder") {
                    openStatuslineFolder()
                }
                Button("Refresh Status") {
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(refreshService.isRefreshing)
            }
        }
        .padding(.vertical, 2)
    }

    private var codexSection: some View {
        Section("Codex") {
            TextField("Codex Sessions Path", text: $settingsStore.settings.codexSessionsPath)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            Text("Reads local Codex session JSONL files and uses the newest token_count rate limit event. Prompt and message content are not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Codex Sessions Folder") {
                    openCodexSessionsFolder()
                }
                Button("Refresh Codex Usage") {
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(refreshService.isRefreshing)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Usage Chart Style") {
            Picker("Chart Style", selection: $settingsStore.settings.usageChartStyle) {
                ForEach(UsageChartStyle.allCases) { style in
                    Label(style.displayName, systemImage: style.systemImage).tag(style)
                }
            }
            Text("Choose how each usage limit is drawn. This applies to the app overview and the widget.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Live preview so the choice is obvious before saving.
            UsageMeterView(
                limit: UsageLimit(id: "preview", kind: "preview", label: "Preview", percent: 68, resetsAt: nil),
                style: settingsStore.settings.usageChartStyle,
                compact: false,
                showReset: false
            )
            .padding(.vertical, 4)
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

            if settingsStore.settings.localProjectAnalyticsEnabled {
                Picker("Auto-refresh", selection: $settingsStore.settings.projectAnalyticsRefreshInterval) {
                    ForEach(ProjectAnalyticsRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                Text("How often the Projects page re-scans local logs in the background. Data is scanned once on launch when older than this interval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private func openStatuslineFolder() {
        let folderURL = StatuslineUsageProvider.defaultFileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folderURL)
    }

    private func openCodexSessionsFolder() {
        let path = (settingsStore.settings.codexSessionsPath as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func sourceBinding(_ source: UsageDisplaySource) -> Binding<Bool> {
        Binding(
            get: {
                settingsStore.settings.visibleUsageSources.contains(source)
            },
            set: { isVisible in
                var sources = settingsStore.settings.visibleUsageSources
                if isVisible {
                    sources.insert(source)
                } else if sources.count > 1 {
                    sources.remove(source)
                }
                settingsStore.settings.visibleUsageSources = sources
            }
        )
    }
}
