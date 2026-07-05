import Foundation
import os
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
        // TEMP diagnostics: trace why the snapshot cache read fails in the appex.
        let log = Logger(subsystem: "me.andycao.app.tokenusagemonitor", category: "widget")
        if let url = AppGroup.snapshotFileURL {
            log.error("snapshot url: \(url.path, privacy: .public)")
            log.error("file exists: \(FileManager.default.fileExists(atPath: url.path), privacy: .public)")
            do {
                let data = try Data(contentsOf: url)
                log.error("read ok: \(data.count, privacy: .public) bytes")
            } catch {
                log.error("read failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            log.error("snapshot url: NIL (containerURL failed)")
        }

        var entry = TokenUsageMonitorWidgetEntry(date: Date(), snapshot: cacheStore.read())
        log.error("entry snapshot nil: \(entry.snapshot == nil, privacy: .public)")

        let settings = UsageSettingsStore.readShared()
        entry.chartStyle = settings.usageChartStyle
        if settings.localProjectAnalyticsEnabled, let cache = projectCacheStore.read() {
            entry.topProjects = Array(cache.summaries.prefix(Self.topProjectCount))
            entry.projectsRange = cache.timeRange
        }
        return entry
    }
}
