import Foundation

/// A versioned on-disk snapshot. Optional additions preserve version-one libraries.
public struct LibrarySnapshot: Codable, Sendable {
    public var version = 1
    public let customFeeds: [CalendarFeed]
    public let selectedIDs: Set<String>
    public let records: [SubscriptionRecord]
    public let target: SubscriptionTarget
    public let resolvedURLs: [String: URL]?
    public let favoriteIDs: Set<String>?

    public init(
        customFeeds: [CalendarFeed], selectedIDs: Set<String>, records: [SubscriptionRecord],
        target: SubscriptionTarget, resolvedURLs: [String: URL] = [:], favoriteIDs: Set<String> = []
    ) {
        self.customFeeds = customFeeds
        self.selectedIDs = selectedIDs
        self.records = records
        self.target = target
        self.resolvedURLs = resolvedURLs
        self.favoriteIDs = favoriteIDs
    }
}

/// Keeps persistence independent of SwiftUI and makes tests use their own temporary libraries.
public struct LibraryFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> LibrarySnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
        guard snapshot.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
