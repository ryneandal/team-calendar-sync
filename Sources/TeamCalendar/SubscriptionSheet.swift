import CalendarCore
import SwiftUI

struct SubscriptionSheet: View {
    @Bindable var store: AppStore
    let feeds: [CalendarFeed]
    @State private var target: SubscriptionTarget
    @Environment(\.dismiss) private var dismiss
    @State private var approved = false
    @State private var index = 0
    @State private var validating = false
    @State private var validatedRequest: ValidationRequest?
    @State private var readyFeed: CalendarFeed?
    @State private var validationToken = UUID()
    @State private var opening = false
    @State private var error: String?
    @State private var copied = false

    private struct ValidationRequest: Hashable {
        let approved: Bool
        let index: Int
        let feed: CalendarFeed?
        let token: UUID
    }

    init(store: AppStore, feeds: [CalendarFeed], target: SubscriptionTarget) {
        self.store = store
        self.feeds = feeds
        // Each review owns its destination choice, seeded once from the saved preference.
        _target = State(initialValue: target)
    }

    private var current: CalendarFeed? { feeds.indices.contains(index) ? feeds[index] : nil }
    private var validationRequest: ValidationRequest {
        ValidationRequest(approved: approved, index: index, feed: current, token: validationToken)
    }
    private var preparedFeed: CalendarFeed? {
        validatedRequest == validationRequest ? readyFeed : nil
    }
    private var finished: Bool { approved && current == nil }
    private var confirmedCount: Int {
        feeds.filter { store.record(for: $0, target: target)?.status == .confirmed }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(
                    systemName: finished
                        ? (confirmedCount == feeds.count ? "checkmark.circle" : "clock") : "calendar.badge.plus"
                )
                .font(.system(size: 29, weight: .light)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        finished
                            ? (confirmedCount == feeds.count
                                ? "Your calendar, a little more you." : "Ready when you are.")
                            : approved ? "Finish in your calendar app" : "Make time for what you love."
                    )
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(
                        finished
                            ? "\(confirmedCount) of \(feeds.count) subscriptions confirmed by you."
                            : approved
                                ? "Calendar \(index + 1) of \(feeds.count) · \(target.destination.title)"
                                : "Review your selection and choose where to subscribe."
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(26)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if finished { completion } else if approved, let feed = current { handoff(feed) } else { review }
                }
                .padding(26)
            }
            Divider()
            footer.padding(20)
        }
        .frame(width: 610, height: 690)
        .interactiveDismissDisabled(opening)
        .task(id: validationRequest) {
            let request = validationRequest
            guard request.approved, request.feed != nil else { return }
            await validate(request)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SmallHeading(text: "\(feeds.count) selected calendars")
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(feeds) { feed in
                        HStack(alignment: .top, spacing: 12) {
                            TeamBadge(feed: feed, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.name).font(.system(size: 12, weight: .medium))
                                Text(feed.sourceName).font(.caption).foregroundStyle(.secondary)
                                if let coverage = feed.coverage {
                                    Text(coverage).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 12) {
                SmallHeading(text: "Choose your calendar app")
                ForEach(CalendarDestination.allCases) { destination in
                    Button {
                        target.destination = destination
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: destination.symbol).font(.system(size: 22))
                                .foregroundStyle(destination == target.destination ? Color.teal : Color.secondary)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(destination.title).font(.system(size: 13, weight: .semibold))
                                Text(destination.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: destination == target.destination ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(destination == target.destination ? Color.teal : Color.secondary)
                        }
                        .padding(12)
                        .background(
                            destination == target.destination ? Color.teal.opacity(0.07) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    destination == target.destination
                                        ? Color.teal.opacity(0.5) : Color.secondary.opacity(0.2))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(destination.title), \(destination.subtitle)")
                    .accessibilityAddTraits(destination == target.destination ? .isSelected : [])
                }
                if target.destination == .outlook {
                    Picker("Account", selection: $target.outlookAccount) {
                        ForEach(OutlookAccount.allCases) { Text($0.title).tag($0) }
                    }
                    if target.outlookAccount == .other {
                        TextField("Exchange web calendar URL (https://…)", text: $target.exchangeURL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Exchange web calendar URL")
                        Text(
                            "Use your organization’s Outlook Web Access address. Support for internet subscriptions depends on the server and your administrator."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Label {
                Text(
                    "Only the selected public feed links are passed to your calendar app. You’ll finish approval there. Feeds may include provider messages."
                )
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "hand.raised").foregroundStyle(.secondary)
            }
        }
    }

    private func handoff(_ feed: CalendarFeed) -> some View {
        let record = store.record(for: feed, target: target)
        return VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                TeamBadge(feed: feed, size: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(feed.name).font(.title2.weight(.semibold))
                    Text("\(feed.sourceName) → \(target.destination.title)").font(.subheadline).foregroundStyle(
                        .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("1. Open your calendar app", systemImage: "arrow.up.forward.app")
                    .font(.headline)
                Text(target.instructions).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(preparedFeed?.feedURL?.absoluteString ?? "Preparing the subscription link…")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button {
                        guard let preparedFeed, !opening else { return }
                        CalendarHandoff.copyURL(preparedFeed)
                        store.recordHandoff(preparedFeed, target: target)
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy feed URL", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(preparedFeed == nil || opening)
                    Spacer()
                    Button {
                        guard let preparedFeed, !opening else { return }
                        opening = true
                        Task { await open(preparedFeed) }
                    } label: {
                        Label(
                            target.destination == .outlook
                                ? "Copy URL & Open Outlook" : "Open \(target.destination.title)",
                            systemImage: "arrow.up.forward")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(preparedFeed == nil || opening || record?.status == .confirmed)
                }
                if validating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking the calendar feed…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if preparedFeed != nil {
                    Label("Calendar feed checked", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.teal)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Try Again") {
                        resetStep()
                        validationToken = UUID()
                    }.controlSize(.small).disabled(opening)
                }
            }
            .padding(18).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                Label("2. Confirm when you’ve subscribed", systemImage: "checkmark.circle")
                    .font(.headline)
                Text(
                    "After completing the steps in \(target.destination.title), return here. Opening the app or copying the link alone doesn’t add the subscription."
                )
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if record?.status == .confirmed {
                    Label("You’ve already confirmed this subscription.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(.teal)
                } else {
                    Button("I’ve Added This Calendar") {
                        store.confirm(feed, target: target)
                        advance()
                    }
                    .disabled(record == nil || opening)
                    .buttonStyle(.bordered)
                }
            }
            Text(
                "Subscriptions are read-only. To remove one later, unsubscribe in your calendar app. Updates may take several hours to appear."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(feeds) { feed in
                let record = store.record(for: feed, target: target)
                let confirmed = record?.status == .confirmed
                HStack(spacing: 12) {
                    TeamBadge(feed: feed, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.name).font(.system(size: 13, weight: .medium))
                        Text(
                            confirmed
                                ? "Confirmed by you"
                                : record != nil
                                    ? "Awaiting your confirmation"
                                    : store.selectedIDs.contains(feed.id)
                                        ? "Not confirmed · still in your selection"
                                        : "Not confirmed"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: confirmed ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(confirmed ? Color.teal : Color.secondary)
                }
            }
            Divider()
            Text("Your calendar app will keep subscriptions up to date. You can close Team Calendar whenever you like.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if confirmedCount < feeds.count {
                Button("Revisit Unfinished Calendars") {
                    index = feeds.firstIndex { store.record(for: $0, target: target)?.status != .confirmed } ?? 0
                    resetStep()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(finished ? "Close" : "Finish Later") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(opening)
            Spacer()
            if finished {
                Button("View My Subscriptions") {
                    store.showSubscriptions(focusing: feeds.first?.id)
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else if approved {
                Button(
                    current.flatMap { store.record(for: $0, target: target) }?.status == .confirmed
                        ? "Next" : "Skip for Now"
                ) {
                    advance()
                }.disabled(opening)
            } else {
                Button("Approve & Continue") {
                    store.target = target
                    store.save()
                    approved = true
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(
                    feeds.isEmpty
                        || (target.destination == .outlook && target.outlookAccount == .other
                            && (try? FeedURL.validated(target.exchangeURL)) == nil)
                )
            }
        }
    }

    private func validate(_ request: ValidationRequest) async {
        guard let feed = request.feed else { return }
        validating = true
        validatedRequest = nil
        readyFeed = nil
        error = nil
        do {
            let resolved = try await store.resolveFeed(feed)
            guard !Task.isCancelled, request == validationRequest else { return }
            guard let url = resolved.feedURL else { throw FeedError.unresolvedSubscription }
            _ = try await store.client.preview(for: url, forceRefresh: true)
            guard !Task.isCancelled, request == validationRequest else { return }
            readyFeed = resolved
            validatedRequest = request
        } catch {
            guard !Task.isCancelled, request == validationRequest else { return }
            self.error = error.localizedDescription
        }
        validating = false
    }

    private func open(_ feed: CalendarFeed) async {
        defer { opening = false }
        guard preparedFeed == feed, !Task.isCancelled else { return }
        let destination = target
        error = nil
        do {
            if destination.destination == .outlook {
                CalendarHandoff.copyURL(feed)
                store.recordHandoff(feed, target: destination)
                copied = true
            }
            try await CalendarHandoff.open(feed, target: destination)
            store.recordHandoff(feed, target: destination)
        } catch { self.error = error.localizedDescription }
    }

    private func advance() {
        if let feed = current, store.record(for: feed, target: target)?.status == .confirmed {
            store.selectedIDs.remove(feed.id)
            store.save()
        }
        index += 1
        resetStep()
    }

    private func resetStep() {
        validatedRequest = nil
        readyFeed = nil
        validating = false
        error = nil
        copied = false
    }
}
