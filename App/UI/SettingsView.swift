import AppKit
import SwiftUI
import WidgetKit

struct SettingsView: View {
    private static let privacyPolicyURL = URL(string: "https://github.com/f1982/token-usage-monitor/blob/develop/PRIVACY.md")!
    private static let supportURL = URL(string: "https://github.com/f1982/token-usage-monitor/blob/develop/SUPPORT.md")!

    @EnvironmentObject private var settingsStore: UsageSettingsStore
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var analytics: ProjectAnalyticsViewModel
    private let bookmarkStore = ScopedBookmarkStore()
    private let oauthTokenReader = ClaudeTokenReader()
    @State private var oauthTokenInput = ""

    var body: some View {
        Form {
            displaySection
            quotaSourceSection
            codexSection
            appearanceSection
            projectAnalyticsSection
            experimentalSection
            localDataSection
            privacySection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: settingsStore.settings.quotaSourceMode) { _, _ in
            Task { await refreshService.refresh(force: true) }
        }
        .onChange(of: settingsStore.settings.experimentalOAuthEnabled) { _, _ in
            if settingsStore.settings.experimentalOAuthEnabled {
                settingsStore.settings.quotaSourceMode = .statuslineThenLocalThenOAuth
            }
            Task { await refreshService.refresh(force: true) }
        }
        .onChange(of: settingsStore.settings.visibleUsageSources) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
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
            Toggle("Show session usage in menu bar", isOn: $settingsStore.settings.menuBarUsageEnabled)
            Text("Choose which usage products appear in the overview and widget. At least one source stays enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("When enabled, the Mac menu bar shows Claude Code session quota and Codex session tokens/context usage.")
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
        let exists = bookmarkStore.withAccess(for: .statusline) { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("latest.json").path)
        } ?? false
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
                Button("Choose Statusline Folder") {
                    chooseDirectory(for: .statusline)
                }
                Button("Open Statusline Folder") {
                    openStatuslineFolder()
                }
                Button("Refresh Status") {
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(refreshService.isRefreshing)
            }
            accessActions(for: .statusline)
        }
        .padding(.vertical, 2)
    }

    private var codexSection: some View {
        Section("Codex") {
            Text(settingsStore.settings.codexSessionsPath)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            Text("Reads current account limits through the installed Codex CLI when available. Local session JSONL is used as a fallback; prompt and message content are not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Choose Codex Sessions Folder") {
                    chooseDirectory(for: .codexSessions)
                }
                Button("Open Codex Sessions Folder") {
                    openCodexSessionsFolder()
                }
                Button("Refresh Codex Usage") {
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(refreshService.isRefreshing)
            }
            accessActions(for: .codexSessions)
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

            Text(settingsStore.settings.claudeProjectsPath)
                .font(.caption.monospaced())
                .textSelection(.enabled)

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
                Button("Choose Claude Projects Folder") {
                    chooseDirectory(for: .claudeProjects)
                }
                Button("Open Claude Projects Folder") {
                    openProjectsFolder()
                }
                Button("Refresh Project Analytics") {
                    Task { await analytics.refresh() }
                }
                .disabled(!settingsStore.settings.localProjectAnalyticsEnabled || analytics.isScanning)
            }

            accessActions(for: .claudeProjects)

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
            SecureField("Paste OAuth token", text: $oauthTokenInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save Token") {
                    guard oauthTokenReader.saveToken(oauthTokenInput) else { return }
                    oauthTokenInput = ""
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(oauthTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove Token", role: .destructive) {
                    oauthTokenReader.removeToken()
                    settingsStore.settings.experimentalOAuthEnabled = false
                }
                .disabled(oauthTokenReader.readToken() == nil)
            }
            Text("Run `claude setup-token` in Terminal, then paste the generated long-lived token here. When enabled, live OAuth usage is preferred over statusline data. The token is stored in the macOS Keychain; no Claude Code credential file is read.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var localDataSection: some View {
        Section("Local Data") {
            Text("Usage totals, project summaries, and usage history are stored in the shared App Group container so the widget can display them. Raw logs and OAuth tokens are not cached.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear Cached Usage Data", role: .destructive) {
                refreshService.clearCachedData()
                analytics.clearCachedData()
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Text("All data stays on this Mac. Raw logs, prompt text, and message content are never stored or uploaded. Only aggregated token totals are cached for the widget.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Privacy Policy") { NSWorkspace.shared.open(Self.privacyPolicyURL) }
                Button("Support") { NSWorkspace.shared.open(Self.supportURL) }
            }
        }
    }

    private func openProjectsFolder() {
        if let url = bookmarkStore.resolve(.claudeProjects) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openStatuslineFolder() {
        if let url = bookmarkStore.resolve(.statusline) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openCodexSessionsFolder() {
        if let url = bookmarkStore.resolve(.codexSessions) {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseDirectory(for key: ScopedBookmarkStore.Key) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow Access"

        guard panel.runModal() == .OK,
              let url = panel.url,
              bookmarkStore.save(url, for: key) else { return }

        switch key {
        case .claudeProjects:
            settingsStore.settings.claudeProjectsPath = url.path
            settingsStore.settings.localProjectAnalyticsEnabled = true
            Task { await analytics.refresh() }
        case .codexSessions:
            settingsStore.settings.codexSessionsPath = url.path
            Task { await refreshService.refresh(force: true) }
        case .statusline:
            Task { await refreshService.refresh(force: true) }
        }
    }

    @ViewBuilder
    private func accessActions(for key: ScopedBookmarkStore.Key) -> some View {
        HStack {
            Button("Re-authorize") { chooseDirectory(for: key) }
            Button("Revoke Access", role: .destructive) { revokeAccess(for: key) }
                .disabled(!bookmarkStore.hasBookmark(for: key))
        }
    }

    private func revokeAccess(for key: ScopedBookmarkStore.Key) {
        bookmarkStore.remove(key)
        switch key {
        case .claudeProjects:
            settingsStore.settings.claudeProjectsPath = UsageSettings.default.claudeProjectsPath
            settingsStore.settings.localProjectAnalyticsEnabled = false
            analytics.clearCachedData()
        case .codexSessions:
            settingsStore.settings.codexSessionsPath = UsageSettings.default.codexSessionsPath
            Task { await refreshService.refresh(force: true) }
        case .statusline:
            Task { await refreshService.refresh(force: true) }
        }
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
