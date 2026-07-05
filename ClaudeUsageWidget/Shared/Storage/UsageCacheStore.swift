import Foundation

protocol UsageCacheStoring {
    func read() -> ClaudeUsageSnapshot?
    func write(_ snapshot: ClaudeUsageSnapshot)
}

/// Reads and writes the latest normalized usage snapshot in the App Group
/// container. Stores normalized usage only — never OAuth tokens.
struct UsageCacheStore: UsageCacheStoring {
    let fileURL: URL?

    init(fileURL: URL? = AppGroup.snapshotFileURL) {
        self.fileURL = fileURL
    }

    func read() -> ClaudeUsageSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Corrupt cache is ignored safely.
        return try? decoder.decode(ClaudeUsageSnapshot.self, from: data)
    }

    func write(_ snapshot: ClaudeUsageSnapshot) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
