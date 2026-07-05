import Foundation

enum AppGroup {
    static let identifier = "4MX24QZ69S.group.com.boardpro.ClaudeUsageWidget"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotFileURL: URL? {
        containerURL?.appendingPathComponent("claude-usage-snapshot.json")
    }

    static var projectUsageFileURL: URL? {
        containerURL?.appendingPathComponent("project-usage-summary.json")
    }

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
