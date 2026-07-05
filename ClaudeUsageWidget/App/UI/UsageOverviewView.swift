import SwiftUI

struct UsageOverviewView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Code Usage")
                .font(.title2)
                .bold()

            if let snapshot = refreshService.snapshot {
                if snapshot.hasAnyUsage {
                    usageCards(for: snapshot)
                } else {
                    Text("Usage unavailable")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
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
    private func usageCards(for snapshot: ClaudeUsageSnapshot) -> some View {
        if let weekly = snapshot.weekly {
            UsageLimitRow(limit: weekly)
        }
        if let session = snapshot.session {
            UsageLimitRow(limit: session)
        }
        if !snapshot.weeklyScoped.isEmpty {
            Divider()
            ForEach(snapshot.weeklyScoped) { limit in
                UsageLimitRow(limit: limit)
            }
        }
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
