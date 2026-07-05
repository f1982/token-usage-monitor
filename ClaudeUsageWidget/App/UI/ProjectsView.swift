import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var settingsStore: UsageSettingsStore
    @EnvironmentObject private var analytics: ProjectAnalyticsViewModel

    var body: some View {
        Group {
            if settingsStore.settings.localProjectAnalyticsEnabled {
                enabledContent
            } else {
                disabledState
            }
        }
        .navigationTitle("Projects")
    }

    // MARK: - Disabled state

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Local Project Analytics is off.")
                .font(.headline)
            Text("Enable it in Settings to calculate per-project token usage from ~/.claude/projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Enabled content

    private var enabledContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Range", selection: $analytics.range) {
                    ForEach(ProjectUsageTimeRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                if analytics.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh") {
                    Task { await analytics.refresh() }
                }
                .disabled(analytics.isScanning)
            }

            if let note = analytics.statusNote {
                ErrorNoteView(note: note)
            }

            listOrEmptyState

            if let generatedAt = analytics.generatedAt {
                Text("Scanned \(UsageDisplayFormatting.cacheAgeText(fetchedAt: generatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .onChange(of: analytics.range) { _, _ in
            Task { await analytics.refresh() }
        }
        .task {
            if !analytics.hasScanned {
                await analytics.refresh()
            }
        }
    }

    @ViewBuilder
    private var listOrEmptyState: some View {
        if analytics.summaries.isEmpty {
            VStack(spacing: 6) {
                if !analytics.hasScanned {
                    Text("Click Refresh to scan local logs.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No token usage found for this time range.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(analytics.summaries) { summary in
                ProjectSummaryRow(summary: summary)
            }
            .listStyle(.inset)
        }
    }
}

struct ProjectSummaryRow: View {
    let summary: ProjectUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(summary.projectName)
                    .font(.headline)
                Spacer()
                Text("\(UsageDisplayFormatting.groupedNumberText(summary.totalTokens)) tokens")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !summary.models.isEmpty {
                Text("Models: \(summary.models.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Full path stays out of the primary row; secondary text only.
            if let path = summary.projectPath {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailLine: String {
        var parts: [String] = []
        parts.append("in \(UsageDisplayFormatting.groupedNumberText(summary.inputTokens))")
        parts.append("out \(UsageDisplayFormatting.groupedNumberText(summary.outputTokens))")
        parts.append("cache \(UsageDisplayFormatting.groupedNumberText(summary.cacheCreationTokens + summary.cacheReadTokens))")
        parts.append("\(summary.messageCount) messages")
        if let lastUsedAt = summary.lastUsedAt {
            parts.append("last used \(UsageDisplayFormatting.cacheAgeText(fetchedAt: lastUsedAt))")
        }
        return parts.joined(separator: " · ")
    }
}
