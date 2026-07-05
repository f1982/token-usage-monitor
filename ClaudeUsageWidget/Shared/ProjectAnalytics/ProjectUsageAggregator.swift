import CryptoKit
import Foundation

struct ProjectUsageSummary: Codable, Equatable, Identifiable {
    var id: String
    var projectName: String
    var projectPath: String?
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var messageCount: Int
    var models: [String]
    var firstUsedAt: Date?
    var lastUsedAt: Date?
    var source: UsageProvenance
}

/// Groups normalized usage events into per-project summaries: deduplicates by
/// stable ID, filters by time range, sums token fields, and sorts by total
/// tokens descending.
enum ProjectUsageAggregator {
    static func aggregate(
        events: [ProjectUsageEvent],
        range: ProjectUsageTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectUsageSummary] {
        var seenIDs = Set<String>()
        var groups: [String: [ProjectUsageEvent]] = [:]
        var groupOrder: [String] = []

        for event in events {
            guard seenIDs.insert(event.stableID).inserted else { continue }
            guard range.contains(event.timestamp, now: now, calendar: calendar) else { continue }
            let key = groupKey(for: event)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(event)
        }

        let summaries = groupOrder.map { key in
            summarize(groups[key] ?? [], key: key)
        }
        return summaries.sorted {
            if $0.totalTokens != $1.totalTokens { return $0.totalTokens > $1.totalTokens }
            return $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending
        }
    }

    /// Stable hash of the normalized project path when available, otherwise
    /// of the project name.
    static func summaryID(projectPath: String?, projectName: String) -> String {
        let key = projectPath.map(normalizePath) ?? projectName
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.prefix(8).joined()
    }

    private static func groupKey(for event: ProjectUsageEvent) -> String {
        event.projectPath.map(normalizePath) ?? "name:\(event.projectName)"
    }

    private static func normalizePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func summarize(_ events: [ProjectUsageEvent], key: String) -> ProjectUsageSummary {
        let projectPath = events.compactMap(\.projectPath).first
        let projectName = events.map(\.projectName).first { !$0.isEmpty } ?? "Unknown project"
        let timestamps = events.compactMap(\.timestamp)
        let models = Set(events.compactMap(\.model)).sorted()

        return ProjectUsageSummary(
            id: summaryID(projectPath: projectPath, projectName: projectName),
            projectName: projectName,
            projectPath: projectPath,
            totalTokens: events.reduce(0) { $0 + $1.totalTokens },
            inputTokens: events.reduce(0) { $0 + $1.inputTokens },
            outputTokens: events.reduce(0) { $0 + $1.outputTokens },
            cacheCreationTokens: events.reduce(0) { $0 + $1.cacheCreationTokens },
            cacheReadTokens: events.reduce(0) { $0 + $1.cacheReadTokens },
            messageCount: events.count,
            models: models,
            firstUsedAt: timestamps.min(),
            lastUsedAt: timestamps.max(),
            source: .localEstimate
        )
    }
}
