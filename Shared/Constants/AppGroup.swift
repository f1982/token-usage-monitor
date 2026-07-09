import Foundation

enum AppGroup {
    static let identifier = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_IDENTIFIER") as? String
        ?? "group.example.tokenusagemonitor"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotFileURL: URL? {
        containerURL?.appendingPathComponent("claude-usage-snapshot.json")
    }

    static var projectUsageFileURL: URL? {
        containerURL?.appendingPathComponent("project-usage-summary.json")
    }

    static var usageHistoryFileURL: URL? {
        containerURL?.appendingPathComponent("usage-history.json")
    }

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
