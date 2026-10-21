import XCTest

@testable import CalendarCore

@MainActor
final class FanCalendarTests: XCTestCase {
    private let subscriptionURL = URL(string: "https://fancalendar.app/api/subscription/8083aecd89852861.ics")!

    private func college(_ key: String = "ALA") -> CalendarFeed {
        CalendarFeed(
            id: "college-\(key)", name: key, sport: .americanFootball,
            league: "College FBS · SEC", location: "USA", monogram: key,
            color: "940000", feedURL: nil, sourceURL: URL(string: "https://www.fancalendar.app/")!,
            provider: "FanCalendar / ESPN", coverage: "Upcoming games", fanCalendarTeamKey: key)
    }

    private func client(
        status: Int = 200, data: Data? = nil, headers: [String: String] = [:],
        now: @escaping @Sendable () -> Date = { .now }
    ) -> FeedClient {
        StubProtocol.state.configure(
            status: status,
            data: data
                ?? Data(
                    #"{"subscriptionUrl":"https://fancalendar.app/api/subscription/8083aecd89852861.ics"}"#.utf8),
            headers: headers)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return FeedClient(session: URLSession(configuration: configuration), now: now)
    }

    func testRequestContainsOnlyTheSelectedPublicTeamAndNoAlarms() throws {
        let request = try FanCalendarSubscription.request(teamKey: "ALA")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://www.fancalendar.app/api/subscription/create")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["teamKeys", "sports", "alarms", "includeAllGames", "includeSessions"])
        XCTAssertEqual(object["teamKeys"] as? [String], ["ALA"])
        XCTAssertEqual(object["sports"] as? [String], ["cfb"])
        XCTAssertEqual(object["alarms"] as? [String: Int], ["cfb-ALA": 0])
        XCTAssertEqual(object["includeAllGames"] as? Bool, false)
        XCTAssertEqual(object["includeSessions"] as? Bool, false)
        let texas = try FanCalendarSubscription.request(teamKey: "TA&M")
        let texasBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(texas.httpBody)) as? [String: Any])
        XCTAssertEqual(texasBody["teamKeys"] as? [String], ["TA&M"])
        for invalid in ["", "ALA,OSU", "../ALA", "Alabama", String(repeating: "A", count: 17)] {
            XCTAssertThrowsError(try FanCalendarSubscription.request(teamKey: invalid))
        }
    }

    func testResponseMustContainAnExpectedPublicSubscriptionURL() throws {
        XCTAssertEqual(
            try FanCalendarSubscription.subscriptionURL(
                from: Data(
                    #"{"subscriptionUrl":"https://fancalendar.app/api/subscription/8083aecd89852861.ics"}"#.utf8)),
            subscriptionURL)
        let invalid = [
            "https://example.com/api/subscription/8083aecd89852861.ics",
            "http://fancalendar.app/api/subscription/8083aecd89852861.ics",
            "https://fancalendar.app/account", "https://localhost/feed.ics",
            subscriptionURL.absoluteString + "?email=someone", subscriptionURL.absoluteString + "#fragment",
        ]
        for input in invalid {
            let data = try JSONSerialization.data(withJSONObject: ["subscriptionUrl": input])
            XCTAssertThrowsError(try FanCalendarSubscription.subscriptionURL(from: data), input)
        }
        XCTAssertThrowsError(try FanCalendarSubscription.subscriptionURL(from: Data("{}".utf8)))
    }

    func testUnresolvedTeamCannotOpenAnyDestination() throws {
        let team = college()
        for destination in CalendarDestination.allCases {
            XCTAssertThrowsError(try SubscriptionTarget(destination: destination).handoffURL(for: team)) {
                XCTAssertEqual($0 as? FeedError, .unresolvedSubscription)
            }
        }
        let resolved = team.resolved(with: subscriptionURL)
        XCTAssertEqual(resolved.id, team.id)
        XCTAssertEqual(resolved.introduction, team.introduction)
        XCTAssertEqual(resolved.fanCalendarTeamKey, team.fanCalendarTeamKey)
        XCTAssertEqual(try SubscriptionTarget().handoffURL(for: resolved).scheme, "webcal")
        let google = try SubscriptionTarget(destination: .google).handoffURL(for: resolved)
        XCTAssertEqual(
            URLComponents(url: google, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
            "webcal://fancalendar.app/api/subscription/8083aecd89852861.ics")
        XCTAssertEqual(try JSONDecoder().decode(CalendarFeed.self, from: JSONEncoder().encode(resolved)), resolved)
    }

    func testConcurrentResolutionAndRepeatedPreviewsReuseOneLink() async throws {
        let client = client()
        let team = college()
        async let first = client.resolve(team)
        async let second = client.resolve(team)
        async let third = client.resolve(team)
        let resolved = try await [first, second, third]
        XCTAssertTrue(resolved.allSatisfy { $0.feedURL == subscriptionURL })
        let again = try await client.resolve(team)
        XCTAssertEqual(again.feedURL, subscriptionURL)
        XCTAssertEqual(StubProtocol.state.requestCount, 1)
    }

    func testPersistedLinkWorksWithoutRequestingAnotherSubscription() async throws {
        let client = client(status: 500)
        let resolved = try await client.resolve(college(), cachedURL: subscriptionURL)
        XCTAssertEqual(resolved.feedURL, subscriptionURL)
        XCTAssertEqual(StubProtocol.state.requestCount, 0)
        do {
            _ = try await client.resolve(college(), cachedURL: URL(string: "https://unrelated.example/feed.ics")!)
            XCTFail("Untrusted persisted URLs must be rejected")
        } catch { XCTAssertEqual(error as? FeedError, .invalidURL) }
        XCTAssertEqual(StubProtocol.state.requestCount, 0)
    }

    func testRateLimitStopsFurtherProviderRequestsUntilRetryTime() async throws {
        let client = client(status: 429, data: Data(), headers: ["Retry-After": "60"])
        var firstRetry: Date?
        for key in ["ALA", "OSU"] {
            do {
                _ = try await client.resolve(college(key))
                XCTFail("Rate-limited resolution must fail")
            } catch FeedError.rateLimited(let retryAt) {
                if let firstRetry { XCTAssertEqual(retryAt, firstRetry) } else { firstRetry = retryAt }
                XCTAssertTrue((55...65).contains(retryAt.timeIntervalSinceNow))
            }
        }
        XCTAssertEqual(StubProtocol.state.requestCount, 1)

        // Other providers must remain usable during FanCalendar's cooldown.
        StubProtocol.state.configure(
            status: 200, data: Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n".utf8))
        let preview = try await client.preview(for: URL(string: "https://example.com/feed.ics")!)
        XCTAssertTrue(preview.events.isEmpty)
        XCTAssertEqual(StubProtocol.state.requestCount, 1)
    }

    func testHTTPDateRetryAfterHonorsTheFullProviderCooldown() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z"))
        let client = client(
            status: 429, data: Data(), headers: ["Retry-After": "Wed, 21 Oct 2026 13:00:00 GMT"], now: { now })
        for key in ["ALA", "OSU"] {
            do {
                _ = try await client.resolve(college(key))
                XCTFail("Rate-limited resolution must fail")
            } catch FeedError.rateLimited(let retryAt) {
                XCTAssertEqual(retryAt, now.addingTimeInterval(3_600))
            }
        }
        XCTAssertEqual(StubProtocol.state.requestCount, 1)
    }

    func testInvalidAndPastRetryAfterHeadersHaveSafeFallbacks() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z"))
        for (header, delay) in [
            ("invalid", 900.0), ("-60", 900.0), ("nan", 900.0),
            ("Wed, 21 Oct 2026 11:00:00 GMT", 1.0), ("0", 1.0),
        ] {
            let client = client(status: 429, data: Data(), headers: ["Retry-After": header], now: { now })
            do {
                _ = try await client.resolve(college())
                XCTFail("Rate-limited resolution must fail")
            } catch FeedError.rateLimited(let retryAt) {
                XCTAssertEqual(retryAt, now.addingTimeInterval(delay), header)
            }
        }
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, headers) = Self.state.respond()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var status = 200
    private var data = Data()
    private var headers: [String: String] = [:]

    var requestCount: Int { lock.withLock { count } }

    func configure(status: Int, data: Data, headers: [String: String] = [:]) {
        lock.withLock {
            self.status = status
            self.data = data
            self.headers = headers
            count = 0
        }
    }

    func respond() -> (Int, Data, [String: String]) {
        lock.withLock {
            count += 1
            return (status, data, headers)
        }
    }
}
