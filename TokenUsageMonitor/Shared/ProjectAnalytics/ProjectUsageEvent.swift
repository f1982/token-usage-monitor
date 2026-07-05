import Foundation

/// One normalized token-usage event extracted from a Claude Code JSONL line.
/// Never carries prompt or message content.
struct ProjectUsageEvent: Codable, Equatable, Hashable {
    var stableID: String
    var projectName: String
    var projectPath: String?
    var timestamp: Date?
    var model: String?
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var totalTokens: Int
}
