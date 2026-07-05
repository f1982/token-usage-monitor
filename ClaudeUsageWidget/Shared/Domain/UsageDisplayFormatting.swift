import Foundation

enum UsageDisplayFormatting {
    /// Clamps a percent value into 0...100 for visual progress. Non-finite or
    /// missing values clamp to 0.
    static func clampedPercent(_ percent: Double?) -> Double {
        guard let percent, percent.isFinite else { return 0 }
        return min(max(percent, 0), 100)
    }

    /// Primary display text, e.g. "31% used". Missing percent shows "—".
    static func percentText(_ percent: Double?) -> String {
        guard let percent, percent.isFinite else { return "—" }
        return "\(Int(clampedPercent(percent).rounded()))% used"
    }

    /// Compact percent for the widget, e.g. "31%". Missing percent shows "—".
    static func shortPercentText(_ percent: Double?) -> String {
        guard let percent, percent.isFinite else { return "—" }
        return "\(Int(clampedPercent(percent).rounded()))%"
    }

    /// Reset time text. Same-day resets are relative ("resets in 2h"); later
    /// resets use a short date/time. Missing reset time returns nil so the
    /// label can be hidden.
    static func resetText(for resetsAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resets soon" }
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            let hours = Int(interval / 3600)
            let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
            if hours > 0 { return "resets in \(hours)h" }
            if minutes > 0 { return "resets in \(minutes)m" }
            return "resets in <1m"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "resets \(formatter.string(from: resetsAt))"
    }

    /// Grouped integer text, e.g. "123,456".
    static func groupedNumberText(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Compact token count for the widget, e.g. "812", "284k", "1.2M".
    static func compactTokenText(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            let text = String(format: "%.1f", millions)
            return "\(text.hasSuffix(".0") ? String(text.dropLast(2)) : text)M"
        }
        if tokens >= 1_000 {
            return "\(Int((Double(tokens) / 1_000).rounded()))k"
        }
        return "\(tokens)"
    }

    /// Cache age text, e.g. "just now", "12m ago", "3h ago".
    static func cacheAgeText(fetchedAt: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(fetchedAt))
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86_400))d ago"
    }
}
