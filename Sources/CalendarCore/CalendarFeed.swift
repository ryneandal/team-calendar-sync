import Foundation

public enum Sport: String, Codable, CaseIterable, Identifiable, Sendable {
    case football, basketball, americanFootball, baseball, golf, motorsport, tennis, combatSports, esports, actualPlay,
        space, custom

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .football: "Soccer"
        case .basketball: "Basketball"
        case .americanFootball: "American football"
        case .baseball: "Baseball"
        case .golf: "Golf"
        case .motorsport: "Motorsport"
        case .tennis: "Tennis"
        case .combatSports: "Combat sports"
        case .esports: "Esports"
        case .actualPlay: "Actual play & shows"
        case .space: "Space launches"
        case .custom: "Custom calendars"
        }
    }
    public var symbol: String {
        switch self {
        case .football: "soccerball"
        case .basketball: "basketball"
        case .americanFootball: "american.football"
        case .baseball: "baseball"
        case .golf: "figure.golf"
        case .motorsport: "flag.checkered"
        case .tennis: "tennisball"
        case .combatSports: "figure.boxing"
        case .esports: "gamecontroller"
        case .actualPlay: "dice"
        case .space: "sparkles"
        case .custom: "link"
        }
    }
}

public struct CalendarFeed: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sport: Sport
    public let league: String
    public let location: String
    public let monogram: String
    public let color: String
    public let feedURL: URL?
    public let fanCalendarTeamKey: String?
    public let sourceURL: URL
    public let provider: String?
    public let coverage: String?
    public let provenance: String?

    public init(
        id: String, name: String, sport: Sport, league: String, location: String,
        monogram: String, color: String, feedURL: URL?, sourceURL: URL,
        provider: String? = nil, coverage: String? = nil, provenance: String? = nil,
        fanCalendarTeamKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.league = league
        self.location = location
        self.monogram = monogram
        self.color = color
        self.feedURL = feedURL
        self.fanCalendarTeamKey = fanCalendarTeamKey
        self.sourceURL = sourceURL
        self.provider = provider
        self.coverage = coverage
        self.provenance = provenance
    }

    public func resolved(with url: URL) -> CalendarFeed {
        CalendarFeed(
            id: id, name: name, sport: sport, league: league, location: location,
            monogram: monogram, color: color, feedURL: url, sourceURL: sourceURL,
            provider: provider, coverage: coverage, provenance: provenance,
            fanCalendarTeamKey: fanCalendarTeamKey)
    }

    public var sourceName: String { provider ?? (sport == .custom ? (feedURL?.host ?? "Custom source") : "Fixtur.es") }
    public var sourceKind: String { provenance ?? (sport == .custom ? "Custom feed" : "Independent provider") }
    public var introduction: String {
        if let coverage { return coverage }
        switch sport {
        case .actualPlay: return "Make time for the next episode, premiere, or adventure."
        case .space: return "Watch the next mission leave Earth. Launch times can change at short notice."
        case .esports: return "Follow the next match, series, and tournament in your calendar."
        case .tennis: return "Follow the tournament calendar throughout the season."
        case .golf: return "Make room for the next tournament, from opening round to final putt."
        case .combatSports: return "Upcoming fight cards, right where you plan your week."
        case .custom: return "The events you follow, alongside the plans you make."
        case .motorsport: return "Every race weekend, right where you plan your week."
        default: return "A place in your calendar for every game."
        }
    }

    public func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let searchable = "\(name) \(league) \(location) \(sport.title) \(sport.rawValue) \(monogram) \(coverage ?? "")"
        return terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
    }

    public static func bundled() throws -> [CalendarFeed] {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw FeedError.invalidCalendar
        }
        return try JSONDecoder().decode([CalendarFeed].self, from: Data(contentsOf: url))
    }
}

public enum FeedError: LocalizedError, Equatable {
    case invalidURL, insecureRedirect
    case badResponse(Int)
    case tooLarge, invalidCalendar, invalidEncoding
    case unresolvedSubscription
    case rateLimited(until: Date)

    public var errorDescription: String? {
        switch self {
        case .unresolvedSubscription:
            "The subscription link isn’t ready. Load the preview or try the approval step again."
        case .rateLimited(let until):
            "This provider is temporarily limiting requests. Try again after \(until.formatted(date: .omitted, time: .shortened)). Your selection is saved."
        case .invalidURL: "Enter a public HTTPS or webcal calendar URL, without a username or password."
        case .insecureRedirect: "This feed redirected to an address that isn’t a public HTTPS URL."
        case .badResponse(let code): "The calendar provider returned HTTP \(code). Try again later."
        case .tooLarge: "This calendar is too large to preview (the limit is 5 MB). You can still open its source."
        case .invalidCalendar:
            "This address didn’t return a valid iCalendar feed. Check that it links to the calendar itself."
        case .invalidEncoding: "The calendar’s text encoding couldn’t be read."
        }
    }
}

public enum FeedURL {
    public static func validated(_ input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw FeedError.invalidURL
        }
        if parts.scheme?.lowercased() == "webcal" { parts.scheme = "https" }
        guard parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
            let host = parts.host?.lowercased(), isPublicHost(host), parts.port == nil || parts.port == 443,
            let url = parts.url
        else { throw FeedError.invalidURL }
        parts.fragment = nil
        return parts.url ?? url
    }

    private static func isPublicHost(_ host: String) -> Bool {
        guard host.contains("."), !host.hasSuffix("."), !host.hasSuffix(".local"),
            !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
            !host.contains(":"), !host.contains("["), host != "localhost"
        else { return false }
        // Public feeds use DNS names; reject literal IP addresses, including private networks.
        return !host.allSatisfy { $0.isNumber || $0 == "." }
    }

    public static func webcal(_ url: URL) throws -> URL {
        let secure = try validated(url.absoluteString)
        guard var parts = URLComponents(url: secure, resolvingAgainstBaseURL: false) else {
            throw FeedError.invalidURL
        }
        parts.scheme = "webcal"
        guard let result = parts.url else { throw FeedError.invalidURL }
        return result
    }
}
