import Combine
import Foundation

/// Persists user-facing usage settings in App Group `UserDefaults` so both
/// the app (read/write) and the widget (read-only) see the same values.
@MainActor
final class UsageSettingsStore: ObservableObject {
    nonisolated static let storageKey = "usage-settings-v1"

    @Published var settings: UsageSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = AppGroup.userDefaults) {
        let resolved = defaults ?? .standard
        self.defaults = resolved
        self.settings = Self.read(from: resolved)
    }

    /// Snapshot read for non-observing consumers (widget timeline provider).
    nonisolated static func readShared(defaults: UserDefaults? = AppGroup.userDefaults) -> UsageSettings {
        guard let defaults else { return .default }
        return read(from: defaults)
    }

    nonisolated private static func read(from defaults: UserDefaults) -> UsageSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(UsageSettings.self, from: data)
        else { return .default }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
