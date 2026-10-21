import CalendarCore
import Foundation
import Observation

enum LibrarySection: String, Identifiable, CaseIterable {
    case discover, favorites, selected, subscriptions, football, basketball, americanFootball, baseball, golf,
        motorsport
    case tennis, combatSports, esports, actualPlay, space, custom
    var id: String { rawValue }
    var sport: Sport? { Sport(rawValue: rawValue) }
    var title: String {
        switch self {
        case .discover: "Discover"
        case .favorites: "Favorites"
        case .selected: "Selected calendars"
        case .subscriptions: "My subscriptions"
        default: sport?.title ?? "Calendars"
        }
    }
    var symbol: String {
        switch self {
        case .discover: "square.grid.2x2"
        case .favorites: "star"
        case .selected: "checkmark.circle"
        case .subscriptions: "calendar.badge.checkmark"
        default: sport?.symbol ?? "calendar"
        }
    }
}

@MainActor @Observable
final class AppStore {
    var catalog: [CalendarFeed] = []
    var customFeeds: [CalendarFeed] = []
    var selectedIDs: Set<String> = []
    var favoriteIDs: Set<String> = []
    var records: [SubscriptionRecord] = []
    var section: LibrarySection? = .discover {
        didSet {
            if oldValue != section {
                leagueFilter = nil
                subscriptionFilter = nil
            }
        }
    }
    var leagueFilter: String?
    var subscriptionFilter: SubscriptionStatus?
    var focusedID: String?
    var searchText = ""
    var showingReview = false
    private(set) var reviewQueue: [CalendarFeed] = []
    private(set) var reviewTarget = SubscriptionTarget()
    var showingCustomFeed = false
    var errorMessage: String?
    var target = SubscriptionTarget()
    var refreshToken = UUID()
    let client = FeedClient()
    private let libraryFile: LibraryFile
    private var canSave = true
    private var resolvedURLs: [String: URL] = [:]

    init(stateURL: URL? = nil, catalog suppliedCatalog: [CalendarFeed]? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        libraryFile = LibraryFile(
            url: stateURL
                ?? support.appendingPathComponent("TeamCalendar", isDirectory: true).appendingPathComponent(
                    "library.json"))
        do { catalog = try suppliedCatalog ?? CalendarFeed.bundled() } catch {
            errorMessage = "The calendar catalog couldn’t be loaded. \(error.localizedDescription)"
        }
        do {
            if let state = try libraryFile.load() {
                customFeeds = state.customFeeds
                records = state.records
                let knownIDs = Set(libraryFeeds.map(\.id))
                selectedIDs = state.selectedIDs.intersection(knownIDs)
                favoriteIDs = (state.favoriteIDs ?? []).intersection(knownIDs)
                target = state.target
                resolvedURLs = state.resolvedURLs ?? [:]
            }
        } catch {
            // Preserve an unreadable library instead of silently overwriting it.
            canSave = false
            errorMessage =
                "Your saved library couldn’t be read and has been left untouched at \(libraryFile.url.path). Changes won’t be saved until it is repaired or moved."
        }
        focusedID = catalog.first?.id
    }

    var allFeeds: [CalendarFeed] { catalog + customFeeds }
    private var libraryFeeds: [CalendarFeed] {
        var seen = Set<String>()
        return (allFeeds + records.map(\.feed)).filter { seen.insert($0.id).inserted }
    }
    var selectedFeeds: [CalendarFeed] { libraryFeeds.filter { selectedIDs.contains($0.id) } }
    var isPresentingSheet: Bool { showingReview || showingCustomFeed }
    var subscriptionCalendarCount: Int { Set(records.map { $0.feed.id }).count }
    var focusedFeed: CalendarFeed? {
        sectionFeeds.first { $0.id == focusedID } ?? libraryFeeds.first { $0.id == focusedID }
    }
    private var sectionFeeds: [CalendarFeed] {
        let candidates: [CalendarFeed]
        if section == .subscriptions {
            var seen = Set<String>()
            candidates = records.map { record in
                allFeeds.first { $0.id == record.feed.id } ?? record.feed
            }.filter { seen.insert($0.id).inserted }
        } else if section == .selected || section == .favorites {
            candidates = libraryFeeds
        } else {
            candidates = allFeeds
        }
        return candidates.filter { feed in
            let included: Bool
            switch section ?? .discover {
            case .favorites: included = favoriteIDs.contains(feed.id)
            case .selected: included = selectedIDs.contains(feed.id)
            case .subscriptions: included = records.contains { $0.feed.id == feed.id }
            case .discover: included = true
            default: included = feed.sport == section?.sport
            }
            return included
        }
    }

    var availableLeagues: [String] {
        Set(sectionFeeds.map(\.league)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var visibleFeeds: [CalendarFeed] {
        sectionFeeds.filter { feed in
            guard (leagueFilter == nil || feed.league == leagueFilter) && feed.matches(searchText) else { return false }
            guard section == .subscriptions, let subscriptionFilter else { return true }
            let matching = historyRecords(for: feed)
            switch subscriptionFilter {
            case .pending: return matching.contains { $0.status == .pending }
            case .confirmed: return !matching.isEmpty && matching.allSatisfy { $0.status == .confirmed }
            }
        }
    }

    var visibleSelectedCount: Int { visibleFeeds.filter { selectedIDs.contains($0.id) }.count }

    func selectVisible() {
        selectedIDs.formUnion(visibleFeeds.map(\.id))
        save()
    }

    func deselectVisible() {
        let visibleIDs = Set(visibleFeeds.map(\.id))
        selectedIDs.subtract(visibleIDs)
        save()
    }

    func toggleFavorite(_ feed: CalendarFeed) {
        if !favoriteIDs.insert(feed.id).inserted { favoriteIDs.remove(feed.id) }
        save()
    }

    func toggleSelection(_ feed: CalendarFeed) {
        if !selectedIDs.insert(feed.id).inserted { selectedIDs.remove(feed.id) }
        save()
    }

    func clearSelection() {
        selectedIDs.removeAll()
        save()
    }

    func beginReview(_ feeds: [CalendarFeed]? = nil) {
        guard !isPresentingSheet else { return }
        let queue = feeds ?? selectedFeeds
        guard !queue.isEmpty else { return }
        reviewQueue = queue
        reviewTarget = target
        showingReview = true
    }

    func beginCustomFeed() {
        guard !isPresentingSheet else { return }
        showingCustomFeed = true
    }

    func resume(record: SubscriptionRecord) {
        guard !isPresentingSheet, record.status == .pending else { return }
        reviewQueue = [record.feed]
        reviewTarget = record.target
        showingReview = true
    }

    func showSubscriptions(focusing id: String?) {
        section = .subscriptions
        searchText = ""
        leagueFilter = nil
        subscriptionFilter = nil
        focusedID = id
    }

    func addCustomFeed(name: String, url: URL) {
        searchText = ""
        leagueFilter = nil
        if let existing = libraryFeeds.first(where: { cachedFeed($0).feedURL == url }) {
            if existing.sport == .custom && !customFeeds.contains(where: { $0.id == existing.id }) {
                customFeeds.append(existing)
                save()
            }
            section = existing.sport == .custom ? .custom : .discover
            focusedID = existing.id
            return
        }
        let feed = CalendarFeed(
            id: "custom-\(UUID().uuidString)", name: name,
            sport: .custom, league: "Custom feed", location: url.host ?? "",
            monogram: String(name.prefix(2)).uppercased(), color: "35877B",
            feedURL: url, sourceURL: url)
        customFeeds.append(feed)
        section = .custom
        focusedID = feed.id
        save()
    }

    func removeCustomFeed(_ feed: CalendarFeed) {
        customFeeds.removeAll { $0.id == feed.id }
        selectedIDs.remove(feed.id)
        favoriteIDs.remove(feed.id)
        resolvedURLs.removeValue(forKey: feed.id)
        if focusedID == feed.id { focusedID = visibleFeeds.first?.id }
        save()
    }

    func record(for feed: CalendarFeed, target: SubscriptionTarget) -> SubscriptionRecord? {
        records(for: feed).first { $0.target.normalized == target.normalized }
    }

    func records(for feed: CalendarFeed) -> [SubscriptionRecord] {
        let candidate = cachedFeed(feed)
        return records.filter { $0.feed.isSameSubscription(as: candidate) }
    }

    /// History groups all URL versions of a catalog entry. Confirmation still requires
    /// the exact subscription identity through records(for:), never this broader match.
    func historyRecords(for feed: CalendarFeed) -> [SubscriptionRecord] {
        let candidate = cachedFeed(feed)
        return records.filter { $0.feed.id == feed.id || $0.feed.isSameSubscription(as: candidate) }
    }

    func cachedFeed(_ feed: CalendarFeed) -> CalendarFeed {
        guard feed.feedURL == nil, let url = resolvedURLs[feed.id] else { return feed }
        return feed.resolved(with: url)
    }

    func resolveFeed(_ feed: CalendarFeed) async throws -> CalendarFeed {
        let resolved = try await client.resolve(feed, cachedURL: resolvedURLs[feed.id])
        if feed.feedURL == nil, let url = resolved.feedURL, resolvedURLs[feed.id] != url {
            resolvedURLs[feed.id] = url
            save()
        }
        return resolved
    }

    func recordHandoff(_ feed: CalendarFeed, target: SubscriptionTarget) {
        guard feed.feedURL != nil else { return }
        if record(for: feed, target: target) == nil {
            records.append(SubscriptionRecord(feed: feed, target: target.normalized))
        }
        save()
    }

    func confirm(_ feed: CalendarFeed, target: SubscriptionTarget) {
        guard let record = record(for: feed, target: target),
            let index = records.firstIndex(where: { $0.id == record.id })
        else { return }
        records[index].status = .confirmed
        records[index].confirmedAt = .now
        selectedIDs.remove(feed.id)
        save()
    }

    func removeRecord(_ record: SubscriptionRecord) {
        records.removeAll { $0.id == record.id }
        let knownIDs = Set(libraryFeeds.map(\.id))
        selectedIDs.formIntersection(knownIDs)
        favoriteIDs.formIntersection(knownIDs)
        save()
    }

    func save() {
        guard canSave else { return }
        do {
            let state = LibrarySnapshot(
                customFeeds: customFeeds, selectedIDs: selectedIDs, records: records,
                target: target, resolvedURLs: resolvedURLs, favoriteIDs: favoriteIDs)
            try libraryFile.save(state)
        } catch {
            errorMessage = "Your changes couldn’t be saved. \(error.localizedDescription)"
        }
    }
}
