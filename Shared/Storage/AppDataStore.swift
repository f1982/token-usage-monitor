import Foundation

/// Owns the aggregate data files shared by the app and widget.
/// Removing these files is the user's explicit "clear local data" action.
struct AppDataStore {
    var fileManager: FileManager = .default
    var fileURLs: [URL?] = [
        AppGroup.snapshotFileURL,
        AppGroup.projectUsageFileURL,
        AppGroup.usageHistoryFileURL,
    ]

    func clearCaches() {
        fileURLs
        .compactMap { $0 }
        .forEach { try? fileManager.removeItem(at: $0) }
    }
}
