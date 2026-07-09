import Foundation

struct QuotaAggregationResult {
    var snapshot: ClaudeUsageSnapshot?
    var providerID: UsageProviderID?
    var failureNote: String?
}

protocol QuotaAggregating {
    func fetchQuota() async -> QuotaAggregationResult
}

/// Selects the best quota source according to Settings. Providers only fetch;
/// this service owns the ordering: statusline first, then local estimate and
/// experimental OAuth only when the user enabled them.
@MainActor
final class UsageAggregatorService: QuotaAggregating {
    static let oauthRateLimitCooldown: TimeInterval = 2 * 60

    private let settingsProvider: () -> UsageSettings
    private let providers: [UsageProviderID: UsageProvider]
    private let now: () -> Date
    private var oauthRateLimitedUntil: Date?

    init(
        settingsProvider: @escaping () -> UsageSettings,
        providers: [UsageProvider],
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsProvider = settingsProvider
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.now = now
    }

    func fetchQuota() async -> QuotaAggregationResult {
        let settings = settingsProvider()
        var failures: [(id: UsageProviderID, error: UsageProviderError)] = []

        for providerID in Self.providerOrder(for: settings) {
            guard let provider = providers[providerID] else {
                failures.append((providerID, .unavailable))
                continue
            }
            // 429 cooldown: skip OAuth attempts (even forced ones) until it expires.
            if providerID == .oauthExperimental,
               let until = oauthRateLimitedUntil, now() < until {
                failures.append((providerID, .rateLimited))
                continue
            }

            let result = await provider.fetchQuotaUsage()
            // A provider may include a stale snapshot as diagnostic context,
            // but only an error-free value is eligible for selection. Stale
            // data must flow through the fallback chain instead of being
            // written back as a fresh cache entry.
            if let snapshot = result.value, result.error == nil {
                return QuotaAggregationResult(snapshot: snapshot, providerID: providerID, failureNote: nil)
            }

            let error = result.error ?? .unavailable
            if providerID == .oauthExperimental, error == .rateLimited {
                oauthRateLimitedUntil = now().addingTimeInterval(Self.oauthRateLimitCooldown)
            }
            failures.append((providerID, error))
        }

        return QuotaAggregationResult(
            snapshot: nil,
            providerID: nil,
            failureNote: Self.failureNote(for: failures, settings: settings)
        )
    }

    static func providerOrder(for settings: UsageSettings) -> [UsageProviderID] {
        var order: [UsageProviderID] = [.statusline]
        if settings.quotaSourceMode.allowsLocalEstimate {
            order.append(.localEstimate)
        }
        if settings.quotaSourceMode.allowsOAuth, settings.experimentalOAuthEnabled {
            order.append(.oauthExperimental)
        }
        return order
    }

    // MARK: - Failure notes

    static func failureNote(
        for failures: [(id: UsageProviderID, error: UsageProviderError)],
        settings: UsageSettings
    ) -> String {
        var parts = failures.map { message(for: $0.error, providerID: $0.id) }
        if settings.quotaSourceMode == .officialStatuslineOnly {
            parts.append("Enable fallback sources in Settings if you want local estimates.")
        }
        return parts.joined(separator: " ")
    }

    private static func message(for error: UsageProviderError, providerID: UsageProviderID) -> String {
        switch providerID {
        case .statusline:
            switch error {
            case .staleData: return "Official statusline data is stale."
            case .parseFailure: return "Could not read statusline data."
            default: return "Official statusline data not available."
            }
        case .localEstimate:
            return "Local estimate not available."
        case .oauthExperimental:
            switch error {
            case .noCredentials: return "No OAuth token found — log in with Claude Code first."
            case .unauthorized: return "OAuth token expired — open Claude Code to refresh it."
            case .rateLimited: return "OAuth rate limited — showing cached data."
            case .parseFailure: return "OAuth usage response was not JSON."
            case .network(let message): return "OAuth request failed: \(message)."
            default: return "Experimental OAuth data not available."
            }
        }
    }
}
