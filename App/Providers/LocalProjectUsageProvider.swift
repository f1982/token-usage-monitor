import Foundation

enum ProjectScanError: Error, Equatable {
    case rootNotFound(String)

    var message: String {
        switch self {
        case .rootNotFound(let path):
            return "Claude projects folder was not found.\nExpected: \(path)"
        }
    }
}

protocol ProjectUsageProviding {
    func fetchProjectSummaries(range: ProjectUsageTimeRange, now: Date) async throws -> [ProjectUsageSummary]
}

/// Scans Claude Code JSONL logs under the configured projects root and
/// produces per-project token summaries. Opt-in only: callers must check the
/// Local Project Analytics setting before invoking. Files are streamed line
/// by line; raw lines and message content are never retained.
struct LocalProjectUsageProvider: ProjectUsageProviding {
    var rootPath: String

    init(rootPath: String = UsageSettings.default.claudeProjectsPath) {
        self.rootPath = rootPath
    }

    var rootURL: URL {
        URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)
    }

    func fetchProjectSummaries(range: ProjectUsageTimeRange, now: Date = Date()) async throws -> [ProjectUsageSummary] {
        let root = rootURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ProjectScanError.rootNotFound(rootPath)
        }

        var events: [ProjectUsageEvent] = []
        for fileURL in Self.jsonlFiles(under: root) {
            events.append(contentsOf: await parseFile(at: fileURL))
        }
        return ProjectUsageAggregator.aggregate(events: events, range: range, now: now)
    }

    /// Streams one JSONL file line by line. Unreadable files and invalid
    /// lines are skipped, never fatal.
    private func parseFile(at fileURL: URL) async -> [ProjectUsageEvent] {
        var events: [ProjectUsageEvent] = []
        var lineNumber = 0
        do {
            for try await line in fileURL.lines {
                lineNumber += 1
                if let event = ProjectUsageParser.parseLine(line, filePath: fileURL.path, lineNumber: lineNumber) {
                    events.append(event)
                }
            }
        } catch {
            // Keep whatever parsed before the read error.
        }
        return events
    }

    static func jsonlFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }
}
