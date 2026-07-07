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
                if let fetchedAt = refreshService.snapshot?.fetchedAt {
                    Text("Updated \(UsageDisplayFormatting.cacheAgeText(fetchedAt: fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if refreshService.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh") {
                    Task { await refreshService.refresh(force: true) }
                }
                .disabled(refreshService.isRefreshing)
            }
        }
    }
}
