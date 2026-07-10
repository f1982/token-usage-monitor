import Foundation

/// Normalized metadata from the most recently updated Codex session.
/// This is intentionally aggregate-only; prompts and response content are not retained.
struct CodexActiveSession: Equatable {
    var sessionID: String?
    var provider: String?
    var model: String?
    var client: String?
    var workingDirectory: String?
    var lastEventAt: Date
    var totalTokens: Int?
    var contextWindow: Int?

    /// Percentage of the model context window occupied by this session.
    /// Returns nil when Codex did not report both token values.
    var contextUsagePercent: Double? {
        guard let totalTokens, let contextWindow, contextWindow > 0 else { return nil }
        return Double(totalTokens) / Double(contextWindow) * 100
    }

    var isActive: Bool {
        Date().timeIntervalSince(lastEventAt) < 60
    }
}
