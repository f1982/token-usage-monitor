import Foundation

struct ClaudeUsageSnapshot: Codable, Equatable {
    var available: Bool
    var session: UsageLimit?
    var weekly: UsageLimit?
    var weeklyScoped: [UsageLimit]
    var note: String?
    var fetchedAt: Date
    // Which kind of source produced this snapshot. Optional so V0.1 caches
    // (written without the field) keep decoding.
    var provenance: UsageProvenance? = nil

    var hasAnyUsage: Bool {
        session != nil || weekly != nil || !weeklyScoped.isEmpty
    }

    static func unavailable(note: String?, fetchedAt: Date) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: false,
            session: nil,
            weekly: nil,
            weeklyScoped: [],
            note: note,
            fetchedAt: fetchedAt,
            provenance: nil
        )
    }
}
