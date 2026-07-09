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

    var isActive: Bool {
        Date().timeIntervalSince(lastEventAt) < 60
    }
}
