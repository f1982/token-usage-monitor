import Foundation

/// Parses one Claude Code JSONL line into a normalized `ProjectUsageEvent`.
/// Pure and tolerant: any invalid line or line without token counts maps to
/// nil instead of throwing. Only token counts and metadata are extracted —
/// message content never leaves this function.
enum ProjectUsageParser {
    static func parseLine(_ line: String, filePath: String, lineNumber: Int) -> ProjectUsageEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let message = object["message"] as? [String: Any]

        guard let usage = (object["usage"] as? [String: Any]) ?? (message?["usage"] as? [String: Any])
        else { return nil }

        let input = intValue(usage["input_tokens"])
        let output = intValue(usage["output_tokens"])
        let cacheCreation = intValue(usage["cache_creation_input_tokens"])
        let cacheRead = intValue(usage["cache_read_input_tokens"])

        guard input != nil || output != nil || cacheCreation != nil || cacheRead != nil else { return nil }

        let inputTokens = input ?? 0
        let outputTokens = output ?? 0
        let cacheCreationTokens = cacheCreation ?? 0
        let cacheReadTokens = cacheRead ?? 0

        let (projectName, projectPath) = project(from: object, message: message, filePath: filePath)

        return ProjectUsageEvent(
            stableID: stableID(from: object, message: message, filePath: filePath, lineNumber: lineNumber),
            projectName: projectName,
            projectPath: projectPath,
            timestamp: timestamp(from: object, message: message),
            model: model(from: object, message: message),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            totalTokens: inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        )
    }

    // MARK: - Field extraction

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    /// Prefers `message_id + request_id`; falls back to file path + line number.
    private static func stableID(
        from object: [String: Any],
        message: [String: Any]?,
        filePath: String,
        lineNumber: Int
    ) -> String {
        let messageID = stringValue(message?["id"]) ?? stringValue(object["message_id"])
        let requestID = stringValue(object["requestId"]) ?? stringValue(object["request_id"])
        if messageID != nil || requestID != nil {
            return "msg:\(messageID ?? "-")|req:\(requestID ?? "-")"
        }
        return "file:\(filePath)#L\(lineNumber)"
    }

    private static func model(from object: [String: Any], message: [String: Any]?) -> String? {
        if let model = stringValue(object["model"]) { return model }
        if let model = stringValue(message?["model"]) { return model }
        if let request = object["request"] as? [String: Any], let model = stringValue(request["model"]) {
            return model
        }
        return nil
    }

    private static func timestamp(from object: [String: Any], message: [String: Any]?) -> Date? {
        let candidates = [object["timestamp"], object["created_at"], message?["timestamp"]]
        for candidate in candidates {
            if let date = ISO8601Parsing.date(from: stringValue(candidate)) { return date }
        }
        return nil
    }

    /// Extracts the project from supported fields; otherwise derives a name
    /// from the JSONL file's parent directory with a nil path (not reliably
    /// known).
    private static func project(
        from object: [String: Any],
        message: [String: Any]?,
        filePath: String
    ) -> (name: String, path: String?) {
        let workspace = object["workspace"] as? [String: Any]
        let candidates = [
            object["cwd"],
            object["project"],
            object["project_path"],
            object["projectPath"],
            workspace?["cwd"],
        ]
        for candidate in candidates {
            guard let path = stringValue(candidate) else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (name.isEmpty ? path : name, path)
        }
        let parentDirectory = URL(fileURLWithPath: filePath).deletingLastPathComponent().lastPathComponent
        return (parentDirectory.isEmpty ? "Unknown project" : parentDirectory, nil)
    }
}
