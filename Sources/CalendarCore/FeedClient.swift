import Foundation

public actor FeedClient {
    public static let maximumBytes = 5 * 1_024 * 1_024
    private var cache: [URL: FeedPreview] = [:]
    private var resolvedURLs: [String: URL] = [:]
    private var resolving: [String: Task<URL, Error>] = [:]
    private var fanCalendarRetryAt: Date?
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 35
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: SecureRedirectDelegate(), delegateQueue: nil)
        now = { .now }
    }

    init(session: URLSession, now: @escaping @Sendable () -> Date = { .now }) {
        self.session = session
        self.now = now
    }

    public func preview(for url: URL, forceRefresh: Bool = false) async throws -> FeedPreview {
        let url = try FeedURL.validated(url.absoluteString)
        if !forceRefresh, let cached = cache[url], Date.now.timeIntervalSince(cached.fetchedAt) < 600 {
            return cached
        }
        var request = URLRequest(url: url)
        request.setValue("text/calendar, text/plain;q=0.8", forHTTPHeaderField: "Accept")
        let data = try await download(request, limit: Self.maximumBytes)
        let preview = try ICalendarParser.parse(data)
        cache[url] = preview
        return preview
    }

    public func resolve(_ feed: CalendarFeed, cachedURL: URL? = nil) async throws -> CalendarFeed {
        if let url = feed.feedURL {
            return feed.resolved(with: try FeedURL.validated(url.absoluteString))
        }
        guard let key = feed.fanCalendarTeamKey else { throw FeedError.unresolvedSubscription }
        if let cachedURL {
            return feed.resolved(with: try FanCalendarSubscription.validated(cachedURL))
        }
        if let url = resolvedURLs[key] { return feed.resolved(with: url) }
        if let pending = resolving[key] {
            let url = try await pending.value
            return feed.resolved(with: url)
        }
        let pending = Task {
            let request = try FanCalendarSubscription.request(teamKey: key)
            let data = try await self.download(request, limit: 32_768)
            return try FanCalendarSubscription.subscriptionURL(from: data)
        }
        resolving[key] = pending
        defer { resolving[key] = nil }
        let url = try await pending.value
        resolvedURLs[key] = url
        return feed.resolved(with: url)
    }

    private func download(_ original: URLRequest, limit: Int) async throws -> Data {
        let isFanCalendar = ["fancalendar.app", "www.fancalendar.app"].contains(original.url?.host ?? "")
        if isFanCalendar, let retryAt = fanCalendarRetryAt, retryAt > now() {
            throw FeedError.rateLimited(until: retryAt)
        }
        var request = original
        request.setValue("TeamCalendar/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw FeedError.invalidCalendar }
        if response.statusCode == 429 {
            let retryAt = Self.retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: now())
            if isFanCalendar { fanCalendarRetryAt = retryAt }
            throw FeedError.rateLimited(until: retryAt)
        }
        guard (200..<300).contains(response.statusCode) else { throw FeedError.badResponse(response.statusCode) }
        guard response.expectedContentLength <= Int64(limit) else { throw FeedError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            if data.count % 8_192 == 0 { try Task.checkCancellation() }
            guard data.count < limit else { throw FeedError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    /// HTTP Retry-After accepts either delay-seconds or an HTTP-date (RFC 9110 §10.2.3).
    private static func retryDate(_ header: String?, now: Date) -> Date {
        let value = (header ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
            let seconds = TimeInterval(value), seconds.isFinite
        {
            return now.addingTimeInterval(max(1, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(now.addingTimeInterval(1), date)
            }
        }
        return now.addingTimeInterval(900)
    }
}

private final class SecureRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, (try? FeedURL.validated(url.absoluteString)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
