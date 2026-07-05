import Foundation

enum ProjectUsageTimeRange: String, Codable, CaseIterable, Identifiable {
    case today
    case last7Days
    case last30Days
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .all: return "All"
        }
    }

    var shortLabel: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "7d"
        case .last30Days: return "30d"
        case .all: return "All"
        }
    }

    /// Whether an event timestamp falls inside this range. Events without a
    /// timestamp are included only in `all`.
    func contains(_ timestamp: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            guard let timestamp else { return false }
            return calendar.isDate(timestamp, inSameDayAs: now)
        case .last7Days:
            guard let timestamp else { return false }
            return timestamp >= now.addingTimeInterval(-7 * 86_400)
        case .last30Days:
            guard let timestamp else { return false }
            return timestamp >= now.addingTimeInterval(-30 * 86_400)
        }
    }
}
