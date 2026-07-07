import Foundation

protocol CodexUsageProviding {
    func fetchCodexLimits() async -> [UsageLimit]
}

/// Reads Codex rate limits from the latest local session JSONL. Codex emits
/// `token_count` events with `rate_limits.primary` and `rate_limits.secondary`.
struct CodexSessionUsageProvider: CodexUsageProviding {
    static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    var sessionsDirectory: () -> URL
    var fileManager: FileManager

    init(
        sessionsDirectory: URL = Self.defaultSessionsDirectory,
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = { sessionsDirectory }
        self.fileManager = fileManager
    }

    init(
        sessionsDirectory: @escaping () -> URL,
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.fileManager = fileManager
    }

    func fetchCodexLimits() async -> [UsageLimit] {
        guard let fileURL = latestSessionFile() else { return [] }
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        return Self.limits(fromJSONL: contents)
    }

    private func latestSessionFile() -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .max { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    static func limits(fromJSONL contents: String) -> [UsageLimit] {
        let decoder = JSONDecoder()
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains(#""token_count""#),
                  line.contains(#""rate_limits""#),
                  let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(CodexTokenCountEvent.self, from: data),
                  let rateLimits = event.payload.rateLimits else {
                continue
            }
            return makeLimits(from: rateLimits)
        }
        return []
    }

    private static func makeLimits(from rateLimits: CodexRateLimits) -> [UsageLimit] {
        var limits: [UsageLimit] = []
        if let primary = makeLimit(
            rateLimits.primary,
            id: "codex-primary",
            kind: "codex_primary",
            defaultLabel: label(forWindowMinutes: rateLimits.primary.windowMinutes, fallback: "Codex 5h")
        ) {
            limits.append(primary)
        }
        if let secondary = makeLimit(
            rateLimits.secondary,
            id: "codex-secondary",
            kind: "codex_secondary",
            defaultLabel: label(forWindowMinutes: rateLimits.secondary.windowMinutes, fallback: "Codex weekly")
        ) {
            limits.append(secondary)
        }
        return limits
    }

    private static func makeLimit(
        _ entry: CodexRateLimitEntry,
        id: String,
        kind: String,
        defaultLabel: String
    ) -> UsageLimit? {
        guard let percent = entry.usedPercent else { return nil }
        return UsageLimit(
            id: id,
            kind: kind,
            label: defaultLabel,
            percent: percent,
            resetsAt: entry.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func label(forWindowMinutes minutes: Int?, fallback: String) -> String {
        switch minutes {
        case 300:
            return "Codex 5h"
        case 10_080:
            return "Codex weekly"
        case let minutes? where minutes % 1_440 == 0:
            return "Codex \(minutes / 1_440)d"
        case let minutes? where minutes % 60 == 0:
            return "Codex \(minutes / 60)h"
        case let minutes?:
            return "Codex \(minutes)m"
        default:
            return fallback
        }
    }
}

private struct CodexTokenCountEvent: Decodable {
    var payload: Payload

    struct Payload: Decodable {
        var rateLimits: CodexRateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }
}

private struct CodexRateLimits: Decodable {
    var primary: CodexRateLimitEntry
    var secondary: CodexRateLimitEntry
}

private struct CodexRateLimitEntry: Decodable {
    var usedPercent: Double?
    var windowMinutes: Int?
    var resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
