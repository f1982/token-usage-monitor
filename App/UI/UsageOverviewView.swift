import Charts
import SwiftUI

struct UsageOverviewView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var settingsStore: UsageSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Code Usage")
                .font(.title2)
                .bold()

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
                    Text("Source: \(provenance.displayName)")
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
        } else if let fetchedAt = refreshService.snapshot?.fetchedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let age = context.date.timeIntervalSince(fetchedAt)
                let isStale = age >= UsageRefreshService.cacheTTL
                Label(
                    isStale ? "Stale · \(UsageDisplayFormatting.cacheAgeText(fetchedAt: fetchedAt, now: context.date))" :
                        "Updated \(UsageDisplayFormatting.cacheAgeText(fetchedAt: fetchedAt, now: context.date))",
                    systemImage: isStale ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .foregroundStyle(isStale ? .orange : .secondary)
                .font(.caption)
                .help("Last source update: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }
}
