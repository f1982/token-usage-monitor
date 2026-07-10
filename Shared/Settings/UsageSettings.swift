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
    case neonSegments

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .progressBar: return "Progress Bar"
        case .bar: return "Bar Chart"
        case .donut: return "Donut"
        case .waterBall: return "Water Ball"
        case .neonSegments: return "Neon Segments"
        }
    }

    /// SF Symbol used in the settings picker.
    var systemImage: String {
        switch self {
        case .progressBar: return "rectangle.compress.vertical"
        case .bar: return "chart.bar.fill"
        case .donut: return "chart.pie.fill"
        case .waterBall: return "drop.fill"
        case .neonSegments: return "rectangle.grid.1x2.fill"
        }
    }

    /// The water ball shows quota *remaining* (a draining tank); the others
    /// fill up as quota is *used*.
    var showsRemaining: Bool { self == .waterBall }
}

/// Which usage products are visible in the overview and widget. Keep this
/// enum additive so future products can join the same settings UI.
enum UsageDisplaySource: String, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// How often the Projects page auto-refreshes its cached per-project
/// summaries. `manual` disables the interval so data only updates on an
/// explicit Refresh. `String`-backed with a fallback so older stored
/// settings keep decoding across versions.
enum ProjectAnalyticsRefreshInterval: String, Codable, CaseIterable, Identifiable {
    case manual
    case every30Minutes
    case hourly
    case every3Hours
    case every6Hours

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual only"
        case .every30Minutes: return "Every 30 minutes"
        case .hourly: return "Every hour"
        case .every3Hours: return "Every 3 hours"
        case .every6Hours: return "Every 6 hours"
        }
    }

    /// The staleness threshold, in seconds, or `nil` for `manual` (never
    /// auto-refreshes).
    var seconds: TimeInterval? {
        switch self {
        case .manual: return nil
        case .every30Minutes: return 30 * 60
        case .hourly: return 60 * 60
        case .every3Hours: return 3 * 60 * 60
        case .every6Hours: return 6 * 60 * 60
        }
    }
}

struct UsageSettings: Codable, Equatable {
    var menuBarUsageEnabled: Bool
    var quotaSourceMode: QuotaSourceMode
    var visibleUsageSources: Set<UsageDisplaySource>
    var localProjectAnalyticsEnabled: Bool
    var claudeProjectsPath: String
    var codexSessionsPath: String
    var experimentalOAuthEnabled: Bool
    var projectAnalyticsDefaultRange: ProjectUsageTimeRange
    var projectAnalyticsRefreshInterval: ProjectAnalyticsRefreshInterval
    var usageChartStyle: UsageChartStyle

    static let `default` = UsageSettings(
        menuBarUsageEnabled: false,
        quotaSourceMode: .officialStatuslineOnly,
        visibleUsageSources: Set(UsageDisplaySource.allCases),
        localProjectAnalyticsEnabled: false,
        claudeProjectsPath: "~/.claude/projects",
        codexSessionsPath: "~/.codex/sessions",
        experimentalOAuthEnabled: false,
        projectAnalyticsDefaultRange: .last7Days,
        projectAnalyticsRefreshInterval: .hourly,
        usageChartStyle: .progressBar
    )

    init(
        menuBarUsageEnabled: Bool = false,
        quotaSourceMode: QuotaSourceMode,
        visibleUsageSources: Set<UsageDisplaySource> = Set(UsageDisplaySource.allCases),
        localProjectAnalyticsEnabled: Bool,
        claudeProjectsPath: String,
        codexSessionsPath: String = "~/.codex/sessions",
        experimentalOAuthEnabled: Bool,
        projectAnalyticsDefaultRange: ProjectUsageTimeRange,
        projectAnalyticsRefreshInterval: ProjectAnalyticsRefreshInterval = .hourly,
        usageChartStyle: UsageChartStyle
    ) {
        self.menuBarUsageEnabled = menuBarUsageEnabled
        self.quotaSourceMode = quotaSourceMode
        self.visibleUsageSources = visibleUsageSources.isEmpty ? Set(UsageDisplaySource.allCases) : visibleUsageSources
        self.localProjectAnalyticsEnabled = localProjectAnalyticsEnabled
        self.claudeProjectsPath = claudeProjectsPath
        self.codexSessionsPath = codexSessionsPath
        self.experimentalOAuthEnabled = experimentalOAuthEnabled
        self.projectAnalyticsDefaultRange = projectAnalyticsDefaultRange
        self.projectAnalyticsRefreshInterval = projectAnalyticsRefreshInterval
        self.usageChartStyle = usageChartStyle
    }

    // Missing or unrecognized keys fall back to safe defaults so older stored
    // settings keep decoding across versions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UsageSettings.default
        menuBarUsageEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .menuBarUsageEnabled))
            .flatMap { $0 } ?? defaults.menuBarUsageEnabled
        quotaSourceMode = (try? container.decodeIfPresent(QuotaSourceMode.self, forKey: .quotaSourceMode))
            .flatMap { $0 } ?? defaults.quotaSourceMode
        let decodedSources = (try? container.decodeIfPresent(Set<UsageDisplaySource>.self, forKey: .visibleUsageSources))
            .flatMap { $0 } ?? defaults.visibleUsageSources
        visibleUsageSources = decodedSources.isEmpty ? defaults.visibleUsageSources : decodedSources
        localProjectAnalyticsEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .localProjectAnalyticsEnabled))
            .flatMap { $0 } ?? defaults.localProjectAnalyticsEnabled
        claudeProjectsPath = (try? container.decodeIfPresent(String.self, forKey: .claudeProjectsPath))
            .flatMap { $0 } ?? defaults.claudeProjectsPath
        codexSessionsPath = (try? container.decodeIfPresent(String.self, forKey: .codexSessionsPath))
            .flatMap { $0 } ?? defaults.codexSessionsPath
        experimentalOAuthEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .experimentalOAuthEnabled))
            .flatMap { $0 } ?? defaults.experimentalOAuthEnabled
        projectAnalyticsDefaultRange = (try? container.decodeIfPresent(ProjectUsageTimeRange.self, forKey: .projectAnalyticsDefaultRange))
            .flatMap { $0 } ?? defaults.projectAnalyticsDefaultRange
        projectAnalyticsRefreshInterval = (try? container.decodeIfPresent(ProjectAnalyticsRefreshInterval.self, forKey: .projectAnalyticsRefreshInterval))
            .flatMap { $0 } ?? defaults.projectAnalyticsRefreshInterval
        usageChartStyle = (try? container.decodeIfPresent(UsageChartStyle.self, forKey: .usageChartStyle))
            .flatMap { $0 } ?? defaults.usageChartStyle
    }
}
