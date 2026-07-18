import Charts
import SwiftUI

struct UsageOverviewView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var settingsStore: UsageSettingsStore
    @EnvironmentObject private var codexSessionMonitor: CodexSessionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Code Usage")
                .font(.title2)
                .bold()

            if settingsStore.settings.visibleUsageSources.contains(.codex) {
                codexSessionCard
            }

            if let snapshot = refreshService.snapshot {
                usageSections(for: snapshot, visibleSources: settingsStore.settings.visibleUsageSources)
                historySection
            } else {
                Text("Loading usage…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }

            Divider()
            footer
        }
        .padding(20)
    }

    @ViewBuilder
    private func usageSections(for snapshot: ClaudeUsageSnapshot, visibleSources: Set<UsageDisplaySource>) -> some View {
        let showsClaude = visibleSources.contains(.claudeCode)
        let showsCodex = visibleSources.contains(.codex)

        if !showsClaude && !showsCodex {
            unavailableText("Usage unavailable")
        } else {
            if showsClaude {
                sourceHeader("Claude Code")
                if snapshot.hasClaudeUsage {
                    claudeUsageCards(for: snapshot)
                } else {
                    unavailableText("Claude Code usage unavailable")
                }
            }

            if showsClaude && showsCodex {
                Divider()
            }

            if showsCodex {
                sourceHeader("Codex")
                if snapshot.hasCodexUsage {
                    codexUsageCards(for: snapshot)
                } else {
                    unavailableText("Codex usage unavailable")
                }
            }
        }
    }

    @ViewBuilder
    private var codexSessionCard: some View {
        if let session = codexSessionMonitor.session {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(session.isActive ? "Live session" : "Idle session", systemImage: session.isActive ? "circle.fill" : "pause.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(session.isActive ? .green : .secondary)
                    Spacer()
                    Text(UsageDisplayFormatting.cacheAgeText(fetchedAt: session.lastEventAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let model = session.model { metadataRow("Model", model) }
                if let provider = session.provider { metadataRow("Provider", provider) }
                if let client = session.client { metadataRow("Client", client) }
                if let workingDirectory = session.workingDirectory {
                    metadataRow("Project", URL(fileURLWithPath: workingDirectory).lastPathComponent)
                    metadataRow("Folder", workingDirectory)
                }
                if let totalTokens = session.totalTokens {
                    metadataRow("Tokens", UsageDisplayFormatting.groupedNumberText(totalTokens))
                }
                if let contextWindow = session.contextWindow {
                    metadataRow("Context", UsageDisplayFormatting.groupedNumberText(contextWindow))
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex session not detected")
                        .font(.subheadline.weight(.medium))
                    Text("Checking ~/.codex/sessions every 10 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func claudeUsageCards(for snapshot: ClaudeUsageSnapshot) -> some View {
        let style = settingsStore.settings.usageChartStyle
        if let weekly = snapshot.weekly {
            UsageLimitRow(limit: weekly, style: style)
        }
        if let session = snapshot.session {
            UsageLimitRow(limit: session, style: style)
        }
        if !snapshot.weeklyScoped.isEmpty {
            Divider()
            ForEach(snapshot.weeklyScoped) { limit in
                UsageLimitRow(limit: limit, style: style)
            }
        }
    }

    private func codexUsageCards(for snapshot: ClaudeUsageSnapshot) -> some View {
        let style = settingsStore.settings.usageChartStyle
        return ForEach(snapshot.codex) { limit in
            UsageLimitRow(limit: limit, style: style)
        }
    }

    private func sourceHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    @ViewBuilder
    private var historySection: some View {
        let points = Array(refreshService.history.suffix(48))
        if points.count >= 2 {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent trend")
                    .font(.headline)
                Chart(points) { point in
                    if let weekly = point.weeklyPercent {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Used", weekly)
                        )
                        .foregroundStyle(by: .value("Limit", "Weekly"))
                    }
                    if let session = point.sessionPercent {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Used", session)
                        )
                        .foregroundStyle(by: .value("Limit", "Session"))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100])
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 140)
                Text("Stored locally for the last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func unavailableText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = refreshService.snapshot?.note {
                ErrorNoteView(note: note)
            }
            HStack {
                if let provenance = refreshService.snapshot?.provenance {
                    Text("Claude source: \(provenance.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                dataHealthLabel
                Spacer()
                if refreshService.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(refreshService.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(refreshService.isRefreshing)
                .help("Fetch the latest available usage data")
            }
        }
    }

    @ViewBuilder
    private var dataHealthLabel: some View {
        if refreshService.isRefreshing {
            Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else if refreshService.snapshot?.provenance != nil,
                  let fetchedAt = refreshService.snapshot?.fetchedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let age = context.date.timeIntervalSince(fetchedAt)
                let isStale = age >= UsageRefreshService.cacheTTL
                Label(
                    isStale ? "Claude stale · \(UsageDisplayFormatting.cacheAgeText(fetchedAt: fetchedAt, now: context.date))" :
                        "Claude updated \(UsageDisplayFormatting.cacheAgeText(fetchedAt: fetchedAt, now: context.date))",
                    systemImage: isStale ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .foregroundStyle(isStale ? .orange : .secondary)
                .font(.caption)
                .help("Last source update: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }
}
