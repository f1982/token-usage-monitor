import XCTest

private struct StubTokenReader: TokenReading {
    var token: String?
    func readToken() -> String? { token }
}

private struct StubUsageClient: UsageFetching {
    var result: Result<ClaudeUsageSnapshot, UsageClientError>
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageSnapshot {
        try result.get()
    }
}

final class OAuthUsageProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_700_000)

    private func snapshot() -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            available: true,
            session: nil,
            weekly: UsageLimit(id: "weekly", kind: "weekly_all", label: "All models", percent: 42, resetsAt: nil),
            weeklyScoped: [],
            note: nil,
            fetchedAt: now
        )
    }

    func testMissingTokenReturnsNoCredentials() async {
        let provider = OAuthUsageProvider(
            tokenReader: StubTokenReader(token: nil),
            usageClient: StubUsageClient(result: .success(snapshot())),
            now: { self.now }
        )

        let result = await provider.fetchQuotaUsage()

        XCTAssertNil(result.value)
        XCTAssertEqual(result.error, .noCredentials)
    }

    func testSuccessMarksSnapshotExperimental() async throws {
        let provider = OAuthUsageProvider(
            tokenReader: StubTokenReader(token: "sk-test"),
            usageClient: StubUsageClient(result: .success(snapshot())),
            now: { self.now }
        )

        let result = await provider.fetchQuotaUsage()

        let value = try XCTUnwrap(result.value)
        XCTAssertEqual(value.provenance, .experimental)
        XCTAssertEqual(result.provenance, .experimental)
    }

    func testClientErrorsAreMapped() async {
        let provider = OAuthUsageProvider(
            tokenReader: StubTokenReader(token: "sk-test"),
            usageClient: StubUsageClient(result: .failure(.unauthorized)),
            now: { self.now }
        )

        let result = await provider.fetchQuotaUsage()

        XCTAssertEqual(result.error, .unauthorized)
    }

    func testErrorMapping() {
        XCTAssertEqual(OAuthUsageProvider.mapError(.unauthorized), .unauthorized)
        XCTAssertEqual(OAuthUsageProvider.mapError(.rateLimited), .rateLimited)
        XCTAssertEqual(OAuthUsageProvider.mapError(.notJSON), .parseFailure)
        XCTAssertEqual(OAuthUsageProvider.mapError(.badStatus(500)), .network("usage endpoint returned HTTP 500"))
        XCTAssertEqual(OAuthUsageProvider.mapError(.network("boom")), .network("boom"))
    }
}
