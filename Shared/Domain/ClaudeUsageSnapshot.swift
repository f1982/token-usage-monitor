import Foundation

struct ClaudeUsageSnapshot: Codable, Equatable {
    var available: Bool
    var session: UsageLimit?
    var weekly: UsageLimit?
    var weeklyScoped: [UsageLimit]
    var codex: [UsageLimit] = []
    var note: String?
    var fetchedAt: Date
    // Which kind of source produced this snapshot. Optional so V0.1 caches
    // (written without the field) keep decoding.
    var provenance: UsageProvenance? = nil

    var hasAnyUsage: Bool {
        hasClaudeUsage || hasCodexUsage
    }

    var hasClaudeUsage: Bool {
        session != nil || weekly != nil || !weeklyScoped.isEmpty
    }

    var hasCodexUsage: Bool {
        !codex.isEmpty
    }

    func filtered(visibleSources: Set<UsageDisplaySource>) -> ClaudeUsageSnapshot {
        var filtered = self
        if !visibleSources.contains(.claudeCode) {
            filtered.session = nil
            filtered.weekly = nil
            filtered.weeklyScoped = []
        }
        if !visibleSources.contains(.codex) {
            filtered.codex = []
        }
        filtered.available = filtered.hasAnyUsage
        return filtered
    }

    static func unavailable(note: String?, fetchedAt: Date) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: false,
            session: nil,
            weekly: nil,
            weeklyScoped: [],
            codex: [],
            note: note,
            fetchedAt: fetchedAt,
            provenance: nil
        )
    }
}
