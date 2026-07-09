import XCTest

final class ClaudeTokenReaderTests: XCTestCase {
    // MARK: - Pure token extraction

    func testExtractsNestedClaudeAiOauthToken() {
        let json = #"{"claudeAiOauth": {"accessToken": "sk-test-nested"}}"#
        XCTAssertEqual(ClaudeTokenReader.extractToken(fromJSON: json), "sk-test-nested")
    }

    func testExtractsTopLevelToken() {
        let json = #"{"accessToken": "sk-test-top"}"#
        XCTAssertEqual(ClaudeTokenReader.extractToken(fromJSON: json), "sk-test-top")
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(ClaudeTokenReader.extractToken(fromJSON: "not json at all"))
    }

    func testMissingTokenReturnsNil() {
        XCTAssertNil(ClaudeTokenReader.extractToken(fromJSON: #"{"claudeAiOauth": {}}"#))
        XCTAssertNil(ClaudeTokenReader.extractToken(fromJSON: #"{"somethingElse": true}"#))
    }

    func testEmptyTokenReturnsNil() {
        XCTAssertNil(ClaudeTokenReader.extractToken(fromJSON: #"{"accessToken": ""}"#))
        XCTAssertNil(ClaudeTokenReader.extractToken(fromJSON: #"{"claudeAiOauth": {"accessToken": ""}}"#))
    }

    func testNestedTokenPreferredButFallsBackToTopLevel() {
        let json = #"{"claudeAiOauth": {}, "accessToken": "sk-fallback"}"#
        XCTAssertEqual(ClaudeTokenReader.extractToken(fromJSON: json), "sk-fallback")
    }

    // MARK: - Source priority

    private struct MockKeychain: KeychainReading {
        var value: Data?
        func readGenericPassword(service: String) -> Data? { value }
    }

    private func writeTempCredentials(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeTokenReaderTests-\(UUID().uuidString).json")
        try Data(contents.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testReadsTokenFromCredentialsFile() throws {
        let fileURL = try writeTempCredentials(#"{"claudeAiOauth": {"accessToken": "sk-from-file"}}"#)
        let reader = ClaudeTokenReader(credentialsFileURL: fileURL, keychain: MockKeychain(value: nil))
        XCTAssertEqual(reader.readToken(), "sk-from-file")
    }

    func testFallsBackToKeychainWhenFileMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let keychain = MockKeychain(value: Data(#"{"claudeAiOauth": {"accessToken": "sk-from-keychain"}}"#.utf8))
        let reader = ClaudeTokenReader(credentialsFileURL: missing, keychain: keychain)
        XCTAssertEqual(reader.readToken(), "sk-from-keychain")
    }

    func testFallsBackToKeychainWhenFileHasNoToken() throws {
        let fileURL = try writeTempCredentials(#"{"other": true}"#)
        let keychain = MockKeychain(value: Data(#"{"accessToken": "sk-from-keychain"}"#.utf8))
        let reader = ClaudeTokenReader(credentialsFileURL: fileURL, keychain: keychain)
        XCTAssertEqual(reader.readToken(), "sk-from-keychain")
    }

    func testReturnsNilWhenNoSourceHasToken() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let reader = ClaudeTokenReader(credentialsFileURL: missing, keychain: MockKeychain(value: nil))
        XCTAssertNil(reader.readToken())
    }
}

private final class CountingTokenReader: TokenReading {
    private(set) var callCount = 0
    let token: String?

    init(token: String?) {
        self.token = token
    }

    func readToken() -> String? {
        callCount += 1
        return token
    }
}

final class MemoizingTokenReaderTests: XCTestCase {
    func testReadsUnderlyingReaderOnlyOnceForSuccessfulToken() {
        let underlying = CountingTokenReader(token: "token")
        let reader = MemoizingTokenReader(reader: underlying)

        XCTAssertEqual(reader.readToken(), "token")
        XCTAssertEqual(reader.readToken(), "token")
        XCTAssertEqual(underlying.callCount, 1)
    }

    func testCachesMissingTokenToAvoidRepeatedKeychainPrompts() {
        let underlying = CountingTokenReader(token: nil)
        let reader = MemoizingTokenReader(reader: underlying)

        XCTAssertNil(reader.readToken())
        XCTAssertNil(reader.readToken())
        XCTAssertEqual(underlying.callCount, 1)
    }

    func testInvalidationPreventsFurtherCredentialReads() {
        let underlying = CountingTokenReader(token: "token")
        let reader = MemoizingTokenReader(reader: underlying)

        XCTAssertEqual(reader.readToken(), "token")
        reader.invalidate()

        XCTAssertNil(reader.readToken())
        XCTAssertEqual(underlying.callCount, 1)
    }
}
