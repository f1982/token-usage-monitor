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
    @Published private(set) var history: [UsageHistoryPoint]
    @Published private(set) var isRefreshing = false

    private let aggregator: QuotaAggregating
    private let codexUsageProvider: CodexUsageProviding?
    private let cacheStore: UsageCacheStoring
    private let historyStore: UsageHistoryStore
    private let reloadWidgets: () -> Void
    private let now: () -> Date

    private var refreshTask: Task<ClaudeUsageSnapshot, Never>?

    init(
        aggregator: QuotaAggregating,
        codexUsageProvider: CodexUsageProviding? = nil,
        cacheStore: UsageCacheStoring,
        historyStore: UsageHistoryStore = UsageHistoryStore(),
        reloadWidgets: @escaping () -> Void = {},
        now: @escaping () -> Date = Date.init
    ) {
        self.aggregator = aggregator
        self.codexUsageProvider = codexUsageProvider
        self.cacheStore = cacheStore
        self.historyStore = historyStore
        self.reloadWidgets = reloadWidgets
        self.now = now
        self.snapshot = cacheStore.read()
        self.history = historyStore.read()
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
            let updated = await addingCodexLimits(to: cached)
            if updated != cached {
                cacheStore.write(updated)
                reloadWidgets()
            }
            snapshot = updated
            return updated
        }

        let outcome = await aggregator.fetchQuota()

        if let fresh = outcome.snapshot {
            let updated = await addingCodexLimits(to: fresh, fallbackCodex: cached?.codex ?? [])
            cacheStore.write(updated)
            historyStore.append(snapshot: updated)
            history = historyStore.read()
            snapshot = updated
            reloadWidgets()
            return updated
        }

        return await publish(stale(cached, note: outcome.failureNote ?? "Usage data not available."))
    }

    private func publish(_ result: ClaudeUsageSnapshot) async -> ClaudeUsageSnapshot {
        let updated = await addingCodexLimits(to: result)
        snapshot = updated
        return updated
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

    private func addingCodexLimits(
        to snapshot: ClaudeUsageSnapshot,
        fallbackCodex: [UsageLimit] = []
    ) async -> ClaudeUsageSnapshot {
        guard let codexUsageProvider else { return snapshot }
        let codexLimits = await codexUsageProvider.fetchCodexLimits()

        var updated = snapshot
        if codexLimits.isEmpty {
            updated.codex = snapshot.codex.isEmpty ? fallbackCodex : snapshot.codex
        } else {
            updated.codex = codexLimits
        }
        updated.available = updated.hasAnyUsage
        return updated
    }
}
