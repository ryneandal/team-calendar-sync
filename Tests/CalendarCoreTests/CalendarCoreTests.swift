import XCTest

@testable import CalendarCore

final class CalendarCoreTests: XCTestCase {
    private func calendar(_ events: String, headers: String = "") -> Data {
        Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(headers)\r\n\(events)\r\nEND:VCALENDAR\r\n".utf8)
    }

    private func event(_ properties: String) -> String {
        "BEGIN:VEVENT\r\n\(properties)\r\nEND:VEVENT"
    }

    func testUTCEventsAreSortedAndPastEventsAreFiltered() throws {
        let data = calendar(
            event("UID:later\r\nDTSTART:20261022T190000Z\r\nSUMMARY:Later match") + "\r\n"
                + event("UID:earlier\r\nDTSTART:20261020T190000Z\r\nSUMMARY:Earlier match"))
        let preview = try ICalendarParser.parse(data)
        XCTAssertEqual(preview.events.map(\.title), ["Earlier match", "Later match"])
        let cutoff = ISO8601DateFormatter().date(from: "2026-10-21T00:00:00Z")!
        XCTAssertEqual(preview.upcoming(after: cutoff).map(\.id), ["later|"])
    }

    func testFoldedUTF8AndEscapedText() throws {
        let data = calendar(
            event(
                "UID:folded\r\nDTSTART:20261022T190000Z\r\nSUMMARY:Atlético\\, Madrid vs. a very\r\n long opponent\r\nLOCATION:Field\\; North\\nGate 2"
            ))
        let preview = try ICalendarParser.parse(data)
        XCTAssertEqual(preview.events.first?.title, "Atlético, Madrid vs. a verylong opponent")
        XCTAssertEqual(preview.events.first?.location, "Field; North\nGate 2")
    }

    func testAlarmPropertiesCannotOverwriteEvent() throws {
        let data = calendar(
            event(
                "UID:match\r\nDTSTART:20261022T190000Z\r\nSUMMARY:Actual match\r\nBEGIN:VALARM\r\nSUMMARY:Alarm title\r\nDESCRIPTION:Reminder\r\nEND:VALARM"
            ))
        XCTAssertEqual(try ICalendarParser.parse(data).events.first?.title, "Actual match")
    }

    func testNamedTimeZoneObservesDaylightSaving() throws {
        let data = calendar(event("UID:madrid\r\nDTSTART;TZID=Europe/Madrid:20260701T210000\r\nSUMMARY:Summer match"))
        let expected = ISO8601DateFormatter().date(from: "2026-07-01T19:00:00Z")!
        XCTAssertEqual(try ICalendarParser.parse(data).events.first?.start, expected)
    }

    func testQuotedTimeZone() throws {
        let data = calendar(event("UID:london\r\nDTSTART;TZID=\"Europe/London\":20260701T200000"))
        let expected = ISO8601DateFormatter().date(from: "2026-07-01T19:00:00Z")!
        XCTAssertEqual(try ICalendarParser.parse(data).events.first?.start, expected)
    }

    func testUnknownTimeZoneIsSkippedInsteadOfInventingTime() throws {
        let data = calendar(event("UID:unknown\r\nDTSTART;TZID=Custom/Unknown:20260701T200000"))
        let preview = try ICalendarParser.parse(data)
        XCTAssertTrue(preview.events.isEmpty)
        XCTAssertEqual(preview.skippedEvents, 1)
    }

    func testFloatingDateUsesCalendarTimeZone() throws {
        let data = calendar(event("UID:floating\r\nDTSTART:20260701T120000"), headers: "X-WR-TIMEZONE:America/New_York")
        let expected = ISO8601DateFormatter().date(from: "2026-07-01T16:00:00Z")!
        XCTAssertEqual(try ICalendarParser.parse(data).events.first?.start, expected)
    }

    func testAllDayEventRemainsUpcomingThroughoutTheDay() throws {
        let data = calendar(
            event("UID:all-day\r\nDTSTART;VALUE=DATE:20261020\r\nSUMMARY:Race day"), headers: "X-WR-TIMEZONE:UTC")
        let preview = try ICalendarParser.parse(data, localTimeZone: TimeZone(secondsFromGMT: 0)!)
        let noon = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        XCTAssertEqual(preview.upcoming(after: noon).count, 1)
        XCTAssertEqual(preview.events.first?.isAllDay, true)
        XCTAssertEqual(preview.events.first?.end?.timeIntervalSince(preview.events.first!.start), 86_400)
    }

    func testAllDayDatesDoNotShiftInSubscriberTimeZone() throws {
        let data = calendar(
            event("UID:all-day\r\nDTSTART;VALUE=DATE:20261020\r\nDTEND;VALUE=DATE:20261021"),
            headers: "X-WR-TIMEZONE:UTC")
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let preview = try ICalendarParser.parse(data, localTimeZone: zone)
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = zone
        let event = try XCTUnwrap(preview.events.first)
        XCTAssertEqual(localCalendar.component(.day, from: event.start), 20)
        XCTAssertEqual(localCalendar.component(.hour, from: event.start), 0)
        XCTAssertEqual(localCalendar.component(.day, from: try XCTUnwrap(event.end)), 21)
    }

    func testAllDayDefaultEndRespectsDaylightSavingBoundary() throws {
        let data = calendar(event("UID:all-day\r\nDTSTART;VALUE=DATE:20260308"))
        let preview = try ICalendarParser.parse(data, localTimeZone: TimeZone(identifier: "America/New_York")!)
        let event = try XCTUnwrap(preview.events.first)
        XCTAssertEqual(try XCTUnwrap(event.end).timeIntervalSince(event.start), 23 * 60 * 60)
    }

    func testCancelledAndMalformedEventsDoNotAppear() throws {
        let data = calendar(
            event("UID:cancelled\r\nDTSTART:20261022T190000Z\r\nSTATUS:CANCELLED") + "\r\n"
                + event("UID:invalid\r\nDTSTART:not-a-date") + "\r\n" + event("UID:valid\r\nDTSTART:20261022T190000Z"))
        let preview = try ICalendarParser.parse(data)
        XCTAssertEqual(preview.events.map(\.id), ["valid|"])
        XCTAssertEqual(preview.skippedEvents, 1)
    }

    func testRecurrenceIsDisclosedAndOverridesAreDistinct() throws {
        let data = calendar(
            event("UID:series\r\nDTSTART:20261022T190000Z\r\nRRULE:FREQ=WEEKLY;COUNT=2") + "\r\n"
                + event("UID:series\r\nRECURRENCE-ID:20261029T190000Z\r\nDTSTART:20261029T200000Z"))
        let preview = try ICalendarParser.parse(data, now: ISO8601DateFormatter().date(from: "2026-10-20T00:00:00Z")!)
        XCTAssertEqual(preview.events.count, 2)
        XCTAssertTrue(preview.containsRecurrence)
    }

    func testHTMLAndTruncatedCalendarsAreRejected() {
        for text in ["<html>Sign in</html>", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR", "BEGIN:VCALENDAR"] {
            XCTAssertThrowsError(try ICalendarParser.parse(Data(text.utf8)))
        }
    }

    func testEmptyCalendarIsValid() throws {
        XCTAssertTrue(try ICalendarParser.parse(calendar("")).events.isEmpty)
    }

    func testOversizedDataIsRejected() {
        XCTAssertThrowsError(try ICalendarParser.parse(Data(repeating: 65, count: FeedClient.maximumBytes + 1))) {
            XCTAssertEqual($0 as? FeedError, .tooLarge)
        }
    }

    func testWebcalNormalizesToHTTPSAndRemovesFragment() throws {
        XCTAssertEqual(
            try FeedURL.validated(" webcal://example.com/team.ics?league=1#section ").absoluteString,
            "https://example.com/team.ics?league=1")
    }

    func testUnsafeURLsAreRejected() {
        let invalid = [
            "http://example.com/a.ics", "file:///tmp/a.ics", "https://user:pass@example.com/a.ics",
            "https://localhost/a", "https://127.0.0.1/a", "https://10.0.0.1/a", "https://[::1]/a",
            "https://calendar.local/a", "https://example.com:8443/a", "javascript:alert(1)",
        ]
        for input in invalid { XCTAssertThrowsError(try FeedURL.validated(input), input) }
    }

    func testGoogleHandoffPreservesQueryParametersAsOneCID() throws {
        let feed = customFeed(url: URL(string: "https://example.com/calendar.ics?team=a&season=2026")!)
        let target = SubscriptionTarget(destination: .google)
        let components = URLComponents(url: try target.handoffURL(for: feed), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "calendar.google.com")
        XCTAssertEqual(components.queryItems?.count, 1)
        XCTAssertEqual(components.queryItems?.first?.value, "webcal://example.com/calendar.ics?team=a&season=2026")
    }

    func testAppleHandoffUsesWebcal() throws {
        let feed = try XCTUnwrap(CalendarFeed.bundled().first)
        XCTAssertEqual(try SubscriptionTarget().handoffURL(for: feed).scheme, "webcal")
    }

    func testExchangeDestinationsAndCustomURLValidation() throws {
        let feed = try XCTUnwrap(CalendarFeed.bundled().first)
        XCTAssertEqual(try SubscriptionTarget(destination: .outlook).handoffURL(for: feed).host, "outlook.office.com")
        XCTAssertEqual(
            try SubscriptionTarget(destination: .outlook, outlookAccount: .personal).handoffURL(for: feed).host,
            "outlook.live.com")
        XCTAssertThrowsError(
            try SubscriptionTarget(destination: .outlook, outlookAccount: .other, exchangeURL: "http://unsafe.example")
                .handoffURL(for: feed))
        XCTAssertEqual(
            try SubscriptionTarget(
                destination: .outlook, outlookAccount: .other, exchangeURL: "https://mail.example.com/owa"
            ).handoffURL(for: feed).path, "/owa")
    }

    func testIrrelevantProviderOptionsDoNotCreateDuplicateTargets() {
        let first = SubscriptionTarget(
            destination: .apple, outlookAccount: .other, exchangeURL: "https://mail.example.com")
        XCTAssertEqual(first.normalized, SubscriptionTarget().normalized)
        let work = SubscriptionTarget(destination: .outlook, exchangeURL: "https://mail.example.com")
        XCTAssertEqual(work.normalized, SubscriptionTarget(destination: .outlook).normalized)
    }

    func testNewHandoffIsPendingAndPersistsWithoutClaimingSuccess() throws {
        let feed = try XCTUnwrap(CalendarFeed.bundled().first)
        let record = SubscriptionRecord(feed: feed, target: SubscriptionTarget())
        let restored = try JSONDecoder().decode(SubscriptionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.status, .pending)
        XCTAssertNil(restored.confirmedAt)
        XCTAssertEqual(restored.feed, feed)
    }

    func testCatalogHasUniqueIDsAndSecureFeeds() throws {
        let feeds = try CalendarFeed.bundled()
        XCTAssertEqual(feeds.count, 626)
        XCTAssertEqual(Set(feeds.map(\.id)).count, feeds.count)
        let urls = feeds.compactMap(\.feedURL)
        let keys = feeds.compactMap(\.fanCalendarTeamKey)
        XCTAssertEqual(urls.count, 488)
        XCTAssertEqual(Set(urls).count, urls.count)
        XCTAssertEqual(keys.count, 138)
        XCTAssertEqual(Set(keys).count, keys.count)
        for feed in feeds {
            if let url = feed.feedURL {
                XCTAssertNoThrow(try FeedURL.validated(url.absoluteString))
            } else {
                let key = try XCTUnwrap(feed.fanCalendarTeamKey)
                XCTAssertNoThrow(try FanCalendarSubscription.request(teamKey: key))
            }
            XCTAssertEqual(feed.sourceURL.scheme, "https")
            XCTAssertFalse(feed.sourceName.isEmpty)
        }
    }

    func testSearchSupportsAccentsMultipleTermsAndCities() throws {
        let feeds = try CalendarFeed.bundled()
        XCTAssertEqual(feeds.filter { $0.matches("atletico madrid") }.map(\.id), ["atletico-madrid"])
        XCTAssertEqual(feeds.filter { $0.matches("NBA boston") }.map(\.id), ["nba-boston-celtics"])
        XCTAssertTrue(feeds.contains { $0.matches("Santa Clara") })
        XCTAssertTrue(feeds.allSatisfy { $0.matches("  ") })
    }

    func testEveryNFLTeamIsAvailable() throws {
        let expected: Set<String> = [
            "Arizona Cardinals", "Atlanta Falcons", "Baltimore Ravens", "Buffalo Bills",
            "Carolina Panthers", "Chicago Bears", "Cincinnati Bengals", "Cleveland Browns",
            "Dallas Cowboys", "Denver Broncos", "Detroit Lions", "Green Bay Packers",
            "Houston Texans", "Indianapolis Colts", "Jacksonville Jaguars", "Kansas City Chiefs",
            "Las Vegas Raiders", "Los Angeles Chargers", "Los Angeles Rams", "Miami Dolphins",
            "Minnesota Vikings", "New England Patriots", "New Orleans Saints", "New York Giants",
            "New York Jets", "Philadelphia Eagles", "Pittsburgh Steelers", "San Francisco 49ers",
            "Seattle Seahawks", "Tampa Bay Buccaneers", "Tennessee Titans", "Washington Commanders",
        ]
        let teams = try CalendarFeed.bundled().filter { $0.league == "NFL" }
        XCTAssertEqual(Set(teams.map(\.name)), expected)
        XCTAssertTrue(teams.allSatisfy { $0.sport == .americanFootball })
    }

    func testDivisionICollegeFootballIncludesFBSAndFCSWithConferences() throws {
        let college = try CalendarFeed.bundled().filter { $0.id.hasPrefix("ncaaf-") }
        XCTAssertEqual(college.count, 266)
        XCTAssertEqual(college.filter { $0.league.hasPrefix("College FBS ·") }.count, 138)
        XCTAssertEqual(college.filter { $0.league.hasPrefix("College FCS ·") }.count, 128)
        XCTAssertEqual(Set(college.map(\.league)).count, 25)
        XCTAssertEqual(college.first { $0.name == "Alabama Crimson Tide" }?.league, "College FBS · SEC")
        XCTAssertEqual(college.first { $0.name == "Ohio State Buckeyes" }?.league, "College FBS · Big Ten")
        XCTAssertTrue(college.allSatisfy { $0.sport == .americanFootball })
        let fcs = college.filter { $0.league.hasPrefix("College FCS ·") }
        XCTAssertTrue(fcs.allSatisfy { $0.feedURL?.host == "cfbvibes.com" && $0.fanCalendarTeamKey == nil })
        let utrgv = try XCTUnwrap(college.first { $0.id == "ncaaf-292" })
        XCTAssertEqual(utrgv.feedURL?.path, "/teams/utrgv/schedule.ics")
        XCTAssertEqual(utrgv.sourceName, "CFB Vibes")
    }

    func testAllTwelveSoccerLeagueRostersAreAvailable() throws {
        let expected = [
            "Premier League": 20, "La Liga": 20, "Bundesliga": 18,
            "Serie A": 20, "Ligue 1": 18, "Primeira Liga": 18,
            "Eredivisie": 18, "Scottish Premiership": 12, "MLS": 30,
            "Liga MX": 18, "Brasileirão Série A": 20, "Argentina Primera División": 30,
        ]
        let soccer = try CalendarFeed.bundled().filter { $0.sport == .football }
        XCTAssertEqual(Dictionary(grouping: soccer, by: \.league).mapValues(\.count), expected)
        XCTAssertFalse(soccer.contains { $0.name.contains("All-Stars") })
        XCTAssertTrue(soccer.allSatisfy { $0.matches("soccer") && $0.matches("football") })
    }

    func testAllThreeBaseballLeaguesHaveCompleteTeamCoverage() throws {
        let baseball = try CalendarFeed.bundled().filter { $0.sport == .baseball }
        XCTAssertEqual(
            Dictionary(grouping: baseball, by: \.league).mapValues(\.count), ["MLB": 30, "NPB": 12, "KBO": 10])
        XCTAssertEqual(
            Set(baseball.filter { $0.league == "NPB" }.map(\.name)),
            [
                "Yomiuri Giants", "Tokyo Yakult Swallows", "Yokohama DeNA BayStars", "Chunichi Dragons",
                "Hanshin Tigers", "Hiroshima Toyo Carp", "Hokkaido Nippon-Ham Fighters",
                "Tohoku Rakuten Golden Eagles", "Saitama Seibu Lions", "Chiba Lotte Marines",
                "Orix Buffaloes", "Fukuoka SoftBank Hawks",
            ])
        XCTAssertEqual(
            Set(baseball.filter { $0.league == "KBO" }.map(\.name)),
            [
                "Doosan Bears", "Hanwha Eagles", "KIA Tigers", "Kiwoom Heroes", "KT Wiz",
                "LG Twins", "Lotte Giants", "NC Dinos", "Samsung Lions", "SSG Landers",
            ])
        XCTAssertEqual(
            Set(baseball.filter { $0.league == "KBO" }.compactMap { $0.feedURL?.lastPathComponent }),
            ["OB", "HH", "HT", "WO", "KT", "LG", "LT", "NC", "SS", "SK"])
    }

    func testSeasonSpecificFeedsDiscloseTheirLimitsBeforeSubscription() throws {
        let baseball = try CalendarFeed.bundled().filter { ["MLB", "NPB"].contains($0.league) }
        for feed in baseball {
            let year = feed.league == "MLB" ? "2027" : "2026"
            XCTAssertTrue(try XCTUnwrap(feed.feedURL).absoluteString.contains(year))
            XCTAssertTrue(feed.location.contains(year))
            XCTAssertTrue(feed.introduction.contains(year))
            XCTAssertTrue(feed.introduction.contains("new subscription"))
        }
    }

    func testGolfToursIncludeOfficialAndIndependentSources() throws {
        let golf = try CalendarFeed.bundled().filter { $0.sport == .golf }
        XCTAssertEqual(
            Set(golf.map(\.name)),
            [
                "PGA Tour", "PGA Tour Champions", "Korn Ferry Tour",
                "PGA Tour Americas", "LPGA Tour", "DP World Tour", "LIV Golf",
            ])
        XCTAssertEqual(golf.filter { $0.sourceKind == "Official tour calendar" }.count, 4)
        XCTAssertTrue(golf.allSatisfy { $0.introduction.contains("tee times") })
    }

    func testJapaneseAndKoreanBaseballTimesConvertToTheCorrectInstants() throws {
        let data = calendar(
            event("UID:kbo\r\nDTSTART;TZID=Asia/Seoul:20260312T130000\r\nSUMMARY:SSG vs KIA") + "\r\n"
                + event("UID:npb\r\nDTSTART;TZID=Japan:20260327T181500\r\nSUMMARY:G vs T"))
        let preview = try ICalendarParser.parse(data, localTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(preview.skippedEvents, 0)
        XCTAssertEqual(
            preview.events.map(\.start),
            [
                ISO8601DateFormatter().date(from: "2026-03-12T04:00:00Z")!,
                ISO8601DateFormatter().date(from: "2026-03-27T09:15:00Z")!,
            ])
    }

    private func customFeed(url: URL) -> CalendarFeed {
        CalendarFeed(
            id: "test", name: "Test", sport: .custom, league: "Custom", location: "",
            monogram: "T", color: "35877B", feedURL: url, sourceURL: url)
    }

    func testTwitchWeeklyBroadcastKeepsLocalTimeAcrossDST() throws {
        let data = calendar(
            event(
                "UID:critical-role\r\nDTSTART;TZID=/America/Los_Angeles:20260827T190000\r\nDTEND;TZID=/America/Los_Angeles:20260827T230000\r\nRRULE:FREQ=WEEKLY;BYDAY=TH\r\nSUMMARY:Critical Role"
            ))
        let now = ISO8601DateFormatter().date(from: "2026-10-29T00:00:00Z")!
        let preview = try ICalendarParser.parse(data, now: now)
        let next = preview.upcoming(after: now, limit: 2)
        XCTAssertEqual(
            next.map(\.start),
            ["2026-10-30T02:00:00Z", "2026-11-06T03:00:00Z"].map { ISO8601DateFormatter().date(from: $0)! })
        XCTAssertFalse(preview.hasUnexpandedRecurrence)
        XCTAssertEqual(next.first?.end?.timeIntervalSince(next.first!.start), 4 * 3_600)
    }

    func testWeeklyIntervalCountExclusionsAndMovedOccurrences() throws {
        let master = event(
            "UID:show\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TH\r\nEXDATE:20261015T190000Z\r\nEXDATE:20261112T190000Z\r\nSUMMARY:Regular show"
        )
        let moved = event(
            "UID:show\r\nRECURRENCE-ID:20261029T190000Z\r\nDTSTART:20261030T200000Z\r\nSUMMARY:Moved show")
        let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        let preview = try ICalendarParser.parse(calendar(master + "\r\n" + moved), now: now)
        XCTAssertEqual(preview.events.map(\.title), ["Regular show", "Moved show"])
        XCTAssertEqual(preview.events.last?.start, ISO8601DateFormatter().date(from: "2026-10-30T20:00:00Z")!)
    }

    func testCancelledRecurrenceOverrideIsNotRegenerated() throws {
        let master = event("UID:show\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=WEEKLY;COUNT=2")
        let cancelled = event("UID:show\r\nRECURRENCE-ID:20261008T190000Z\r\nSTATUS:CANCELLED")
        let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        XCTAssertEqual(try ICalendarParser.parse(calendar(master + "\r\n" + cancelled), now: now).events.count, 1)
    }

    func testUntilIsInclusiveAndAdditionalDatesAreHonored() throws {
        let data = calendar(
            event(
                "UID:show\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=DAILY;UNTIL=20261003T190000Z\r\nRDATE:20261005T190000Z"
            ))
        let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        XCTAssertEqual(try ICalendarParser.parse(data, now: now).events.count, 4)
    }

    func testUnsupportedRecurrenceIsDisclosedRatherThanGuessed() throws {
        let data = calendar(event("UID:monthly\r\nDTSTART:20261001T190000Z\r\nRRULE:FREQ=MONTHLY;BYDAY=1TH"))
        let preview = try ICalendarParser.parse(data)
        XCTAssertTrue(preview.hasUnexpandedRecurrence)
        XCTAssertEqual(preview.events.count, 1)
    }

    func testLivePlayCatalogDisclosesDropoutCoverageAndRealTwitchEndpoint() throws {
        let feeds = try CalendarFeed.bundled()
        let dropout = try XCTUnwrap(feeds.first { $0.id == "dimension-20-dropout" })
        XCTAssertTrue(dropout.introduction.contains("whole service"))
        XCTAssertEqual(dropout.sourceKind, "Community-maintained")
        let criticalRole = try XCTUnwrap(feeds.first { $0.id == "critical-role" })
        XCTAssertEqual(criticalRole.feedURL?.host, "api.twitch.tv")
        XCTAssertEqual(criticalRole.feedURL?.path, "/helix/schedule/icalendar")
        XCTAssertTrue(criticalRole.matches("Critical Role"))
    }
}
