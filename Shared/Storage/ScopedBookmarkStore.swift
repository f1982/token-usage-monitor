import Foundation

/// Persists user-granted access to directories outside the app container.
/// Bookmark data is stored in the App Group so the app and its extension can
/// share the selection metadata without sharing access to the source files.
struct ScopedBookmarkStore {
    enum Key: String {
        case claudeProjects
        case codexSessions
        case statusline
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = AppGroup.userDefaults) {
        self.defaults = defaults ?? .standard
    }

    @discardableResult
    func save(_ url: URL, for key: Key) -> Bool {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return false }

        defaults.set(data, forKey: storageKey(for: key))
        return true
    }

    func resolve(_ key: Key) -> URL? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            _ = save(url, for: key)
        }
        return url
    }

    func remove(_ key: Key) {
        defaults.removeObject(forKey: storageKey(for: key))
    }

    private func storageKey(for key: Key) -> String {
        "scoped-bookmark-\(key.rawValue)-v1"
    }
}
