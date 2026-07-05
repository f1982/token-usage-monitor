import SwiftUI
import WidgetKit

struct TokenUsageMonitorWidget: Widget {
    let kind = "TokenUsageMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageTimelineProvider()) { entry in
            TokenUsageMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Shows your Claude Code session and weekly usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
