import Foundation

enum QuotaSourceMode: String, Codable, CaseIterable, Identifiable {
    case officialStatuslineOnly
    case statuslineThenLocalEstimate
    case statuslineThenLocalThenOAuth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .officialStatuslineOnly:
            return "Official statusline only"
        case .statuslineThenLocalEstimate:
            return "Statusline, then local estimate"
        case .statuslineThenLocalThenOAuth:
            return "Statusline, then local estimate, then experimental OAuth"
        }
    }

    var allowsLocalEstimate: Bool { self != .officialStatuslineOnly }
    var allowsOAuth: Bool { self == .statuslineThenLocalThenOAuth }
}

struct UsageSettings: Codable, Equatable {
    var quotaSourceMode: QuotaSourceMode
    var localProjectAnalyticsEnabled: Bool
    var claudeProjectsPath: String
    var experimentalOAuthEnabled: Bool
    var projectAnalyticsDefaultRange: ProjectUsageTimeRange

    static let `default` = UsageSettings(
        quotaSourceMode: .officialStatuslineOnly,
        localProjectAnalyticsEnabled: false,
        claudeProjectsPath: "~/.claude/projects",
        experimentalOAuthEnabled: false,
        projectAnalyticsDefaultRange: .last7Days
    )

    init(
        quotaSourceMode: QuotaSourceMode,
        localProjectAnalyticsEnabled: Bool,
        claudeProjectsPath: String,
        experimentalOAuthEnabled: Bool,
        projectAnalyticsDefaultRange: ProjectUsageTimeRange
    ) {
        self.quotaSourceMode = quotaSourceMode
        self.localProjectAnalyticsEnabled = localProjectAnalyticsEnabled
        self.claudeProjectsPath = claudeProjectsPath
        self.experimentalOAuthEnabled = experimentalOAuthEnabled
        self.projectAnalyticsDefaultRange = projectAnalyticsDefaultRange
    }

    // Missing or unrecognized keys fall back to safe defaults so older stored
    // settings keep decoding across versions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UsageSettings.default
        quotaSourceMode = (try? container.decodeIfPresent(QuotaSourceMode.self, forKey: .quotaSourceMode))
            .flatMap { $0 } ?? defaults.quotaSourceMode
        localProjectAnalyticsEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .localProjectAnalyticsEnabled))
            .flatMap { $0 } ?? defaults.localProjectAnalyticsEnabled
        claudeProjectsPath = (try? container.decodeIfPresent(String.self, forKey: .claudeProjectsPath))
            .flatMap { $0 } ?? defaults.claudeProjectsPath
        experimentalOAuthEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .experimentalOAuthEnabled))
            .flatMap { $0 } ?? defaults.experimentalOAuthEnabled
        projectAnalyticsDefaultRange = (try? container.decodeIfPresent(ProjectUsageTimeRange.self, forKey: .projectAnalyticsDefaultRange))
            .flatMap { $0 } ?? defaults.projectAnalyticsDefaultRange
    }
}
