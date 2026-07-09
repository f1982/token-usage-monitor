import Foundation

struct UsageHistoryPoint: Codable, Equatable, Identifiable {
    let timestamp: Date
    let sessionPercent: Double?
    let weeklyPercent: Double?
    let codexPercent: Double?

    var id: Date { timestamp }

    init(snapshot: ClaudeUsageSnapshot, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.sessionPercent = snapshot.session?.percent
        self.weeklyPercent = snapshot.weekly?.percent
        self.codexPercent = snapshot.codex.first?.percent
    }
}

struct UsageHistoryStore {
    static let retention: TimeInterval = 30 * 86_400
    let fileURL: URL?
    let now: () -> Date

    init(fileURL: URL? = AppGroup.usageHistoryFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    func read() -> [UsageHistoryPoint] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageHistoryPoint].self, from: data)) ?? []
    }

    func append(snapshot: ClaudeUsageSnapshot) {
        guard let fileURL else { return }
        let currentTime = now()
        var points = read().filter { currentTime.timeIntervalSince($0.timestamp) <= Self.retention }
        let point = UsageHistoryPoint(snapshot: snapshot, timestamp: currentTime)

        if let last = points.last, currentTime.timeIntervalSince(last.timestamp) < 5 * 60 {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(points) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
