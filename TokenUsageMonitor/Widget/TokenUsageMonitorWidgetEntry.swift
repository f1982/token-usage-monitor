import Foundation
import WidgetKit

struct TokenUsageMonitorWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ClaudeUsageSnapshot?
    var topProjects: [ProjectUsageSummary] = []
    var projectsRange: ProjectUsageTimeRange?
    var chartStyle: UsageChartStyle = .progressBar

    static func placeholder(date: Date = Date()) -> TokenUsageMonitorWidgetEntry {
        TokenUsageMonitorWidgetEntry(
            date: date,
            snapshot: ClaudeUsageSnapshot(
                available: true,
                session: UsageLimit(id: "session", kind: "session", label: "Session", percent: 42, resetsAt: nil),
                weekly: UsageLimit(id: "weekly", kind: "weekly_all", label: "All models", percent: 31, resetsAt: nil),
                weeklyScoped: [],
                note: nil,
                fetchedAt: date
            )
        )
    }
}
