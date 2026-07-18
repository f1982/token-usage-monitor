import Foundation

protocol CodexUsageProviding {
    func fetchCodexLimits() async -> [UsageLimit]
}

protocol CodexActiveSessionProviding {
    func fetchActiveSession() async -> CodexActiveSession?
}

/// Reads Codex rate limits from local session JSONL as a fallback when the
/// account-level app-server request is unavailable.
struct CodexSessionUsageProvider: CodexUsageProviding, CodexActiveSessionProviding {
    static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    var sessionsDirectory: () -> URL?
    private let scanner: CodexSessionScanner

    init(
        sessionsDirectory: URL = Self.defaultSessionsDirectory,
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = { sessionsDirectory }
        self.scanner = CodexSessionScanner(fileManager: fileManager)
    }

    init(
        sessionsDirectory: @escaping () -> URL?,
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.scanner = CodexSessionScanner(fileManager: fileManager)
    }

    func fetchCodexLimits() async -> [UsageLimit] {
        guard let directory = sessionsDirectory() else { return [] }
        return await scanner.fetchLimits(in: directory)
    }

    func fetchActiveSession() async -> CodexActiveSession? {
        guard let directory = sessionsDirectory() else { return nil }
        return await scanner.fetchActiveSession(in: directory)
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
            let limits = CodexUsageLimitMapper.limits(from: [rateLimits])
            if !limits.isEmpty { return limits }
        }
        return []
    }

    static func activeSession(fromJSONL contents: String) -> CodexActiveSession? {
        var sessionID: String?
        var provider: String?
        var model: String?
        var client: String?
        var workingDirectory: String?
        var lastEventAt: Date?
        var totalTokens: Int?
        var contextWindow: Int?

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }

            if let value = payload["session_id"] as? String { sessionID = value }
            if let value = payload["model_provider"] as? String { provider = value }
            if let value = payload["model"] as? String { model = value }
            if let value = payload["cwd"] as? String { workingDirectory = value }
            if let value = payload["originator"] as? String { client = value }
            if let value = object["timestamp"] as? String,
               let date = ISO8601Parsing.date(from: value) {
                lastEventAt = date
            }

            if let info = payload["info"] as? [String: Any] {
                if let usage = info["total_token_usage"] as? [String: Any],
                   let value = usage["total_tokens"] as? NSNumber {
                    totalTokens = value.intValue
                }
                if let value = info["model_context_window"] as? NSNumber {
                    contextWindow = value.intValue
                }
            }
            if let value = payload["model_context_window"] as? NSNumber {
                contextWindow = value.intValue
            }
        }

        guard let lastEventAt else { return nil }
        return CodexActiveSession(
            sessionID: sessionID,
            provider: provider,
            model: model,
            client: client,
            workingDirectory: workingDirectory,
            lastEventAt: lastEventAt,
            totalTokens: totalTokens,
            contextWindow: contextWindow
        )
    }

}

/// Performs filesystem work on its own actor so quota refreshes do not block
/// SwiftUI's main actor while traversing and reading session logs.
private actor CodexSessionScanner {
    let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func fetchLimits(in directory: URL) -> [UsageLimit] {
        let didStartAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { directory.stopAccessingSecurityScopedResource() }
        }
        for fileURL in sessionFiles(in: directory).prefix(20) {
            guard let data = try? Data(contentsOf: fileURL),
                  let contents = String(data: data, encoding: .utf8) else {
                continue
            }
            let limits = CodexSessionUsageProvider.limits(fromJSONL: contents)
            if !limits.isEmpty { return limits }
        }
        return []
    }

    func fetchActiveSession(in directory: URL) -> CodexActiveSession? {
        let didStartAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { directory.stopAccessingSecurityScopedResource() }
        }
        guard let fileURL = sessionFiles(in: directory).first,
              let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        return CodexSessionUsageProvider.activeSession(fromJSONL: contents)
    }

    private func sessionFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }
}

private struct CodexTokenCountEvent: Decodable {
    var payload: Payload

    struct Payload: Decodable {
        var rateLimits: CodexRateLimitSnapshot?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }
}
