import Foundation

// MARK: - Normalized statusline state file

/// Normalized state file written by a Claude Code statusline hook. Dates are
/// kept as strings and parsed leniently so a slightly different producer
/// doesn't break the whole file.
struct StatuslineStateFile: Decodable {
    var schemaVersion: Int?
    var source: String?
    var capturedAt: String?
    var rateLimits: RateLimits?

    struct RateLimits: Decodable {
        var session: Entry?
        var weekly: Entry?
        var weeklyScoped: [Entry]?
    }

    struct Entry: Decodable {
        var kind: String?
        var label: String?
        var percent: Double?
        var resetsAt: String?
    }
}

// MARK: - Provider

/// Reads official Claude Code `rate_limits` data from the normalized state
/// file maintained by a statusline hook. This is the default (and only
/// always-on) quota source in V0.2.
struct StatuslineUsageProvider: UsageProvider {
    static let freshnessWindow: TimeInterval = 10 * 60

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-usage-widget/statusline/latest.json")
    }

    let id = UsageProviderID.statusline
    let displayName = "Claude Code statusline"
    let provenance = UsageProvenance.official

    var fileURL: URL
    var now: () -> Date

    init(fileURL: URL = Self.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    func fetchQuotaUsage() async -> UsageProviderResult<ClaudeUsageSnapshot> {
        let currentTime = now()

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure(.missing, provenance: provenance, fetchedAt: currentTime)
        }
        guard let state = try? JSONDecoder().decode(StatuslineStateFile.self, from: data) else {
            return .failure(.parseFailure, provenance: provenance, fetchedAt: currentTime)
        }
        guard let capturedAt = ISO8601Parsing.date(from: state.capturedAt) else {
            return .failure(.parseFailure, provenance: provenance, fetchedAt: currentTime)
        }
        let snapshot = Self.makeSnapshot(from: state, capturedAt: capturedAt)
        guard snapshot.hasAnyUsage else {
            return .failure(.unavailable, provenance: provenance, fetchedAt: currentTime)
        }
        if currentTime.timeIntervalSince(capturedAt) > Self.freshnessWindow {
            var staleSnapshot = snapshot
            staleSnapshot.note = "Official statusline data is stale."
            return UsageProviderResult(
                value: staleSnapshot,
                error: .staleData,
                provenance: provenance,
                fetchedAt: currentTime
            )
        }
        return .success(snapshot, provenance: provenance, fetchedAt: currentTime)
    }

    // MARK: - Mapping

    static func makeSnapshot(from state: StatuslineStateFile, capturedAt: Date) -> ClaudeUsageSnapshot {
        let limits = state.rateLimits
        let session = limits?.session.flatMap { makeLimit($0, id: "session", defaultLabel: "Session") }
        let weekly = limits?.weekly.flatMap { makeLimit($0, id: "weekly", defaultLabel: "All models") }
        let scoped = (limits?.weeklyScoped ?? []).enumerated().compactMap { index, entry in
            makeLimit(entry, id: "weekly_scoped-\(index)", defaultLabel: "Weekly")
        }

        return ClaudeUsageSnapshot(
            available: session != nil || weekly != nil || !scoped.isEmpty,
            session: session,
            weekly: weekly,
            weeklyScoped: scoped,
            note: nil,
            fetchedAt: capturedAt,
            provenance: .official
        )
    }

    private static func makeLimit(_ entry: StatuslineStateFile.Entry, id: String, defaultLabel: String) -> UsageLimit? {
        guard let percent = entry.percent else { return nil }
        return UsageLimit(
            id: id,
            kind: entry.kind ?? id,
            label: entry.label ?? defaultLabel,
            percent: percent,
            resetsAt: ISO8601Parsing.date(from: entry.resetsAt)
        )
    }
}
