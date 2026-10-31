import CalendarCore
import Foundation

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
enum CalendarHandoff {
    static func open(_ feed: CalendarFeed, target: SubscriptionTarget) async throws {
        let url = try target.handoffURL(for: feed)
        #if os(macOS)
            if target.destination == .apple {
                guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
                else {
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
        #else
            // Let iOS resolve the calendar URL. No app-specific scheme, private API,
            // or access to the user's event store is needed for a live subscription.
            guard await UIApplication.shared.open(url) else { throw HandoffError.couldNotOpen }
        #endif
    }

    static func copyURL(_ feed: CalendarFeed) {
        guard let url = feed.feedURL else { return }
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
            UIPasteboard.general.url = url
        #endif
    }

    enum HandoffError: LocalizedError {
        case calendarNotInstalled, couldNotOpen
        var errorDescription: String? {
            switch self {
            case .calendarNotInstalled:
                "Apple Calendar couldn’t be found. Copy the feed link and add it in your calendar app."
            case .couldNotOpen:
                "No calendar handler opened this link. Copy the feed URL and add it using your calendar app’s subscription option."
            }
        }
    }
}
