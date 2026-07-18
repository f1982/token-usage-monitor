import XCTest

// MARK: - Mocks

private final class MockAggregator: QuotaAggregating, @unchecked Sendable {
    var results: [QuotaAggregationResult] = []
    private(set) var callCount = 0

    func fetchQuota() async -> QuotaAggregationResult {
        callCount += 1
        guard !results.isEmpty else {
            XCTFail("unexpected fetchQuota call")
            return QuotaAggregationResult(snapshot: nil, providerID: nil, failureNote: "no stubbed result")
        }
        return results.removeFirst()
    }
}

private final class MockCacheStore: UsageCacheStoring, @unchecked Sendable {
    var stored: ClaudeUsageSnapshot?
    private(set) var writeCount = 0

    func read() -> ClaudeUsageSnapshot? { stored }
    func write(_ snapshot: ClaudeUsageSnapshot) {
        stored = snapshot
        writeCount += 1
    }
}

private final class MockCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    var limits: [UsageLimit] = []
    private(set) var callCount = 0

    func fetchCodexLimits() async -> [UsageLimit] {
        callCount += 1
        return limits
    }
}

private final class MutableClock: @unchecked Sendable {
    var current = Date(timeIntervalSince1970: 1_751_700_000)
    func advance(by interval: TimeInterval) { current = current.addingTimeInterval(interval) }
}

// MARK: - Tests

@MainActor
final class UsageRefreshServiceTests: XCTestCase {
    private func makeSnapshot(
        fetchedAt: Date,
        percent: Double = 31,
        provenance: UsageProvenance? = .official
    ) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: true,
            session: UsageLimit(id: "session-0", kind: "session", label: "Session", percent: 42, resetsAt: nil),
            weekly: UsageLimit(id: "weekly_all-1", kind: "weekly_all", label: "All models", percent: percent, resetsAt: nil),
            weeklyScoped: [],
            note: nil,
            fetchedAt: fetchedAt,
            provenance: provenance
        )
    }

    private func makeService(
        aggregator: MockAggregator,
        cache: MockCacheStore,
        clock: MutableClock,
        codexUsageProvider: CodexUsageProviding? = nil,
        reloadWidgets: @escaping () -> Void = {}
    ) -> UsageRefreshService {
        UsageRefreshService(
            aggregator: aggregator,
            codexUsageProvider: codexUsageProvider,
            cacheStore: cache,
            historyStore: UsageHistoryStore(fileURL: nil),
            reloadWidgets: reloadWidgets,
            now: { clock.current }
        )
    }

    func testFreshCacheAvoidsAggregator() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        cache.stored = makeSnapshot(fetchedAt: clock.current.addingTimeInterval(-60))

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock)
        let result = await service.refresh()

        XCTAssertEqual(aggregator.callCount, 0)
        XCTAssertEqual(result, cache.stored)
    }

    func testStaleCacheTriggersFetchAndWritesCache() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        cache.stored = makeSnapshot(fetchedAt: clock.current.addingTimeInterval(-10 * 60), percent: 10)
        let fresh = makeSnapshot(fetchedAt: clock.current, percent: 50)
        aggregator.results = [QuotaAggregationResult(snapshot: fresh, providerID: .statusline, failureNote: nil)]

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock)
        let result = await service.refresh()

        XCTAssertEqual(aggregator.callCount, 1)
        XCTAssertEqual(result, fresh)
        XCTAssertEqual(cache.stored, fresh)
        XCTAssertEqual(cache.writeCount, 1)
    }

    func testSuccessfulRefreshMergesCodexLimits() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        let codexProvider = MockCodexUsageProvider()
        codexProvider.limits = [
            UsageLimit(
                id: "codex-primary",
                kind: "codex_primary",
                label: "Codex 5h",
                percent: 34,
                resetsAt: Date(timeIntervalSince1970: 1_783_341_600)
            ),
        ]
        aggregator.results = [
            QuotaAggregationResult(snapshot: makeSnapshot(fetchedAt: clock.current), providerID: .statusline, failureNote: nil),
        ]

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock, codexUsageProvider: codexProvider)
        let result = await service.refresh()

        XCTAssertEqual(codexProvider.callCount, 1)
        XCTAssertEqual(result.codex, codexProvider.limits)
        XCTAssertEqual(cache.stored?.codex, codexProvider.limits)
    }

    func testSuccessfulClaudeRefreshPreservesCachedCodexWhenCodexReadFails() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        let codexUsageProvider = MockCodexUsageProvider()
        let previousCodex = [
            UsageLimit(id: "codex-primary", kind: "codex_primary", label: "Codex 5h", percent: 22, resetsAt: nil),
        ]
        var cached = makeSnapshot(fetchedAt: clock.current.addingTimeInterval(-10 * 60))
        cached.codex = previousCodex
        cached.available = true
        cache.stored = cached
        aggregator.results = [
            QuotaAggregationResult(
                snapshot: makeSnapshot(fetchedAt: clock.current, percent: 50),
                providerID: .statusline,
                failureNote: nil
            ),
        ]

        let service = makeService(
            aggregator: aggregator,
            cache: cache,
            clock: clock,
            codexUsageProvider: codexUsageProvider
        )
        let result = await service.refresh()

        XCTAssertEqual(result.codex, previousCodex)
        XCTAssertTrue(result.available)
    }

    func testForcedRefreshBypassesFreshCache() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        cache.stored = makeSnapshot(fetchedAt: clock.current.addingTimeInterval(-30))
        aggregator.results = [
            QuotaAggregationResult(snapshot: makeSnapshot(fetchedAt: clock.current, percent: 60), providerID: .statusline, failureNote: nil),
        ]

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock)
        _ = await service.refresh(force: true)

        XCTAssertEqual(aggregator.callCount, 1)
    }

    func testFailureReturnsStaleCacheWithNote() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        let stale = makeSnapshot(fetchedAt: clock.current.addingTimeInterval(-10 * 60))
        cache.stored = stale
        aggregator.results = [
            QuotaAggregationResult(snapshot: nil, providerID: nil, failureNote: "Official statusline data not available."),
        ]

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock)
        let result = await service.refresh()

        XCTAssertEqual(result.note, "Official statusline data not available.")
        XCTAssertEqual(result.weekly, stale.weekly)
        XCTAssertEqual(cache.writeCount, 0, "stale result must not overwrite cache")
    }

    func testClaudeFailureStillCachesFreshCodexUsageForWidget() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        let codexProvider = MockCodexUsageProvider()
        let codexLimits = [
            UsageLimit(id: "codex-codex-10080", kind: "codex_codex_10080", label: "Codex weekly", percent: 1, resetsAt: nil),
        ]
        codexProvider.limits = codexLimits
        cache.stored = makeSnapshot(fetchedAt: clock.current.addingTimeInterval(-10 * 60))
        aggregator.results = [
            QuotaAggregationResult(snapshot: nil, providerID: nil, failureNote: "Official statusline data not available."),
        ]
        var reloadCount = 0
        let service = makeService(
            aggregator: aggregator,
            cache: cache,
            clock: clock,
            codexUsageProvider: codexProvider,
            reloadWidgets: { reloadCount += 1 }
        )

        let result = await service.refresh()

        XCTAssertEqual(result.codex, codexLimits)
        XCTAssertEqual(cache.stored?.codex, codexLimits)
        XCTAssertEqual(cache.writeCount, 1)
        XCTAssertEqual(reloadCount, 1)
    }

    func testFailureWithoutCacheReturnsUnavailable() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        aggregator.results = [
            QuotaAggregationResult(snapshot: nil, providerID: nil, failureNote: "Official statusline data not available."),
        ]

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock)
        let result = await service.refresh()

        XCTAssertFalse(result.available)
        XCTAssertEqual(result.note, "Official statusline data not available.")
    }

    func testSuccessfulRefreshReloadsWidgets() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        aggregator.results = [
            QuotaAggregationResult(snapshot: makeSnapshot(fetchedAt: clock.current), providerID: .statusline, failureNote: nil),
        ]
        var reloadCount = 0

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock, reloadWidgets: { reloadCount += 1 })
        _ = await service.refresh()

        XCTAssertEqual(reloadCount, 1)
    }

    func testFailedRefreshDoesNotReloadWidgets() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        aggregator.results = [
            QuotaAggregationResult(snapshot: nil, providerID: nil, failureNote: "Could not read statusline data."),
        ]
        var reloadCount = 0

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock, reloadWidgets: { reloadCount += 1 })
        let result = await service.refresh()

        XCTAssertEqual(reloadCount, 0)
        XCTAssertEqual(result.note, "Could not read statusline data.")
    }

    func testConcurrentRefreshesAreCoalesced() async {
        let aggregator = MockAggregator()
        let cache = MockCacheStore()
        let clock = MutableClock()
        aggregator.results = [
            QuotaAggregationResult(snapshot: makeSnapshot(fetchedAt: clock.current), providerID: .statusline, failureNote: nil),
        ]

        let service = makeService(aggregator: aggregator, cache: cache, clock: clock)
        async let first = service.refresh()
        async let second = service.refresh()
        let (a, b) = await (first, second)

        XCTAssertEqual(aggregator.callCount, 1)
        XCTAssertEqual(a, b)
    }
}
