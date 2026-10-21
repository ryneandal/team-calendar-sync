import CalendarCore
import SwiftUI

struct FeedDetailView: View {
    @Bindable var store: AppStore
    let feed: CalendarFeed
    @State private var preview: FeedPreview?
    @State private var resolvedFeed: CalendarFeed?
    @State private var loading = false
    @State private var previewError: String?
    @State private var copied = false
    @State private var deletingCustom = false
    @State private var removingRecord: SubscriptionRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if !feedRecords.isEmpty {
                    Divider()
                    subscriptionHistory
                }
                Divider()
                upcoming
                Divider()
                source
            }
            .padding(28)
            .frame(maxWidth: 580, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: store.refreshToken) { await loadPreview() }
        .confirmationDialog("Remove this custom calendar?", isPresented: $deletingCustom) {
            Button("Remove from Team Calendar", role: .destructive) { store.removeCustomFeed(feed) }
        } message: {
            Text("This removes the source from this app. Any subscription in your calendar app will remain.")
        }
        .alert(
            "Forget this subscription record?",
            isPresented: Binding(
                get: { removingRecord != nil }, set: { if !$0 { removingRecord = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { removingRecord = nil }
            Button("Forget Record", role: .destructive) {
                if let record = removingRecord { store.removeRecord(record) }
                removingRecord = nil
            }
        } message: {
            Text(
                "This only clears Team Calendar’s record. To unsubscribe, remove the calendar in \(removingRecord?.target.destination.title ?? "your calendar app")."
            )
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                TeamBadge(feed: feed, size: 72)
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    Label(feed.sport.title, systemImage: feed.sport.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                    Button {
                        store.toggleFavorite(feed)
                    } label: {
                        Label(
                            store.favoriteIDs.contains(feed.id) ? "In Favorites" : "Add to Favorites",
                            systemImage: store.favoriteIDs.contains(feed.id) ? "star.fill" : "star")
                    }
                    .controlSize(.small)
                    .accessibilityLabel(
                        "\(store.favoriteIDs.contains(feed.id) ? "Remove" : "Add") \(feed.name) \(store.favoriteIDs.contains(feed.id) ? "from" : "to") favorites"
                    )
                    .accessibilityValue(store.favoriteIDs.contains(feed.id) ? "Favorite" : "Not a favorite")
                    .help(
                        store.favoriteIDs.contains(feed.id)
                            ? "Remove from Favorites" : "Save this calendar in Favorites")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(feed.name).font(.system(size: 29, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(feed.league) · \(feed.location)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(feed.introduction)
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.toggleSelection(feed)
            } label: {
                Label(
                    store.selectedIDs.contains(feed.id) ? "Selected for review" : "Select calendar",
                    systemImage: store.selectedIDs.contains(feed.id) ? "checkmark" : "plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityLabel(
                "\(store.selectedIDs.contains(feed.id) ? "Deselect" : "Select") \(feed.name) for review"
            )
            .accessibilityValue(store.selectedIDs.contains(feed.id) ? "Selected" : "Not selected")
            Text("You’ll choose an account and approve before subscribing.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SmallHeading(text: "Coming up")
                Spacer()
                Button {
                    store.refreshToken = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.borderless).help("Refresh preview (⌘R)").disabled(loading)
                .accessibilityLabel("Refresh calendar preview")
            }
            if loading && preview == nil {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking the latest schedule…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            } else if let previewError {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Preview unavailable", systemImage: "wifi.exclamationmark").font(.subheadline.weight(.medium))
                    Text(previewError).font(.caption).foregroundStyle(.secondary)
                    Button("Try Again") { store.refreshToken = UUID() }.controlSize(.small)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            } else if let preview {
                let events = preview.upcoming()
                if events.isEmpty {
                    Text(
                        "No upcoming events are listed in this preview. Check the source’s season and coverage; some feeds need a new subscription each season."
                    )
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                } else {
                    VStack(spacing: 8) {
                        ForEach(events) { event in EventRow(event: event) }
                    }
                }
                if preview.hasUnexpandedRecurrence || preview.skippedEvents > 0 {
                    Text(
                        "This is a partial preview. Some calendar details couldn’t be shown here. Your calendar app receives the original feed."
                    )
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                } else if preview.containsRecurrence {
                    Text(
                        "Recurring dates are previewed for the next six months. The source controls breaks and schedule changes."
                    )
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Preview checked \(preview.fetchedAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock")
                    Text("Times in \(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmallHeading(text: "About this calendar")
            Label("Updates in your calendar app", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
            Text(
                "A subscription follows changes to the schedule. Your calendar provider decides how often to refresh, so changes may take time to appear."
            )
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Source").foregroundStyle(.secondary)
                Spacer()
                Link("\(feed.sourceName) ↗", destination: feed.sourceURL)
            }.font(.system(size: 12))
            Text(
                (resolvedFeed ?? store.cachedFeed(feed)).feedURL?.absoluteString
                    ?? "The subscription link will appear after the preview loads."
            )
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            .textSelection(.enabled).lineLimit(3)
            HStack {
                Button {
                    CalendarHandoff.copyURL(resolvedFeed ?? store.cachedFeed(feed))
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy feed URL", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
                .disabled((resolvedFeed ?? store.cachedFeed(feed)).feedURL == nil)
                Spacer()
                if feed.sport == .custom && store.customFeeds.contains(where: { $0.id == feed.id }) {
                    Button(role: .destructive) {
                        deletingCustom = true
                    } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless).help("Remove custom calendar")
                }
            }
            if feed.sport != .custom {
                Text(
                    "\(feed.sourceKind) · \(feed.sourceName). Schedules may change; the feed may also include provider messages."
                )
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private var feedRecords: [SubscriptionRecord] {
        store.historyRecords(for: feed).sorted { $0.status == .pending && $1.status != .pending }
    }

    private var subscriptionHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmallHeading(text: "Your subscriptions")
            ForEach(feedRecords) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(record.target.destination.title, systemImage: record.target.destination.symbol)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            removingRecord = record
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless).help("Forget record; doesn’t unsubscribe")
                        .accessibilityLabel("Forget \(targetDescription(record.target)) subscription record")
                    }
                    if record.target.destination == .outlook {
                        Text(record.target.outlookAccount.title)
                            .font(.caption).foregroundStyle(.secondary)
                        if record.target.outlookAccount == .other {
                            Text(record.target.exchangeURL)
                                .font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if !record.feed.isSameSubscription(as: store.cachedFeed(feed)) {
                        Text("Previously used feed · \(record.feed.name)")
                            .font(.caption.weight(.medium))
                        if let url = record.feed.feedURL {
                            Text(url.absoluteString)
                                .font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Label(
                        record.status == .confirmed ? "Confirmed by you" : "Awaiting your confirmation",
                        systemImage: record.status == .confirmed ? "checkmark.circle.fill" : "clock"
                    )
                    .font(.caption).foregroundStyle(record.status == .confirmed ? Color.teal : Color.secondary)
                    if record.status == .pending {
                        Button("Resume Setup…") { store.resume(record: record) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(store.isPresentingSheet)
                            .accessibilityLabel("Resume \(feed.name) setup in \(targetDescription(record.target))")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Manage or remove subscriptions in your calendar app. Team Calendar can’t verify changes made there.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func targetDescription(_ target: SubscriptionTarget) -> String {
        guard target.destination == .outlook else { return target.destination.title }
        let account = target.outlookAccount == .other ? target.exchangeURL : target.outlookAccount.title
        return "\(target.destination.title), \(account)"
    }

    private func loadPreview() async {
        loading = true
        previewError = nil
        do {
            let resolved = try await store.resolveFeed(feed)
            guard !Task.isCancelled else { return }
            resolvedFeed = resolved
            guard let url = resolved.feedURL else { throw FeedError.unresolvedSubscription }
            let result = try await store.client.preview(for: url, forceRefresh: preview != nil)
            guard !Task.isCancelled else { return }
            preview = result
        } catch is CancellationError { return } catch {
            guard !Task.isCancelled else { return }
            previewError = error.localizedDescription
        }
        loading = false
    }
}
