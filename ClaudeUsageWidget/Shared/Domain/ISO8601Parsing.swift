import Foundation

enum ISO8601Parsing {
    /// Parses ISO8601 timestamps with or without fractional seconds. Bad or
    /// missing strings map to nil instead of failing the caller.
    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
