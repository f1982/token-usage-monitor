import Foundation

enum UsageClientError: Error, Equatable {
    case unauthorized
    case rateLimited
    case badStatus(Int)
    case notJSON
    case network(String)
}

protocol UsageFetching {
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageSnapshot
}

// MARK: - Raw response models

struct RawUsageResponse: Decodable {
    var limits: [RawLimitEntry]?
    var seven_day: RawSevenDay?
}

struct RawLimitEntry: Decodable {
    var kind: String
    var group: String?
    var percent: Double?
    var resets_at: String?
    var scope: RawScope?
    var is_active: Bool?
}

struct RawScope: Decodable {
    var model: RawModel?
}

struct RawModel: Decodable {
    var display_name: String?
}

struct RawSevenDay: Decodable {
    var utilization: Double?
    var resets_at: String?
}

// MARK: - Client

/// Calls the internal Claude Code usage endpoint and normalizes the response.
/// The endpoint is undocumented, so all network/JSON failures are treated as
/// expected recoverable states (typed errors handled by the refresh service).
struct ClaudeUsageClient: UsageFetching {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    var session: URLSession = .shared
    var now: () -> Date = Date.init

    func fetchUsage(accessToken: String) async throws -> ClaudeUsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.network("no HTTP response")
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw UsageClientError.unauthorized
        case 429:
            throw UsageClientError.rateLimited
        default:
            throw UsageClientError.badStatus(http.statusCode)
        }

        let raw: RawUsageResponse
        do {
            raw = try JSONDecoder().decode(RawUsageResponse.self, from: data)
        } catch {
            throw UsageClientError.notJSON
        }
        return Self.makeSnapshot(from: raw, fetchedAt: now())
    }

    // MARK: - Mapping

    /// Normalizes a raw usage response into a `ClaudeUsageSnapshot`.
    static func makeSnapshot(from raw: RawUsageResponse, fetchedAt: Date) -> ClaudeUsageSnapshot {
        let limits = raw.limits ?? []

        let sessionEntries = limits.enumerated().filter { $0.element.kind == "session" }
        let weeklyAllEntries = limits.enumerated().filter { $0.element.kind == "weekly_all" }
        let scopedEntries = limits.enumerated().filter { $0.element.kind == "weekly_scoped" }

        let session = pickEntry(from: sessionEntries).map { index, entry in
            makeLimit(entry, index: index, label: "Session")
        }

        var weekly = pickEntry(from: weeklyAllEntries).map { index, entry in
            makeLimit(entry, index: index, label: "All models")
        }
        if weekly == nil, let sevenDay = raw.seven_day, let utilization = sevenDay.utilization {
            weekly = UsageLimit(
                id: "seven_day",
                kind: "weekly_all",
                label: "All models",
                percent: utilization,
                resetsAt: parseISODate(sevenDay.resets_at)
            )
        }

        let scoped = scopedEntries.map { index, entry in
            makeLimit(entry, index: index, label: entry.scope?.model?.display_name ?? "Weekly")
        }

        let available = session != nil || weekly != nil || !scoped.isEmpty
        return ClaudeUsageSnapshot(
            available: available,
            session: session,
            weekly: weekly,
            weeklyScoped: scoped,
            note: nil,
            fetchedAt: fetchedAt
        )
    }

    /// Prefers the entry marked active; otherwise falls back to the first one.
    private static func pickEntry(
        from entries: [(offset: Int, element: RawLimitEntry)]
    ) -> (offset: Int, element: RawLimitEntry)? {
        entries.first { $0.element.is_active == true } ?? entries.first
    }

    private static func makeLimit(_ entry: RawLimitEntry, index: Int, label: String) -> UsageLimit {
        UsageLimit(
            id: "\(entry.kind)-\(index)",
            kind: entry.kind,
            label: label,
            percent: entry.percent ?? 0,
            resetsAt: parseISODate(entry.resets_at)
        )
    }

    /// Parses ISO8601 timestamps with or without fractional seconds. Bad or
    /// missing dates map to nil instead of failing the whole response.
    static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return Self.fractionalFormatter.date(from: string) ?? Self.plainFormatter.date(from: string)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
