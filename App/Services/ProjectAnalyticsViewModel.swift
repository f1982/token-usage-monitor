import Combine
import Foundation

/// Drives the Projects page: runs opt-in JSONL scans off the main thread,
/// caches aggregate-only summaries, and reloads widget timelines.
@MainActor
final class ProjectAnalyticsViewModel: ObservableObject {
    @Published var range: ProjectUsageTimeRange
    @Published private(set) var summaries: [ProjectUsageSummary] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusNote: String?
    @Published private(set) var generatedAt: Date?

    private let settingsStore: UsageSettingsStore
    private let cacheStore: ProjectUsageCacheStoring
    private let makeProvider: (String) -> ProjectUsageProviding
    private let reloadWidgets: () -> Void
    private let now: () -> Date

    /// True once a scan (or cache load) has produced data for the current state.
    private(set) var hasScanned = false

    init(
        settingsStore: UsageSettingsStore,
        cacheStore: ProjectUsageCacheStoring = ProjectUsageCacheStore(),
        makeProvider: @escaping (String) -> ProjectUsageProviding = { LocalProjectUsageProvider(rootPath: $0) },
        reloadWidgets: @escaping () -> Void = {},
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.cacheStore = cacheStore
        self.makeProvider = makeProvider
        self.reloadWidgets = reloadWidgets
        self.now = now
        self.range = settingsStore.settings.projectAnalyticsDefaultRange

        if settingsStore.settings.localProjectAnalyticsEnabled, let cache = cacheStore.read() {
            summaries = cache.summaries
            range = cache.timeRange
            generatedAt = cache.generatedAt
            hasScanned = true
        }
    }

    var isEnabled: Bool {
        settingsStore.settings.localProjectAnalyticsEnabled
    }

    /// Background prefetch entry point. Scans only when analytics is enabled
    /// and the cached summaries are older than the user's chosen refresh
    /// interval (or missing). Fresh cache and `manual` mode short-circuit so
    /// launching the app doesn't re-scan on every open.
    func refreshIfStale() async {
        guard isEnabled, !isScanning else { return }
        guard let maxAge = settingsStore.settings.projectAnalyticsRefreshInterval.seconds else { return }

        if let generatedAt, now().timeIntervalSince(generatedAt) < maxAge {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard isEnabled, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        statusNote = nil

        let rootPath = settingsStore.settings.claudeProjectsPath
        let provider = makeProvider(rootPath)
        let selectedRange = range

        do {
            let result = try await provider.fetchProjectSummaries(range: selectedRange, now: now())
            summaries = result
            generatedAt = now()
            hasScanned = true
            cacheStore.write(ProjectUsageCache(
                schemaVersion: ProjectUsageCacheStore.schemaVersion,
                generatedAt: now(),
                rootPath: rootPath,
                timeRange: selectedRange,
                summaries: result
            ))
            reloadWidgets()
        } catch let error as ProjectScanError {
            statusNote = error.message
        } catch {
            statusNote = "Could not scan Claude project logs."
        }
    }
}
