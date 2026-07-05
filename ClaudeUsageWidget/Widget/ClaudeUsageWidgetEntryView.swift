import SwiftUI
import WidgetKit

struct ClaudeUsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: ClaudeUsageWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if snapshot.hasAnyUsage {
                    usageView(snapshot)
                } else {
                    unavailableView(note: snapshot.note)
                }
            } else {
                noCacheView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - States

    private var noCacheView: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open app to load Claude usage")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(note: String?) -> some View {
        VStack(spacing: 6) {
            Text("Usage unavailable")
                .font(.caption)
                .bold()
            if let note, family != .systemSmall {
                Text(note)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func usageView(_ snapshot: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Code")
                .font(.caption)
                .bold()

            // Medium widget with cached project analytics: compact quota line
            // plus top projects. Small widget stays quota-only.
            if family == .systemMedium, !entry.topProjects.isEmpty {
                compactQuotaLine(snapshot)
                topProjectsSection
            } else {
                if let weekly = snapshot.weekly {
                    limitRow(weekly)
                }
                if let session = snapshot.session {
                    limitRow(session)
                }
                if family == .systemMedium {
                    ForEach(snapshot.weeklyScoped.prefix(2)) { limit in
                        limitRow(limit)
                    }
                }
            }

            Spacer(minLength: 0)

            footer(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func compactQuotaLine(_ snapshot: ClaudeUsageSnapshot) -> some View {
        var parts: [String] = []
        if let weekly = snapshot.weekly {
            parts.append("Weekly \(UsageDisplayFormatting.shortPercentText(weekly.percent))")
        }
        if let session = snapshot.session {
            parts.append("Session \(UsageDisplayFormatting.shortPercentText(session.percent))")
        }
        return Text(parts.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var topProjectsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Top Projects · \(entry.projectsRange?.shortLabel ?? "7d")")
                .font(.caption2)
                .bold()
                .padding(.top, 2)
            // Project names only — never full file paths in the widget.
            ForEach(entry.topProjects) { project in
                HStack {
                    Text(project.projectName)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                    Text(UsageDisplayFormatting.compactTokenText(project.totalTokens))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func limitRow(_ limit: UsageLimit) -> some View {
        UsageMeterView(limit: limit, style: entry.chartStyle, compact: true, showReset: false)
    }

    private func footer(_ snapshot: ClaudeUsageSnapshot) -> some View {
        let age = UsageDisplayFormatting.cacheAgeText(fetchedAt: snapshot.fetchedAt, now: entry.date)
        let isStale = entry.date.timeIntervalSince(snapshot.fetchedAt) > 5 * 60

        return HStack {
            Text(isStale ? "Cached · \(age)" : age)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if family == .systemMedium,
               let resetText = UsageDisplayFormatting.resetText(
                   for: snapshot.weekly?.resetsAt ?? snapshot.session?.resetsAt,
                   now: entry.date
               ) {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
