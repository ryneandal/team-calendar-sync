import CalendarCore
import XCTest

@testable import TeamCalendar

@MainActor
final class AppStoreTests: XCTestCase {
    private func withLibrary(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("library.json"))
    }

    private func feed(
        _ id: String, sport: Sport = .football, league: String = "League A",
        url: String? = nil
    ) -> CalendarFeed {
        CalendarFeed(
            id: id, name: id, sport: sport, league: league, location: "Test",
            monogram: id, color: "35877B", feedURL: URL(string: url ?? "https://example.com/\(id).ics")!,
            sourceURL: URL(string: "https://example.com")!)
    }

    func testReviewQueueAndTargetRemainStableDuringReentry() throws {
        try withLibrary { url in
            let feeds = [feed("A"), feed("B"), feed("C")]
            let store = AppStore(stateURL: url, catalog: feeds)
            store.selectedIDs = Set(feeds.map(\.id))
            store.beginReview()
            store.selectedIDs.remove("A")
            store.target = SubscriptionTarget(destination: .google)
            store.beginReview([feeds[2]])
            store.beginCustomFeed()
            XCTAssertEqual(store.reviewQueue, feeds)
            XCTAssertEqual(store.reviewTarget.destination, .apple)
            XCTAssertFalse(store.showingCustomFeed)

            store.showingReview = false
            store.beginCustomFeed()
            store.beginReview([feeds[2]])
            XCTAssertFalse(store.showingReview)
            XCTAssertTrue(store.showingCustomFeed)
        }
    }

    func testHandoffRequiresExplicitConfirmationAndPreservesFavorites() throws {
        try withLibrary { url in
            let team = feed("A")
            let store = AppStore(stateURL: url, catalog: [team])
            let target = SubscriptionTarget(destination: .google)
            store.toggleSelection(team)
            store.toggleFavorite(team)
            store.confirm(team, target: target)
            XCTAssertTrue(store.records.isEmpty)
            XCTAssertTrue(store.selectedIDs.contains(team.id))
            store.recordHandoff(team, target: target)
            store.recordHandoff(team, target: target)
            XCTAssertEqual(store.records.count, 1)
            XCTAssertEqual(store.records.first?.status, .pending)
            XCTAssertNil(store.records.first?.confirmedAt)
            store.confirm(team, target: target)
            XCTAssertEqual(store.records.first?.status, .confirmed)
            XCTAssertNotNil(store.records.first?.confirmedAt)
            XCTAssertTrue(store.selectedIDs.isEmpty)
            XCTAssertEqual(store.favoriteIDs, [team.id])
        }
    }

    func testRemovedCustomSourceCanBeSelectedFromHistoryAndRestored() throws {
        try withLibrary { url in
            let store = AppStore(stateURL: url, catalog: [])
            let source = URL(string: "https://example.com/custom.ics")!
            store.addCustomFeed(name: "Custom", url: source)
            let custom = try XCTUnwrap(store.customFeeds.first)
            store.recordHandoff(custom, target: SubscriptionTarget())
            store.removeCustomFeed(custom)
            store.section = .subscriptions
            store.toggleSelection(custom)
            store.beginReview()
            XCTAssertEqual(store.reviewQueue.map(\.id), [custom.id])

            let reloaded = AppStore(stateURL: url, catalog: [])
            XCTAssertEqual(reloaded.selectedFeeds.map(\.id), [custom.id])
            reloaded.addCustomFeed(name: "A new name", url: source)
            XCTAssertEqual(reloaded.customFeeds.map(\.id), [custom.id])
            XCTAssertEqual(reloaded.records(for: custom).count, 1)
            XCTAssertEqual(reloaded.record(for: custom, target: SubscriptionTarget())?.status, .pending)
        }
    }

    func testVisibleSelectionRespectsCategoryLeagueAndSearch() throws {
        try withLibrary { url in
            let feeds = [
                feed("Alpha"), feed("Beta"), feed("Gamma", league: "League B"),
                feed("Delta", sport: .baseball),
            ]
            let store = AppStore(stateURL: url, catalog: feeds)
            store.selectedIDs = ["Delta"]
            store.section = .football
            store.leagueFilter = "League A"
            store.searchText = "Alpha"
            store.selectVisible()
            XCTAssertEqual(store.selectedIDs, ["Alpha", "Delta"])
            XCTAssertEqual(store.visibleSelectedCount, 1)
            store.searchText = ""
            store.selectVisible()
            XCTAssertEqual(store.selectedIDs, ["Alpha", "Beta", "Delta"])
            store.deselectVisible()
            XCTAssertEqual(store.selectedIDs, ["Delta"])

            store.selectVisible()
            store.section = .selected
            store.deselectVisible()
            XCTAssertTrue(store.selectedIDs.isEmpty)
        }
    }

    func testFavoritesPersistIndependentlyOfSelection() throws {
        try withLibrary { url in
            let team = feed("A")
            let store = AppStore(stateURL: url, catalog: [team])
            store.toggleFavorite(team)
            store.toggleSelection(team)
            store.clearSelection()
            let reloaded = AppStore(stateURL: url, catalog: [team])
            reloaded.section = .favorites
            XCTAssertEqual(reloaded.visibleFeeds.map(\.id), [team.id])
            XCTAssertTrue(reloaded.selectedIDs.isEmpty)
            reloaded.toggleFavorite(team)
            XCTAssertTrue(reloaded.visibleFeeds.isEmpty)
        }
    }

    func testPendingStatusWinsAcrossDestinationsAndResumeKeepsExactTarget() throws {
        try withLibrary { url in
            let team = feed("A")
            let store = AppStore(stateURL: url, catalog: [team])
            let apple = SubscriptionTarget()
            let exchange = SubscriptionTarget(
                destination: .outlook, outlookAccount: .other,
                exchangeURL: "https://mail.example.com/calendar/")
            store.recordHandoff(team, target: apple)
            store.confirm(team, target: apple)
            store.recordHandoff(team, target: exchange)
            XCTAssertEqual(store.subscriptionCalendarCount, 1)
            store.section = .subscriptions
            store.subscriptionFilter = .pending
            XCTAssertEqual(store.visibleFeeds.count, 1)
            store.subscriptionFilter = .confirmed
            XCTAssertTrue(store.visibleFeeds.isEmpty)
            let pending = try XCTUnwrap(store.record(for: team, target: exchange))
            store.resume(record: pending)
            XCTAssertEqual(store.reviewTarget, exchange)
            XCTAssertEqual(store.target, apple)
            XCTAssertEqual(store.reviewQueue, [team])
            store.confirm(team, target: exchange)
            XCTAssertEqual(store.visibleFeeds.count, 1)
            store.showingReview = false
            store.resume(record: try XCTUnwrap(store.record(for: team, target: exchange)))
            XCTAssertFalse(store.showingReview)
        }
    }

    func testLegacyLibraryLoadsWithoutOptionalFieldsAndPrunesUnknownIDs() throws {
        try withLibrary { url in
            let team = feed("A")
            let snapshot = LibrarySnapshot(
                customFeeds: [], selectedIDs: [team.id, "missing"], records: [],
                target: SubscriptionTarget())
            var json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
            json.removeValue(forKey: "favoriteIDs")
            json.removeValue(forKey: "resolvedURLs")
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let store = AppStore(stateURL: url, catalog: [team])
            XCTAssertNil(store.errorMessage)
            XCTAssertEqual(store.selectedIDs, [team.id])
            XCTAssertTrue(store.favoriteIDs.isEmpty)
        }
    }

    func testUnreadableAndFutureLibrariesAreNeverOverwritten() throws {
        for original in [
            Data("not JSON".utf8),
            Data(
                #"{"version":99,"customFeeds":[],"selectedIDs":[],"records":[],"target":{"destination":"apple","outlookAccount":"work","exchangeURL":""}}"#
                    .utf8),
        ] {
            try withLibrary { url in
                try original.write(to: url)
                let team = feed("A")
                let store = AppStore(stateURL: url, catalog: [team])
                XCTAssertNotNil(store.errorMessage)
                store.toggleFavorite(team)
                store.toggleSelection(team)
                XCTAssertEqual(try Data(contentsOf: url), original)
            }
        }
    }

    func testRecordsMatchSubscriptionURLsRatherThanReusedCatalogIDs() throws {
        try withLibrary { url in
            let old = feed("A")
            let restored = feed("new-id", url: old.feedURL!.absoluteString)
            let newSeason = feed("A", url: "https://example.com/new-season.ics")
            let store = AppStore(stateURL: url, catalog: [newSeason])
            store.recordHandoff(old, target: SubscriptionTarget())
            XCTAssertEqual(store.records(for: restored).count, 1)
            XCTAssertTrue(store.records(for: newSeason).isEmpty)

            store.confirm(old, target: SubscriptionTarget())
            let google = SubscriptionTarget(destination: .google)
            store.recordHandoff(newSeason, target: google)
            store.section = .subscriptions
            store.subscriptionFilter = .pending
            XCTAssertEqual(store.visibleFeeds, [newSeason])
            XCTAssertEqual(store.historyRecords(for: newSeason).count, 2)
            XCTAssertEqual(store.records(for: newSeason).first?.status, .pending)
            XCTAssertNil(store.record(for: newSeason, target: SubscriptionTarget()))
            store.resume(record: try XCTUnwrap(store.record(for: newSeason, target: google)))
            XCTAssertEqual(store.reviewQueue, [newSeason])
        }
    }

    func testViewingCompletedSubscriptionsClearsExistingFilters() throws {
        try withLibrary { url in
            let team = feed("A")
            let store = AppStore(stateURL: url, catalog: [team])
            store.recordHandoff(team, target: SubscriptionTarget())
            store.section = .subscriptions
            store.subscriptionFilter = .pending
            store.leagueFilter = "Another league"
            store.searchText = "Something else"
            store.confirm(team, target: SubscriptionTarget())
            store.showSubscriptions(focusing: team.id)
            XCTAssertEqual(store.visibleFeeds, [team])
            XCTAssertEqual(store.focusedID, team.id)
            XCTAssertNil(store.subscriptionFilter)
            XCTAssertNil(store.leagueFilter)
            XCTAssertEqual(store.searchText, "")
        }
    }
}
