import XCTest

@testable import CalendarCore

final class SystemCalendarTests: XCTestCase {
    func testSystemDestinationPreservesThePublicSubscriptionURL() throws {
        let feed = CalendarFeed(
            id: "test", name: "Schedule", sport: .custom, league: "Test", location: "",
            monogram: "S", color: "35877B",
            feedURL: URL(string: "https://example.com/events.ics?team=A%26B"),
            sourceURL: URL(string: "https://example.com")!)
        let target = SubscriptionTarget(destination: .system)
        XCTAssertEqual(
            try target.handoffURL(for: feed).absoluteString,
            "webcal://example.com/events.ics?team=A%26B")
        XCTAssertEqual(try JSONDecoder().decode(SubscriptionTarget.self, from: JSONEncoder().encode(target)), target)
    }

    func testPlatformDefaultIsAvailableAndLegacyAppleTargetsStillDecode() throws {
        XCTAssertTrue(CalendarDestination.available.contains(.preferred))
        #if os(iOS)
            XCTAssertEqual(CalendarDestination.preferred, .system)
            XCTAssertFalse(CalendarDestination.available.contains(.apple))
        #else
            XCTAssertEqual(CalendarDestination.preferred, .apple)
        #endif
        let oldTarget = Data(#"{"destination":"apple","outlookAccount":"work","exchangeURL":""}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SubscriptionTarget.self, from: oldTarget).destination, .apple)
    }
}
