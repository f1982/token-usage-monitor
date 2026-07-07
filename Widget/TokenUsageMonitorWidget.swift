import SwiftUI
import WidgetKit

struct TokenUsageMonitorWidget: Widget {
    let kind = "TokenUsageMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageTimelineProvider()) { entry in
            TokenUsageMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Code Usage")
        .description("Shows your Claude Code and Codex usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
