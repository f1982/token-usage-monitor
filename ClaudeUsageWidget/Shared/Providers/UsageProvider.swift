import Foundation

enum UsageProviderID: String, Codable, CaseIterable {
    case statusline
    case localEstimate
    case oauthExperimental
}

enum UsageProvenance: String, Codable {
    case official
    case localEstimate
    case experimental

    var displayName: String {
        switch self {
        case .official: return "Official statusline"
        case .localEstimate: return "Local estimate"
        case .experimental: return "Experimental OAuth"
        }
    }
}

enum UsageProviderError: Error, Equatable {
    case missing
    case staleData
    case parseFailure
    case unavailable
    case noCredentials
    case unauthorized
    case rateLimited
    case network(String)
}

struct UsageProviderResult<Value> {
    var value: Value?
    var error: UsageProviderError?
    var provenance: UsageProvenance
    var fetchedAt: Date

    static func success(_ value: Value, provenance: UsageProvenance, fetchedAt: Date) -> UsageProviderResult {
        UsageProviderResult(value: value, error: nil, provenance: provenance, fetchedAt: fetchedAt)
    }

    static func failure(_ error: UsageProviderError, provenance: UsageProvenance, fetchedAt: Date) -> UsageProviderResult {
        UsageProviderResult(value: nil, error: error, provenance: provenance, fetchedAt: fetchedAt)
    }
}

/// A single quota usage source. Providers only know how to fetch their own
/// data — source ordering and fallback policy live in `UsageAggregatorService`.
protocol UsageProvider {
    var id: UsageProviderID { get }
    var displayName: String { get }
    var provenance: UsageProvenance { get }

    func fetchQuotaUsage() async -> UsageProviderResult<ClaudeUsageSnapshot>
}
