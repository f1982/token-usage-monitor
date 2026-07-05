import SwiftUI
import WidgetKit

struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageTimelineProvider()) { entry in
            ClaudeUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Shows your Claude Code session and weekly usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
