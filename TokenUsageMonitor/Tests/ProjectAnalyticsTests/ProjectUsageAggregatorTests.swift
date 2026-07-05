import XCTest

final class ProjectUsageAggregatorTests: XCTestCase {
    // Noon UTC on a fixed day, evaluated in a fixed UTC calendar so "today"
    // boundaries are deterministic.
    private let now = Date(timeIntervalSince1970: 1_783_339_200)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func event(
        id: String,
        project: String = "alpha",
        path: String? = "/dev/alpha",
        timestamp: Date? = nil,
        model: String? = nil,
        input: Int = 0,
        output: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0
    ) -> ProjectUsageEvent {
        ProjectUsageEvent(
            stableID: id,
            projectName: project,
            projectPath: path,
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            totalTokens: input + output + cacheCreation + cacheRead
        )
    }

    private func aggregate(
        _ events: [ProjectUsageEvent],
        range: ProjectUsageTimeRange = .all
    ) -> [ProjectUsageSummary] {
        ProjectUsageAggregator.aggregate(events: events, range: range, now: now, calendar: utcCalendar)
    }

    func testGroupsByProject() {
        let summaries = aggregate([
            event(id: "1", project: "alpha", path: "/dev/alpha", input: 10),
            event(id: "2", project: "beta", path: "/dev/beta", input: 20),
            event(id: "3", project: "alpha", path: "/dev/alpha", input: 5),
        ])

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.first { $0.projectName == "alpha" }?.messageCount, 2)
        XCTAssertEqual(summaries.first { $0.projectName == "beta" }?.messageCount, 1)
    }

    func testSumsTokenFields() {
        let summaries = aggregate([
            event(id: "1", input: 10, output: 20, cacheCreation: 30, cacheRead: 40),
            event(id: "2", input: 1, output: 2, cacheCreation: 3, cacheRead: 4),
        ])

        let summary = summaries[0]
        XCTAssertEqual(summary.inputTokens, 11)
        XCTAssertEqual(summary.outputTokens, 22)
        XCTAssertEqual(summary.cacheCreationTokens, 33)
        XCTAssertEqual(summary.cacheReadTokens, 44)
        XCTAssertEqual(summary.totalTokens, 110)
        XCTAssertEqual(summary.source, .localEstimate)
    }

    func testDeduplicatesByStableID() {
        let summaries = aggregate([
            event(id: "dup", input: 100),
            event(id: "dup", input: 100),
            event(id: "other", input: 1),
        ])

        XCTAssertEqual(summaries[0].totalTokens, 101)
        XCTAssertEqual(summaries[0].messageCount, 2)
    }

    func testSortsByTotalTokensDescending() {
        let summaries = aggregate([
            event(id: "1", project: "small", path: "/dev/small", input: 10),
            event(id: "2", project: "big", path: "/dev/big", input: 1000),
            event(id: "3", project: "medium", path: "/dev/medium", input: 100),
        ])

        XCTAssertEqual(summaries.map(\.projectName), ["big", "medium", "small"])
    }

    func testFiltersToday() {
        let summaries = aggregate([
            event(id: "today", timestamp: now.addingTimeInterval(-3600), input: 1),
            event(id: "yesterday", timestamp: now.addingTimeInterval(-13 * 3600), input: 1),
        ], range: .today)

        // 12:00Z now: -1h is the same UTC day, -13h is the previous day.
        XCTAssertEqual(summaries.first?.messageCount, 1)
    }

    func testFiltersLast7Days() {
        let summaries = aggregate([
            event(id: "in", timestamp: now.addingTimeInterval(-6 * 86_400), input: 1),
            event(id: "out", timestamp: now.addingTimeInterval(-8 * 86_400), input: 1),
        ], range: .last7Days)

        XCTAssertEqual(summaries.first?.messageCount, 1)
    }

    func testFiltersLast30Days() {
        let summaries = aggregate([
            event(id: "in", timestamp: now.addingTimeInterval(-29 * 86_400), input: 1),
            event(id: "out", timestamp: now.addingTimeInterval(-31 * 86_400), input: 1),
        ], range: .last30Days)

        XCTAssertEqual(summaries.first?.messageCount, 1)
    }

    func testUnknownTimestampIncludedOnlyInAllTime() {
        let events = [event(id: "unknown", timestamp: nil, input: 1)]

        XCTAssertEqual(aggregate(events, range: .all).first?.messageCount, 1)
        XCTAssertTrue(aggregate(events, range: .today).isEmpty)
        XCTAssertTrue(aggregate(events, range: .last7Days).isEmpty)
        XCTAssertTrue(aggregate(events, range: .last30Days).isEmpty)
    }

    func testTracksFirstAndLastUsage() {
        let early = now.addingTimeInterval(-3 * 86_400)
        let late = now.addingTimeInterval(-3600)
        let summaries = aggregate([
            event(id: "1", timestamp: late, input: 1),
            event(id: "2", timestamp: early, input: 1),
            event(id: "3", timestamp: nil, input: 1),
        ])

        XCTAssertEqual(summaries[0].firstUsedAt, early)
        XCTAssertEqual(summaries[0].lastUsedAt, late)
    }

    func testProducesUniqueSortedModelNames() {
        let summaries = aggregate([
            event(id: "1", model: "claude-sonnet-5", input: 1),
            event(id: "2", model: "claude-haiku-4-5", input: 1),
            event(id: "3", model: "claude-sonnet-5", input: 1),
            event(id: "4", model: nil, input: 1),
        ])

        XCTAssertEqual(summaries[0].models, ["claude-haiku-4-5", "claude-sonnet-5"])
    }

    func testSummaryIDIsStableForSamePath() {
        let first = aggregate([event(id: "1", input: 1)])
        let second = aggregate([event(id: "2", input: 5)])

        XCTAssertEqual(first[0].id, second[0].id)
    }

    func testEventsWithoutPathGroupByName() {
        let summaries = aggregate([
            event(id: "1", project: "orphan", path: nil, input: 1),
            event(id: "2", project: "orphan", path: nil, input: 2),
        ])

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].totalTokens, 3)
        XCTAssertNil(summaries[0].projectPath)
    }
}
