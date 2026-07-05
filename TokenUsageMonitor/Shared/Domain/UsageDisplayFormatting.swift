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

    /// Verbose countdown to reset, e.g. "resets in 3d 5h", "resets in 4h 12m".
    /// Unlike ``resetText`` (used in the compact widget), this always spells out
    /// the remaining days/hours so the app can pair it with a countdown bar.
    static func resetCountdownText(for resetsAt: Date?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resets soon" }
        let days = Int(interval / 86_400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if days > 0 {
            return hours > 0 ? "resets in \(days)d \(hours)h" : "resets in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(hours)h"
        }
        if minutes > 0 { return "resets in \(minutes)m" }
        return "resets in <1m"
    }

    /// Fraction (0...1) of the reset window still remaining, given the window
    /// length. 1 = the window just started, 0 = reset is due. Returns nil when
    /// the window length is unknown so callers can hide the bar.
    static func resetRemainingFraction(
        for resetsAt: Date?,
        window: TimeInterval?,
        now: Date = Date()
    ) -> Double? {
        guard let resetsAt, let window, window > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(remaining / window, 0), 1)
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
