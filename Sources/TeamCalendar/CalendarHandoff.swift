import AppKit
import CalendarCore

@MainActor
enum CalendarHandoff {
    static func open(_ feed: CalendarFeed, target: SubscriptionTarget) async throws {
        let url = try target.handoffURL(for: feed)
        if target.destination == .apple {
            guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
                throw HandoffError.calendarNotInstalled
            }
            let configuration = NSWorkspace.OpenConfiguration()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration) {
                    _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } else if !NSWorkspace.shared.open(url) {
            throw HandoffError.couldNotOpen
        }
    }

    static func copyURL(_ feed: CalendarFeed) {
        guard let url = feed.feedURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    enum HandoffError: LocalizedError {
        case calendarNotInstalled, couldNotOpen
        var errorDescription: String? {
            switch self {
            case .calendarNotInstalled:
                "Apple Calendar couldn’t be found. Copy the feed link and add it in your calendar app."
            case .couldNotOpen:
                "The calendar service couldn’t be opened. Copy the feed link and open it in your browser."
            }
        }
    }
}
