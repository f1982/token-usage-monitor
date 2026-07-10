import XCTest

final class ClaudeTokenReaderTests: XCTestCase {
    private final class MockKeychain: KeychainReading {
        var value: Data?
        init(value: Data? = nil) { self.value = value }
        func readGenericPassword(service: String) -> Data? { value }
        @discardableResult
        func saveGenericPassword(_ data: Data, service: String) -> Bool { value = data; return true }
        func deleteGenericPassword(service: String) { value = nil }
    }

    func testReadsUserSuppliedTokenFromKeychain() {
        let reader = ClaudeTokenReader(keychain: MockKeychain(value: Data(" sk-from-keychain \n".utf8)))
        XCTAssertEqual(reader.readToken(), "sk-from-keychain")
    }

    func testSavesAndRemovesTokenInKeychain() {
        let keychain = MockKeychain()
        let reader = ClaudeTokenReader(keychain: keychain)
        XCTAssertTrue(reader.saveToken(" sk-saved \n"))
        XCTAssertEqual(reader.readToken(), "sk-saved")
        reader.removeToken()
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
