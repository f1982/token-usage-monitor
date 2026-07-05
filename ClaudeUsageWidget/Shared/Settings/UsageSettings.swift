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

/// Visual style used to render each usage limit's percentage. Shared by the
/// app overview and the widget so both stay in sync. New cases must keep
/// decoding old stored values, so this is `String`-backed with a fallback.
enum UsageChartStyle: String, Codable, CaseIterable, Identifiable {
    case progressBar
    case bar
    case donut
    case waterBall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .progressBar: return "Progress Bar"
        case .bar: return "Bar Chart"
        case .donut: return "Donut"
        case .waterBall: return "Water Ball"
        }
    }

    /// SF Symbol used in the settings picker.
    var systemImage: String {
        switch self {
        case .progressBar: return "rectangle.compress.vertical"
        case .bar: return "chart.bar.fill"
        case .donut: return "chart.pie.fill"
        case .waterBall: return "drop.fill"
        }
    }

    /// The water ball shows quota *remaining* (a draining tank); the others
    /// fill up as quota is *used*.
    var showsRemaining: Bool { self == .waterBall }
}

struct UsageSettings: Codable, Equatable {
    var quotaSourceMode: QuotaSourceMode
    var localProjectAnalyticsEnabled: Bool
    var claudeProjectsPath: String
    var experimentalOAuthEnabled: Bool
    var projectAnalyticsDefaultRange: ProjectUsageTimeRange
    var usageChartStyle: UsageChartStyle

    static let `default` = UsageSettings(
        quotaSourceMode: .officialStatuslineOnly,
        localProjectAnalyticsEnabled: false,
        claudeProjectsPath: "~/.claude/projects",
        experimentalOAuthEnabled: false,
        projectAnalyticsDefaultRange: .last7Days,
        usageChartStyle: .progressBar
    )

    init(
        quotaSourceMode: QuotaSourceMode,
        localProjectAnalyticsEnabled: Bool,
        claudeProjectsPath: String,
        experimentalOAuthEnabled: Bool,
        projectAnalyticsDefaultRange: ProjectUsageTimeRange,
        usageChartStyle: UsageChartStyle
    ) {
        self.quotaSourceMode = quotaSourceMode
        self.localProjectAnalyticsEnabled = localProjectAnalyticsEnabled
        self.claudeProjectsPath = claudeProjectsPath
        self.experimentalOAuthEnabled = experimentalOAuthEnabled
        self.projectAnalyticsDefaultRange = projectAnalyticsDefaultRange
        self.usageChartStyle = usageChartStyle
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
        usageChartStyle = (try? container.decodeIfPresent(UsageChartStyle.self, forKey: .usageChartStyle))
            .flatMap { $0 } ?? defaults.usageChartStyle
    }
}
