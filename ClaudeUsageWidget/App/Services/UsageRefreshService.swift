import Combine
import Foundation

/// Orchestrates quota refresh: source selection (via the aggregator), cache
/// write, and widget reload. Applies the cache TTL and coalesces concurrent
/// refreshes. Provider ordering and fallback policy live in
/// `UsageAggregatorService`.
@MainActor
final class UsageRefreshService: ObservableObject {
    static let cacheTTL: TimeInterval = 5 * 60

    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var isRefreshing = false

    private let aggregator: QuotaAggregating
    private let cacheStore: UsageCacheStoring
    private let reloadWidgets: () -> Void
    private let now: () -> Date

    private var refreshTask: Task<ClaudeUsageSnapshot, Never>?

    init(
        aggregator: QuotaAggregating,
        cacheStore: UsageCacheStoring,
        reloadWidgets: @escaping () -> Void = {},
        now: @escaping () -> Date = Date.init
    ) {
        self.aggregator = aggregator
        self.cacheStore = cacheStore
        self.reloadWidgets = reloadWidgets
        self.now = now
        self.snapshot = cacheStore.read()
    }

    /// Refreshes usage. Fresh cache short-circuits unless `force` is true
    /// (manual refresh).
    @discardableResult
    func refresh(force: Bool = false) async -> ClaudeUsageSnapshot {
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task { await performRefresh(force: force) }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh(force: Bool) async -> ClaudeUsageSnapshot {
        isRefreshing = true
        defer { isRefreshing = false }

        let cached = cacheStore.read()
        let currentTime = now()

        if !force, let cached, currentTime.timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            snapshot = cached
            return cached
        }

        let outcome = await aggregator.fetchQuota()

        if let fresh = outcome.snapshot {
            cacheStore.write(fresh)
            snapshot = fresh
            reloadWidgets()
            return fresh
        }

        return publish(stale(cached, note: outcome.failureNote ?? "Usage data not available."))
    }

    private func publish(_ result: ClaudeUsageSnapshot) -> ClaudeUsageSnapshot {
        snapshot = result
        return result
    }

    /// Serves the stale cache with a note when available; otherwise an
    /// unavailable snapshot.
    private func stale(_ cached: ClaudeUsageSnapshot?, note: String) -> ClaudeUsageSnapshot {
        if var cached {
            cached.note = note
            return cached
        }
        return .unavailable(note: note, fetchedAt: now())
    }
}
