import Foundation
import Security

protocol TokenReading {
    func readToken() -> String?
}

protocol KeychainReading {
    func readGenericPassword(service: String) -> Data?
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
}

/// Reads the local Claude Code OAuth token. Tries the credentials file first,
/// then the macOS Keychain. The token is never logged, cached, or shown in UI.
struct ClaudeTokenReader: TokenReading {
    static let keychainService = "Claude Code-credentials"

    var credentialsFileURL: URL
    var keychain: KeychainReading

    init(
        credentialsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json"),
        keychain: KeychainReading = SystemKeychainReader()
    ) {
        self.credentialsFileURL = credentialsFileURL
        self.keychain = keychain
    }

    func readToken() -> String? {
        if let data = try? Data(contentsOf: credentialsFileURL),
           let json = String(data: data, encoding: .utf8),
           let token = Self.extractToken(fromJSON: json) {
            return token
        }
        if let data = keychain.readGenericPassword(service: Self.keychainService),
           let json = String(data: data, encoding: .utf8),
           let token = Self.extractToken(fromJSON: json) {
            return token
        }
        return nil
    }

    /// Extracts an access token from raw credentials JSON. Supports both
    /// `{"claudeAiOauth": {"accessToken": "..."}}` and `{"accessToken": "..."}`.
    static func extractToken(fromJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           !token.isEmpty {
            return token
        }
        if let token = object["accessToken"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }
}
