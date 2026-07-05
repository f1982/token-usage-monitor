import Foundation

struct ProjectUsageCache: Codable, Equatable {
    var schemaVersion: Int
    var generatedAt: Date
    var rootPath: String
    var timeRange: ProjectUsageTimeRange
    var summaries: [ProjectUsageSummary]
}

protocol ProjectUsageCacheStoring {
    func read() -> ProjectUsageCache?
    func write(_ cache: ProjectUsageCache)
}

/// Reads and writes aggregated project usage summaries in the App Group
/// container. Stores aggregate numbers only — never raw JSONL lines, prompt
/// text, or message content.
struct ProjectUsageCacheStore: ProjectUsageCacheStoring {
    static let schemaVersion = 1

    let fileURL: URL?

    init(fileURL: URL? = AppGroup.projectUsageFileURL) {
        self.fileURL = fileURL
    }

    func read() -> ProjectUsageCache? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Corrupt cache is ignored safely.
        return try? decoder.decode(ProjectUsageCache.self, from: data)
    }

    func write(_ cache: ProjectUsageCache) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
