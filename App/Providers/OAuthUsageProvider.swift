import Foundation

/// Wraps the V0.1 OAuth flow (local token + undocumented usage endpoint) as
/// an experimental provider. Only called when the user explicitly enabled it
/// in Settings — the aggregator enforces that.
struct OAuthUsageProvider: UsageProvider {
    let id = UsageProviderID.oauthExperimental
    let displayName = "Experimental OAuth API"
    let provenance = UsageProvenance.experimental

    var tokenReader: TokenReading
    var usageClient: UsageFetching
    var now: () -> Date

    init(
        tokenReader: TokenReading = ClaudeTokenReader(),
        usageClient: UsageFetching = ClaudeUsageClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.tokenReader = tokenReader
        self.usageClient = usageClient
        self.now = now
    }

    func fetchQuotaUsage() async -> UsageProviderResult<ClaudeUsageSnapshot> {
        guard let token = tokenReader.readToken() else {
            return .failure(.noCredentials, provenance: provenance, fetchedAt: now())
        }
        do {
            var snapshot = try await usageClient.fetchUsage(accessToken: token)
            snapshot.provenance = .experimental
            return .success(snapshot, provenance: provenance, fetchedAt: snapshot.fetchedAt)
        } catch let error as UsageClientError {
            return .failure(Self.mapError(error), provenance: provenance, fetchedAt: now())
        } catch {
            return .failure(.network(error.localizedDescription), provenance: provenance, fetchedAt: now())
        }
    }

    static func mapError(_ error: UsageClientError) -> UsageProviderError {
        switch error {
        case .unauthorized: return .unauthorized
        case .rateLimited: return .rateLimited
        case .notJSON: return .parseFailure
        case .badStatus(let code): return .network("usage endpoint returned HTTP \(code)")
        case .network(let message): return .network(message)
        }
    }
}
