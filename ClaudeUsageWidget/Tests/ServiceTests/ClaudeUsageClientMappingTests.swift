import XCTest

final class ClaudeUsageClientMappingTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_751_700_000)

    private func decodeRaw(_ json: String) throws -> RawUsageResponse {
        try JSONDecoder().decode(RawUsageResponse.self, from: Data(json.utf8))
    }

    func testMapsSessionWeeklyAndScopedLimits() throws {
        let json = """
        {
          "limits": [
            {"kind": "session", "group": "usage", "percent": 42.5, "resets_at": "2026-07-05T10:00:00Z", "is_active": true},
            {"kind": "weekly_all", "group": "usage", "percent": 31.0, "resets_at": "2026-07-09T00:00:00.123Z"},
            {"kind": "weekly_scoped", "group": "usage", "percent": 12.0, "scope": {"model": {"display_name": "Fable"}}}
          ]
        }
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)

        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.session?.label, "Session")
        XCTAssertEqual(snapshot.session?.percent, 42.5)
        XCTAssertNotNil(snapshot.session?.resetsAt)
        XCTAssertEqual(snapshot.weekly?.label, "All models")
        XCTAssertEqual(snapshot.weekly?.percent, 31.0)
        XCTAssertNotNil(snapshot.weekly?.resetsAt, "fractional-second timestamps should parse")
        XCTAssertEqual(snapshot.weeklyScoped.count, 1)
        XCTAssertEqual(snapshot.weeklyScoped.first?.label, "Fable")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testScopedLimitWithoutDisplayNameUsesWeeklyLabel() throws {
        let json = """
        {"limits": [{"kind": "weekly_scoped", "group": "usage", "percent": 7.0}]}
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.weeklyScoped.first?.label, "Weekly")
    }

    func testMissingWeeklyAllFallsBackToSevenDay() throws {
        let json = """
        {
          "limits": [{"kind": "session", "group": "usage", "percent": 10.0}],
          "seven_day": {"utilization": 55.0, "resets_at": "2026-07-09T00:00:00Z"}
        }
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.weekly?.label, "All models")
        XCTAssertEqual(snapshot.weekly?.percent, 55.0)
        XCTAssertNotNil(snapshot.weekly?.resetsAt)
    }

    func testWeeklyAllPreferredOverSevenDay() throws {
        let json = """
        {
          "limits": [{"kind": "weekly_all", "group": "usage", "percent": 31.0}],
          "seven_day": {"utilization": 99.0}
        }
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.weekly?.percent, 31.0)
    }

    func testMissingLimitsDoesNotCrash() throws {
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw("{}"), fetchedAt: fetchedAt)
        XCTAssertFalse(snapshot.available)
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
        XCTAssertTrue(snapshot.weeklyScoped.isEmpty)
    }

    func testUnknownKindsAreIgnored() throws {
        let json = """
        {"limits": [{"kind": "monthly_mystery", "group": "usage", "percent": 50.0}]}
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)
        XCTAssertFalse(snapshot.available)
    }

    func testActiveSessionEntryPreferredOverInactive() throws {
        let json = """
        {
          "limits": [
            {"kind": "session", "group": "usage", "percent": 1.0, "is_active": false},
            {"kind": "session", "group": "usage", "percent": 88.0, "is_active": true}
          ]
        }
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.session?.percent, 88.0)
    }

    func testBadDatesMapToNilResetInsteadOfFailing() throws {
        let json = """
        {"limits": [{"kind": "session", "group": "usage", "percent": 10.0, "resets_at": "not-a-date"}]}
        """
        let snapshot = ClaudeUsageClient.makeSnapshot(from: try decodeRaw(json), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.session?.percent, 10.0)
        XCTAssertNil(snapshot.session?.resetsAt)
    }

    func testParseISODateSupportsBothFormats() {
        XCTAssertNotNil(ClaudeUsageClient.parseISODate("2026-07-05T10:00:00Z"))
        XCTAssertNotNil(ClaudeUsageClient.parseISODate("2026-07-05T10:00:00.123Z"))
        XCTAssertNotNil(ClaudeUsageClient.parseISODate("2026-07-05T10:00:00+08:00"))
        XCTAssertNil(ClaudeUsageClient.parseISODate("garbage"))
        XCTAssertNil(ClaudeUsageClient.parseISODate(nil))
    }
}
