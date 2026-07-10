import Foundation
import Security

protocol TokenReading {
    func readToken() -> String?
}

protocol KeychainReading {
    func readGenericPassword(service: String) -> Data?
    @discardableResult
    func saveGenericPassword(_ data: Data, service: String) -> Bool
    func deleteGenericPassword(service: String)
}

/// Caches the result of credential discovery for the lifetime of the app.
/// This avoids repeatedly triggering interactive Keychain authorization during
/// automatic refreshes. A failed or invalidated lookup stays unavailable
/// until the app creates a new reader (normally on the next launch).
final class MemoizingTokenReader: TokenReading {
    private let reader: TokenReading
    private let lock = NSLock()
    private var hasRead = false
    private var cachedToken: String?
    private var invalidated = false

    init(reader: TokenReading) {
        self.reader = reader
    }

    func readToken() -> String? {
        lock.lock()
        if hasRead || invalidated {
            let token = cachedToken
            lock.unlock()
            return token
        }
        hasRead = true
        lock.unlock()

        let token = reader.readToken()

        lock.lock()
        cachedToken = token
        lock.unlock()
        return token
    }

    func invalidate() {
        lock.lock()
        cachedToken = nil
        invalidated = true
        lock.unlock()
    }
}

struct SystemKeychainReader: KeychainReading {
    func readGenericPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func saveGenericPassword(_ data: Data, service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status == errSecSuccess }

        let update: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ] as CFDictionary,
            update as CFDictionary
        ) == errSecSuccess
    }

    func deleteGenericPassword(service: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}

/// Reads the OAuth token entered by the user and stored in the macOS Keychain.
/// The app deliberately does not inspect Claude Code's credentials files: doing
/// so would require an implicit, broad filesystem permission in the sandbox.
struct ClaudeTokenReader: TokenReading {
    static let keychainService = "com.example.tokenusagemonitor.oauth-token"
    var keychain: KeychainReading

    init(
        keychain: KeychainReading = SystemKeychainReader()
    ) {
        self.keychain = keychain
    }

    func readToken() -> String? {
        guard let data = keychain.readGenericPassword(service: Self.keychainService),
              let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    func saveToken(_ token: String) -> Bool {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return false }
        return keychain.saveGenericPassword(data, service: Self.keychainService)
    }

    func removeToken() {
        keychain.deleteGenericPassword(service: Self.keychainService)
    }
}
