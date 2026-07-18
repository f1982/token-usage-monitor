import XCTest

// MARK: - Stubs

private final class StubProvider: UsageProvider, @unchecked Sendable {
    let id: UsageProviderID
    let provenance: UsageProvenance
    var displayName: String { id.rawValue }

    var results: [UsageProviderResult<ClaudeUsageSnapshot>]
    private(set) var callCount = 0

    init(id: UsageProviderID, provenance: UsageProvenance, results: [UsageProviderResult<ClaudeUsageSnapshot>]) {
        self.id = id
        self.provenance = provenance
        self.results = results
    }

    func fetchQuotaUsage() async -> UsageProviderResult<ClaudeUsageSnapshot> {
        callCount += 1
        guard !results.isEmpty else {
            return .failure(.unavailable, provenance: provenance, fetchedAt: Date(timeIntervalSince1970: 0))
        }
        return results.count == 1 ? results[0] : results.removeFirst()
    }
}

// MARK: - Tests

@MainActor
final class UsageAggregatorServiceTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_751_700_000)

    private func snapshot(provenance: UsageProvenance) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: true,
            session: nil,
            weekly: UsageLimit(id: "weekly", kind: "weekly_all", label: "All models", percent: 42, resetsAt: nil),
            weeklyScoped: [],
            note: nil,
            fetchedAt: baseDate,
            provenance: provenance
        )
    }

    private func success(_ id: UsageProviderID, _ provenance: UsageProvenance) -> StubProvider {
        StubProvider(id: id, provenance: provenance, results: [
            .success(snapshot(provenance: provenance), provenance: provenance, fetchedAt: baseDate),
        ])
    }

    private func failing(_ id: UsageProviderID, _ provenance: UsageProvenance, error: UsageProviderError) -> StubProvider {
        StubProvider(id: id, provenance: provenance, results: [
            .failure(error, provenance: provenance, fetchedAt: baseDate),
        ])
    }

    private func settings(
        mode: QuotaSourceMode,
        oauthEnabled: Bool = false
    ) -> UsageSettings {
        var settings = UsageSettings.default
        settings.quotaSourceMode = mode
        settings.experimentalOAuthEnabled = oauthEnabled
        return settings
    }

    private func makeService(
        settings: UsageSettings,
        providers: [UsageProvider],
        now: @escaping () -> Date
    ) -> UsageAggregatorService {
        UsageAggregatorService(settingsProvider: { settings }, providers: providers, now: now)
    }

    func testOptInOAuthSelectedBeforeFreshStatusline() async {
        let statusline = success(.statusline, .official)
        let oauth = success(.oauthExperimental, .experimental)
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalThenOAuth, oauthEnabled: true),
            providers: [statusline, oauth],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertEqual(result.providerID, .oauthExperimental)
        XCTAssertEqual(result.snapshot?.provenance, .experimental)
        XCTAssertEqual(statusline.callCount, 0, "complete live data should not be replaced by statusline")
    }

    func testLocalFallbackNotUsedWhenDisabled() async {
        let statusline = failing(.statusline, .official, error: .missing)
        let local = success(.localEstimate, .localEstimate)
        let service = makeService(
            settings: settings(mode: .officialStatuslineOnly),
            providers: [statusline, local],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertNil(result.snapshot)
        XCTAssertEqual(local.callCount, 0)
        XCTAssertEqual(
            result.failureNote,
            "Official statusline data not available. Enable fallback sources in Settings if you want local estimates."
        )
    }

    func testOAuthFallbackNotUsedWhenDisabled() async {
        let statusline = failing(.statusline, .official, error: .missing)
        let local = failing(.localEstimate, .localEstimate, error: .unavailable)
        let oauth = success(.oauthExperimental, .experimental)
        // Mode allows OAuth in ordering, but the explicit toggle is off.
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalThenOAuth, oauthEnabled: false),
            providers: [statusline, local, oauth],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertNil(result.snapshot)
        XCTAssertEqual(oauth.callCount, 0)
    }

    func testLocalFallbackUsedWhenEnabledAndStatuslineMissing() async {
        let statusline = failing(.statusline, .official, error: .missing)
        let local = success(.localEstimate, .localEstimate)
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalEstimate),
            providers: [statusline, local],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertEqual(result.providerID, .localEstimate)
        XCTAssertEqual(result.snapshot?.provenance, .localEstimate)
    }

    func testStaleStatuslineFallsBackWhenEnabled() async {
        let statusline = failing(.statusline, .official, error: .staleData)
        let local = success(.localEstimate, .localEstimate)
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalEstimate),
            providers: [statusline, local],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertEqual(result.providerID, .localEstimate)
    }

    func testStaleSnapshotWithErrorDoesNotShortCircuitFallback() async {
        let stale = snapshot(provenance: .official)
        let statusline = StubProvider(id: .statusline, provenance: .official, results: [
            UsageProviderResult(
                value: stale,
                error: .staleData,
                provenance: .official,
                fetchedAt: baseDate
            ),
        ])
        let local = success(.localEstimate, .localEstimate)
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalEstimate),
            providers: [statusline, local],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertEqual(result.providerID, .localEstimate)
        XCTAssertEqual(result.snapshot?.provenance, .localEstimate)
    }

    func testOAuthUsedOnlyWhenExplicitlyEnabled() async {
        let statusline = failing(.statusline, .official, error: .missing)
        let oauth = success(.oauthExperimental, .experimental)
        // No local estimate provider registered — mirrors the shipped app.
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalThenOAuth, oauthEnabled: true),
            providers: [statusline, oauth],
            now: { self.baseDate }
        )

        let result = await service.fetchQuota()

        XCTAssertEqual(result.providerID, .oauthExperimental)
        XCTAssertEqual(result.snapshot?.provenance, .experimental)
    }

    func testOAuthRateLimitCooldownSkipsSubsequentAttempts() async {
        let statusline = failing(.statusline, .official, error: .missing)
        let oauth = StubProvider(id: .oauthExperimental, provenance: .experimental, results: [
            .failure(.rateLimited, provenance: .experimental, fetchedAt: baseDate),
            .success(snapshot(provenance: .experimental), provenance: .experimental, fetchedAt: baseDate),
        ])
        let clock = MutableAggregatorClock(current: baseDate)
        let service = makeService(
            settings: settings(mode: .statuslineThenLocalThenOAuth, oauthEnabled: true),
            providers: [statusline, oauth],
            now: { clock.current }
        )

        _ = await service.fetchQuota()
        XCTAssertEqual(oauth.callCount, 1)

        // Inside the cooldown window: OAuth is skipped entirely.
        clock.current = baseDate.addingTimeInterval(60)
        _ = await service.fetchQuota()
        XCTAssertEqual(oauth.callCount, 1)

        // After the cooldown, OAuth is attempted again.
        clock.current = baseDate.addingTimeInterval(3 * 60)
        let result = await service.fetchQuota()
        XCTAssertEqual(oauth.callCount, 2)
        XCTAssertEqual(result.providerID, .oauthExperimental)
    }

    func testProviderOrderMatchesSettings() {
        XCTAssertEqual(
            UsageAggregatorService.providerOrder(for: settings(mode: .officialStatuslineOnly)),
            [.statusline]
        )
        XCTAssertEqual(
            UsageAggregatorService.providerOrder(for: settings(mode: .statuslineThenLocalEstimate)),
            [.statusline, .localEstimate]
        )
        XCTAssertEqual(
            UsageAggregatorService.providerOrder(for: settings(mode: .statuslineThenLocalThenOAuth, oauthEnabled: true)),
            [.oauthExperimental, .statusline, .localEstimate]
        )
        XCTAssertEqual(
            UsageAggregatorService.providerOrder(for: settings(mode: .statuslineThenLocalThenOAuth, oauthEnabled: false)),
            [.statusline, .localEstimate]
        )
    }
}

private final class MutableAggregatorClock: @unchecked Sendable {
    var current: Date
    init(current: Date) { self.current = current }
}
