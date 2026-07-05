import XCTest

final class StatuslineUsageProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_700_000)
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatuslineUsageProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var fileURL: URL { directory.appendingPathComponent("latest.json") }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func writeStateFile(capturedAt: Date, rateLimits: String) throws {
        let json = """
        {
          "schemaVersion": 1,
          "source": "claude-code-statusline",
          "capturedAt": "\(isoString(capturedAt))",
          "rateLimits": \(rateLimits)
        }
        """
        try Data(json.utf8).write(to: fileURL)
    }

    private func makeProvider() -> StatuslineUsageProvider {
        StatuslineUsageProvider(fileURL: fileURL, now: { self.now })
    }

    func testValidFreshFileReturnsOfficialSnapshot() async throws {
        try writeStateFile(capturedAt: now.addingTimeInterval(-60), rateLimits: """
        {
          "session": {"kind": "session", "label": "Session", "percent": 31, "resetsAt": "\(isoString(now.addingTimeInterval(4 * 3600)))"},
          "weekly": {"kind": "weekly_all", "label": "All models", "percent": 42},
          "weeklyScoped": [{"kind": "weekly_scoped", "label": "Fable", "percent": 23}]
        }
        """)

        let result = await makeProvider().fetchQuotaUsage()

        let snapshot = try XCTUnwrap(result.value)
        XCTAssertNil(result.error)
        XCTAssertEqual(snapshot.provenance, .official)
        XCTAssertEqual(snapshot.session?.percent, 31)
        XCTAssertNotNil(snapshot.session?.resetsAt)
        XCTAssertEqual(snapshot.weekly?.percent, 42)
        XCTAssertEqual(snapshot.weeklyScoped.count, 1)
        XCTAssertEqual(snapshot.weeklyScoped.first?.label, "Fable")
        XCTAssertEqual(snapshot.fetchedAt, now.addingTimeInterval(-60))
    }

    func testMissingFileReturnsMissingError() async {
        let result = await makeProvider().fetchQuotaUsage()

        XCTAssertNil(result.value)
        XCTAssertEqual(result.error, .missing)
    }

    func testStaleFileReturnsStaleError() async throws {
        try writeStateFile(capturedAt: now.addingTimeInterval(-11 * 60), rateLimits: """
        {"weekly": {"kind": "weekly_all", "label": "All models", "percent": 42}}
        """)

        let result = await makeProvider().fetchQuotaUsage()

        XCTAssertNil(result.value)
        XCTAssertEqual(result.error, .staleData)
    }

    func testFileAtFreshnessBoundaryIsStillFresh() async throws {
        try writeStateFile(capturedAt: now.addingTimeInterval(-StatuslineUsageProvider.freshnessWindow), rateLimits: """
        {"weekly": {"kind": "weekly_all", "label": "All models", "percent": 42}}
        """)

        let result = await makeProvider().fetchQuotaUsage()

        XCTAssertNotNil(result.value)
    }

    func testInvalidJSONReturnsParseError() async throws {
        try Data("{not valid json".utf8).write(to: fileURL)

        let result = await makeProvider().fetchQuotaUsage()

        XCTAssertNil(result.value)
        XCTAssertEqual(result.error, .parseFailure)
    }

    func testMissingCapturedAtReturnsParseError() async throws {
        try Data(#"{"schemaVersion": 1, "rateLimits": {}}"#.utf8).write(to: fileURL)

        let result = await makeProvider().fetchQuotaUsage()

        XCTAssertEqual(result.error, .parseFailure)
    }

    func testMissingRateLimitsReturnsUnavailable() async throws {
        try writeStateFile(capturedAt: now.addingTimeInterval(-60), rateLimits: "{}")

        let result = await makeProvider().fetchQuotaUsage()

        XCTAssertNil(result.value)
        XCTAssertEqual(result.error, .unavailable)
    }
}
