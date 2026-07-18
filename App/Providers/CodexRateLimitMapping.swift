import Foundation

/// Codex has used snake_case in session JSONL and camelCase in app-server.
/// Decode both forms into one model so quota semantics do not depend on a
/// transport's field naming or on the primary/secondary slot ordering.
struct CodexRateLimitSnapshot: Decodable {
    var limitID: String?
    var limitName: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case snakeLimitID = "limit_id"
        case limitName
        case snakeLimitName = "limit_name"
        case primary
        case secondary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitID = try container.decodeIfPresent(String.self, forKey: .limitID)
            ?? container.decodeIfPresent(String.self, forKey: .snakeLimitID)
        limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
            ?? container.decodeIfPresent(String.self, forKey: .snakeLimitName)
        primary = try container.decodeIfPresent(CodexRateLimitWindow.self, forKey: .primary)
        secondary = try container.decodeIfPresent(CodexRateLimitWindow.self, forKey: .secondary)
    }
}

struct CodexRateLimitWindow: Decodable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case snakeUsedPercent = "used_percent"
        case windowMinutes = "windowDurationMins"
        case snakeWindowMinutes = "window_minutes"
        case resetsAt
        case snakeResetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Double.self, forKey: .usedPercent) {
            usedPercent = value
        } else {
            usedPercent = try container.decode(Double.self, forKey: .snakeUsedPercent)
        }
        windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .snakeWindowMinutes)
        resetsAt = try container.decodeIfPresent(Int64.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Int64.self, forKey: .snakeResetsAt)
    }
}

enum CodexUsageLimitMapper {
    static func limits(from snapshots: [CodexRateLimitSnapshot]) -> [UsageLimit] {
        snapshots
            .sorted { lhs, rhs in
                let lhsIsDefault = lhs.limitID == nil || lhs.limitID == "codex"
                let rhsIsDefault = rhs.limitID == nil || rhs.limitID == "codex"
                if lhsIsDefault != rhsIsDefault { return lhsIsDefault }
                return (lhs.limitName ?? lhs.limitID ?? "")
                    .localizedStandardCompare(rhs.limitName ?? rhs.limitID ?? "") == .orderedAscending
            }
            .flatMap(limits(from:))
    }

    private static func limits(from snapshot: CodexRateLimitSnapshot) -> [UsageLimit] {
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        return windows.enumerated().map { index, window in
            let baseLabel = snapshot.limitName?.nilIfBlank
                ?? (snapshot.limitID == nil || snapshot.limitID == "codex" ? "Codex" : snapshot.limitID!)
            let windowKey = window.windowMinutes.map(String.init) ?? "slot-\(index)"
            let bucketKey = snapshot.limitID?.nilIfBlank ?? "codex"

            return UsageLimit(
                id: "codex-\(bucketKey)-\(windowKey)",
                kind: "codex_\(bucketKey)_\(windowKey)",
                label: label(base: baseLabel, windowMinutes: window.windowMinutes),
                percent: min(max(window.usedPercent, 0), 100),
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        .sorted {
            let lhsWindow = windowMinutes(from: $0.kind) ?? Int.max
            let rhsWindow = windowMinutes(from: $1.kind) ?? Int.max
            return lhsWindow < rhsWindow
        }
    }

    private static func label(base: String, windowMinutes: Int?) -> String {
        switch windowMinutes {
        case 300:
            return "\(base) 5h"
        case 10_080:
            return "\(base) weekly"
        case let minutes? where minutes % 1_440 == 0:
            return "\(base) \(minutes / 1_440)d"
        case let minutes? where minutes % 60 == 0:
            return "\(base) \(minutes / 60)h"
        case let minutes?:
            return "\(base) \(minutes)m"
        default:
            return "\(base) limit"
        }
    }

    private static func windowMinutes(from kind: String) -> Int? {
        kind.split(separator: "_").last.flatMap { Int($0) }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
