import Foundation

extension CalendarFeed {
    /// Resolved URLs identify a subscription, even when a removed source is re-added.
    /// A stable team key bridges a college feed before and after its URL is resolved.
    public func isSameSubscription(as other: CalendarFeed) -> Bool {
        if let feedURL, let otherURL = other.feedURL {
            guard let left = try? FeedURL.validated(feedURL.absoluteString),
                let right = try? FeedURL.validated(otherURL.absoluteString)
            else { return false }
            return left == right
        }
        return id == other.id && fanCalendarTeamKey != nil && fanCalendarTeamKey == other.fanCalendarTeamKey
    }
}

public enum CalendarDestination: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, google, outlook
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .apple: "Apple Calendar"
        case .google: "Google Calendar"
        case .outlook: "Outlook & Exchange"
        }
    }
    public var subtitle: String {
        switch self {
        case .apple: "iCloud or On My Mac"
        case .google: "Your Google account"
        case .outlook: "Microsoft 365, Outlook.com, or Exchange"
        }
    }
    public var symbol: String {
        switch self {
        case .apple: "calendar"
        case .google: "globe"
        case .outlook: "envelope.badge"
        }
    }
}

public enum OutlookAccount: String, Codable, CaseIterable, Identifiable, Sendable {
    case work, personal, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .work: "Work or school"
        case .personal: "Outlook.com"
        case .other: "Other Exchange server"
        }
    }
}

public struct SubscriptionTarget: Codable, Hashable, Sendable {
    public var destination: CalendarDestination
    public var outlookAccount: OutlookAccount
    public var exchangeURL: String

    public init(
        destination: CalendarDestination = .apple, outlookAccount: OutlookAccount = .work,
        exchangeURL: String = ""
    ) {
        self.destination = destination
        self.outlookAccount = outlookAccount
        self.exchangeURL = exchangeURL
    }

    public var instructions: String {
        switch destination {
        case .apple:
            "In Calendar, choose Subscribe. Set Location to iCloud to see the calendar on your other devices, or On My Mac for this Mac. Choose an auto-refresh interval, then click OK."
        case .google:
            "Sign in to the Google account you want to use, then confirm Add. If Google doesn’t show the prompt, choose Other calendars → + → From URL and paste the feed link."
        case .outlook:
            "In Outlook on the web, choose Add calendar → Subscribe from web. Paste the feed link, give the calendar a name, and choose Import or Save. Your organization must allow internet calendar subscriptions."
        }
    }

    public var normalized: SubscriptionTarget {
        SubscriptionTarget(
            destination: destination,
            outlookAccount: destination == .outlook ? outlookAccount : .work,
            exchangeURL: destination == .outlook && outlookAccount == .other ? exchangeURL : "")
    }

    public func handoffURL(for feed: CalendarFeed) throws -> URL {
        guard let url = feed.feedURL else { throw FeedError.unresolvedSubscription }
        let feedURL = try FeedURL.validated(url.absoluteString)
        switch destination {
        case .apple:
            return try FeedURL.webcal(feedURL)
        case .google:
            var components = URLComponents(string: "https://calendar.google.com/calendar/render")!
            components.queryItems = [URLQueryItem(name: "cid", value: try FeedURL.webcal(feedURL).absoluteString)]
            guard let url = components.url else { throw FeedError.invalidURL }
            return url
        case .outlook:
            switch outlookAccount {
            case .work: return URL(string: "https://outlook.office.com/calendar/")!
            case .personal: return URL(string: "https://outlook.live.com/calendar/")!
            case .other: return try FeedURL.validated(exchangeURL)
            }
        }
    }
}

public enum SubscriptionStatus: String, Codable, Sendable {
    case pending, confirmed
}

public struct SubscriptionRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let feed: CalendarFeed
    public let target: SubscriptionTarget
    public var status: SubscriptionStatus
    public let openedAt: Date
    public var confirmedAt: Date?

    public init(feed: CalendarFeed, target: SubscriptionTarget, openedAt: Date = .now) {
        id = UUID()
        self.feed = feed
        self.target = target
        self.status = .pending
        self.openedAt = openedAt
    }
}
