import Foundation
import WidgetKit

/// Reads the cached quota snapshot and (when Local Project Analytics is
/// enabled) the aggregated project usage cache from the App Group container.
/// The widget never reads credentials, JSONL logs, or the usage endpoint.
struct ClaudeUsageTimelineProvider: TimelineProvider {
    static let topProjectCount = 3

    let cacheStore = UsageCacheStore()
    let projectCacheStore = ProjectUsageCacheStore()

    func placeholder(in context: Context) -> TokenUsageMonitorWidgetEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenUsageMonitorWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder())
            return
        }
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenUsageMonitorWidgetEntry>) -> Void) {
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [makeEntry()], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> TokenUsageMonitorWidgetEntry {
        let settings = UsageSettingsStore.readShared()
        let visibleSnapshot = cacheStore.read()?.filtered(visibleSources: settings.visibleUsageSources)
        var entry = TokenUsageMonitorWidgetEntry(date: Date(), snapshot: visibleSnapshot)
        entry.chartStyle = settings.usageChartStyle
        if settings.localProjectAnalyticsEnabled, let cache = projectCacheStore.read() {
            entry.topProjects = Array(cache.summaries.prefix(Self.topProjectCount))
            entry.projectsRange = cache.timeRange
        }
        return entry
    }
}
