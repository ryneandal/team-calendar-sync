import XCTest

@testable import CalendarCore

final class ICalendarEdgeCaseTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func event(_ properties: String) -> String {
        "BEGIN:VEVENT\r\n\(properties)\r\nEND:VEVENT"
    }

    private func parse(
        _ events: [String], now: String = "2026-10-01T00:00:00Z",
        zone: TimeZone? = nil
    ) throws -> FeedPreview {
        let body = events.joined(separator: "\r\n")
        let data = Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(body)\r\nEND:VCALENDAR\r\n".utf8)
        return try ICalendarParser.parse(data, now: date(now), localTimeZone: zone ?? utc)
    }

    func testTimedDurationKeepsAnOngoingEventInThePreview() throws {
        let preview = try parse([event("UID:match\r\nDTSTART:20261001T090000Z\r\nDURATION:+PT3H15M30S")])
        XCTAssertEqual(preview.events.first?.end, date("2026-10-01T12:15:30Z"))
        XCTAssertEqual(preview.upcoming(after: date("2026-10-01T10:00:00Z")).count, 1)
        XCTAssertTrue(preview.upcoming(after: date("2026-10-01T13:00:00Z")).isEmpty)
        XCTAssertEqual(preview.skippedEvents, 0)
    }

    func testAllDayWeekDurationUsesCalendarDaysAcrossDST() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let preview = try parse(
            [event("UID:festival\r\nDTSTART;VALUE=DATE:20260306\r\nDURATION:P1W")],
            now: "2026-03-10T12:00:00Z", zone: zone)
        let festival = try XCTUnwrap(preview.events.first)
        XCTAssertEqual(festival.end, date("2026-03-13T04:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(festival.end).timeIntervalSince(festival.start), 167 * 3_600)
        XCTAssertEqual(preview.upcoming(after: date("2026-03-10T12:00:00Z")).count, 1)
    }

    func testRecurringNominalDurationIsRecomputedAcrossDST() throws {
        let preview = try parse(
            [
                event(
                    "UID:daily\r\nDTSTART;TZID=America/New_York:20260307T120000\r\nDURATION:P1D\r\nRRULE:FREQ=DAILY;COUNT=3"
                )
            ],
            now: "2026-03-07T00:00:00Z")
        XCTAssertEqual(
            preview.events.compactMap { $0.end?.timeIntervalSince($0.start) },
            [23 * 3_600, 24 * 3_600, 24 * 3_600])
        XCTAssertEqual(preview.events.last?.end, date("2026-03-10T16:00:00Z"))
    }

    func testNominalDaysAreAppliedBeforeExactHours() throws {
        let preview = try parse(
            [event("UID:mixed\r\nDTSTART;TZID=America/New_York:20260307T120000\r\nDURATION:P1DT2H")],
            now: "2026-03-07T00:00:00Z")
        XCTAssertEqual(preview.events.first?.end, date("2026-03-08T18:00:00Z"))
    }

    func testInvalidAndUnsupportedDurationsAreDisclosedAsSkippedEvents() throws {
        let invalid = [
            "P", "PT", "P1DT", "-PT1H", "PT0S", "P1M", "P1Y", "PT1.5H",
            "P1W2D", "PT1S2H", "P999999999999999999999999D", "P20001D",
        ]
        for value in invalid {
            let preview = try parse([event("UID:invalid\r\nDTSTART:20261001T090000Z\r\nDURATION:\(value)")])
            XCTAssertTrue(preview.events.isEmpty, value)
            XCTAssertEqual(preview.skippedEvents, 1, value)
        }
        let invalidAllDay = try parse([event("UID:all-day\r\nDTSTART;VALUE=DATE:20261001\r\nDURATION:PT24H")])
        XCTAssertTrue(invalidAllDay.events.isEmpty)
        XCTAssertEqual(invalidAllDay.skippedEvents, 1)
        let conflictingEnd = try parse([
            event("UID:conflict\r\nDTSTART:20261001T090000Z\r\nDTEND:20261001T110000Z\r\nDURATION:PT3H")
        ])
        XCTAssertTrue(conflictingEnd.events.isEmpty)
        XCTAssertEqual(conflictingEnd.skippedEvents, 1)
    }

    func testThisAndFutureDoesNotInventUnchangedFutureDates() throws {
        let master = event("UID:show\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=WEEKLY;COUNT=4")
        let moved = event("UID:show\r\nRECURRENCE-ID;RANGE=THISANDFUTURE:20261008T190000Z\r\nDTSTART:20261009T190000Z")
        for events in [[master, moved], [moved, master]] {
            let preview = try parse(events)
            XCTAssertTrue(preview.hasUnexpandedRecurrence)
            XCTAssertEqual(preview.events.map(\.start), [date("2026-10-01T19:00:00Z"), date("2026-10-09T19:00:00Z")])
        }
    }

    func testCancelledThisAndFutureRangeDoesNotRegenerateLaterInstances() throws {
        let master = event("UID:show\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=WEEKLY;COUNT=4")
        let cancelled = event("UID:show\r\nRECURRENCE-ID;RANGE=THISANDFUTURE:20261008T190000Z\r\nSTATUS:CANCELLED")
        let preview = try parse([master, cancelled])
        XCTAssertTrue(preview.hasUnexpandedRecurrence)
        XCTAssertEqual(preview.events.map(\.start), [date("2026-10-01T19:00:00Z")])
    }

    func testOngoingMultiDayRecurrenceIsIncludedForExplicitEndAndDuration() throws {
        for end in ["DTEND;VALUE=DATE:20260908", "DURATION:P7D"] {
            let preview = try parse(
                [event("UID:tournament\r\nDTSTART;VALUE=DATE:20260901\r\n\(end)\r\nRRULE:FREQ=WEEKLY")],
                now: "2026-10-02T12:00:00Z")
            let current = try XCTUnwrap(preview.upcoming(after: date("2026-10-02T12:00:00Z")).first)
            XCTAssertEqual(current.start, date("2026-09-29T00:00:00Z"), end)
            XCTAssertEqual(current.end, date("2026-10-06T00:00:00Z"), end)
            XCTAssertFalse(preview.hasUnexpandedRecurrence, end)
        }
    }

    func testOngoingTimedRecurrenceIsIncludedAcrossDST() throws {
        let preview = try parse(
            [
                event(
                    "UID:retreat\r\nDTSTART;TZID=America/New_York:20260227T120000\r\nDURATION:P7D\r\nRRULE:FREQ=WEEKLY")
            ],
            now: "2026-03-10T12:00:00Z")
        let current = try XCTUnwrap(preview.upcoming(after: date("2026-03-10T12:00:00Z")).first)
        XCTAssertEqual(current.start, date("2026-03-06T17:00:00Z"))
        XCTAssertEqual(current.end, date("2026-03-13T16:00:00Z"))
        XCTAssertFalse(preview.hasUnexpandedRecurrence)
    }

    func testRecurrenceWorkBudgetIsSharedAcrossSeries() {
        var remaining = 3
        let start = date("2026-10-01T19:00:00Z")
        let now = date("2026-10-01T00:00:00Z")
        let first = RecurrenceExpander.dates(
            rule: "FREQ=DAILY;COUNT=2", start: start, timeZone: utc,
            now: now, until: nil, eventLength: 0,
            remainingCandidateDays: &remaining)
        XCTAssertEqual(first, [date("2026-10-02T19:00:00Z")])
        XCTAssertEqual(remaining, 1)
        let second = RecurrenceExpander.dates(
            rule: "FREQ=DAILY;COUNT=2", start: start, timeZone: utc,
            now: now, until: nil, eventLength: 0,
            remainingCandidateDays: &remaining)
        XCTAssertNil(second)
        XCTAssertEqual(remaining, 0)
    }

    func testExhaustedFeedWorkBudgetDisclosesIncompletePreview() throws {
        let ancient = event("UID:ancient\r\nDTSTART:19000101T120000Z\r\nRRULE:FREQ=DAILY;COUNT=1000000")
        let recent = event("UID:recent\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=DAILY;COUNT=2")
        let preview = try parse([ancient, recent])
        XCTAssertTrue(preview.hasUnexpandedRecurrence)
        XCTAssertEqual(preview.events.map(\.id), ["ancient|", "recent|"])
    }
}
