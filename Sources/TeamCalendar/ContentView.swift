import CalendarCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        GeometryReader { bounds in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .frame(height: bounds.size.height, alignment: .top)
                    .navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 250)
            } content: {
                catalog
                    .frame(height: bounds.size.height, alignment: .top)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 390, max: 550)
            } detail: {
                Group {
                    if let feed = store.focusedFeed {
                        FeedDetailView(store: store, feed: feed)
                            .id(feed.id)
                    } else {
                        EmptyState(
                            symbol: "calendar", title: "A little more to look forward to",
                            message: "Choose a calendar to see its upcoming events and subscription options.")
                    }
                }
                .frame(height: bounds.size.height, alignment: .top)
            }
        }
        .navigationTitle("Team Calendar")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search teams, shows, events")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.beginCustomFeed()
                } label: {
                    Label("Add Calendar URL", systemImage: "plus")
                }
                .disabled(store.isPresentingSheet)
                .help("Add a custom calendar URL (⇧⌘N)")
                Button {
                    store.beginReview()
                } label: {
                    Label("Review \(store.selectedIDs.count)", systemImage: "calendar.badge.plus")
                }
                .disabled(store.selectedIDs.isEmpty || store.isPresentingSheet)
                .help("Review selected calendars (⌘Return)")
            }
        }
        .frame(minWidth: 950, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
        .sheet(isPresented: $store.showingReview) {
            SubscriptionSheet(store: store, feeds: store.reviewQueue, target: store.reviewTarget)
        }
        .sheet(isPresented: $store.showingCustomFeed) { CustomFeedSheet(store: store) }
        .alert(
            "Something needs attention",
            isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.section) { alignFocus() }
        .onChange(of: store.searchText) { alignFocus() }
        .onChange(of: store.visibleFeeds.map(\.id)) { alignFocus() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 25, weight: .medium)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Team Calendar").font(.system(size: 13, weight: .semibold))
                    Text("Follow what you love").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 20)

            List(selection: $store.section) {
                Section("Library") {
                    sidebarRow(.discover, count: nil)
                    sidebarRow(.favorites, count: store.favoriteIDs.isEmpty ? nil : store.favoriteIDs.count)
                    sidebarRow(.selected, count: store.selectedIDs.isEmpty ? nil : store.selectedIDs.count)
                    sidebarRow(
                        .subscriptions,
                        count: store.subscriptionCalendarCount == 0 ? nil : store.subscriptionCalendarCount)
                }
                Section("Sports") {
                    ForEach([
                        LibrarySection.football, .americanFootball, .baseball, .basketball, .golf, .motorsport, .tennis,
                        .combatSports,
                    ]) { section in
                        sidebarRow(section, count: nil)
                    }
                }
                Section("Beyond the stadium") {
                    ForEach([LibrarySection.esports, .actualPlay, .space]) { section in
                        sidebarRow(section, count: nil)
                    }
                }
                Section("Your sources") { sidebarRow(.custom, count: nil) }
            }
            .listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 8) {
                Label("Updates from the source", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                Text("Your calendar app refreshes subscribed feeds. Check each source’s season and coverage.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsLink { Text("Sources & preferences…").font(.system(size: 10)) }
                    .buttonStyle(.link)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarRow(_ section: LibrarySection, count: Int?) -> some View {
        HStack {
            Label(section.title, systemImage: section.symbol)
            Spacer(minLength: 4)
            if let count {
                Text(count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .tag(section)
        .padding(.vertical, 3)
    }

    private var catalog: some View {
        let feeds = store.visibleFeeds
        let groups = Dictionary(grouping: feeds, by: \.league)
        var seenLeagues = Set<String>()
        let leagues = feeds.map(\.league).filter { seenLeagues.insert($0).inserted }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SmallHeading(
                    text: store.section == .discover ? "A place for your passions" : "Your calendar collection")
                Text(store.section == .discover ? "Never miss a moment." : store.section?.title ?? "Discover")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sectionDescription)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            if store.section == .subscriptions {
                Picker("Subscription status", selection: $store.subscriptionFilter) {
                    Text("All").tag(SubscriptionStatus?.none)
                    Text("Needs confirmation").tag(Optional(SubscriptionStatus.pending))
                    Text("Confirmed").tag(Optional(SubscriptionStatus.confirmed))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .accessibilityLabel("Filter subscriptions by status")
                .padding(.horizontal, 24).padding(.bottom, 12)
            }

            if store.availableLeagues.count > 1 {
                Picker("League or collection", selection: $store.leagueFilter) {
                    Text("All leagues & collections").tag(String?.none)
                    ForEach(store.availableLeagues, id: \.self) { league in
                        Text(league).tag(Optional(league))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Filter by league or collection")
                .padding(.horizontal, 24).padding(.bottom, 12)
            }

            if feeds.isEmpty {
                emptyCatalog
            } else {
                HStack {
                    Text("\(feeds.count) \(feeds.count == 1 ? "calendar" : "calendars")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !store.searchText.isEmpty {
                        Button("Clear search") { store.searchText = "" }.buttonStyle(.link).font(.caption)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 8)
                visibleSelectionActions
                    .padding(.horizontal, 24).padding(.bottom, 8)
                List(selection: $store.focusedID) {
                    ForEach(leagues, id: \.self) { league in
                        Section(league) {
                            ForEach(groups[league] ?? []) { feed in
                                feedRow(feed).tag(feed.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            selectionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sectionDescription: String {
        switch store.section ?? .discover {
        case .discover: "Teams, shows, and moments worth making time for."
        case .favorites: "Save calendars here to find them again, before or after subscribing."
        case .selected: "Your shortlist, ready to add to your calendar app."
        case .subscriptions: "Track your handoffs and the subscriptions you’ve confirmed."
        case .custom: "School terms, community events, or any public calendar feed."
        default: "Follow the teams, shows, and events you love, in the calendar you already use."
        }
    }

    private var visibleSelectionActions: some View {
        let unselectedCount = store.visibleFeeds.count - store.visibleSelectedCount
        return HStack(spacing: 14) {
            Button("Select \(unselectedCount) visible") { store.selectVisible() }
                .disabled(unselectedCount == 0)
                .help("Select the unselected calendars in these results. Other selections stay unchanged.")
            Button("Deselect \(store.visibleSelectedCount) visible") { store.deselectVisible() }
                .disabled(store.visibleSelectedCount == 0)
                .help("Remove only these visible calendars from your review selection.")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .buttonStyle(.link)
    }

    private func feedRow(_ feed: CalendarFeed) -> some View {
        HStack(spacing: 12) {
            TeamBadge(feed: feed)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(feed.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if store.favoriteIDs.contains(feed.id) {
                        Image(systemName: "star.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(feed.location).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                subscriptionStatus(
                    store.section == .subscriptions ? store.historyRecords(for: feed) : store.records(for: feed))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button {
                store.toggleSelection(feed)
            } label: {
                Image(systemName: store.selectedIDs.contains(feed.id) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(store.selectedIDs.contains(feed.id) ? Color.teal : Color.secondary.opacity(0.65))
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(store.selectedIDs.contains(feed.id) ? "Deselect" : "Select") \(feed.name)")
            .accessibilityValue(store.selectedIDs.contains(feed.id) ? "Selected for review" : "Not selected")
            .help(store.selectedIDs.contains(feed.id) ? "Remove from selection" : "Select calendar")
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button(store.selectedIDs.contains(feed.id) ? "Deselect Calendar" : "Select Calendar") {
                store.toggleSelection(feed)
            }
            Button(store.favoriteIDs.contains(feed.id) ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(feed)
            }
            Divider()
            Button("Copy Feed URL") { CalendarHandoff.copyURL(store.cachedFeed(feed)) }
                .disabled(store.cachedFeed(feed).feedURL == nil)
            Link("Visit Source", destination: feed.sourceURL)
        }
    }

    @ViewBuilder private func subscriptionStatus(_ records: [SubscriptionRecord]) -> some View {
        let pendingCount = records.filter { $0.status == .pending }.count
        if pendingCount > 0 {
            Label(
                records.count == 1 ? "Needs confirmation" : "\(pendingCount) of \(records.count) need confirmation",
                systemImage: "clock"
            )
            .font(.caption).foregroundStyle(.secondary)
        } else if !records.isEmpty {
            Label(
                records.count == 1 ? "Confirmed by you" : "Confirmed by you · \(records.count) destinations",
                systemImage: "checkmark.circle"
            )
            .font(.caption).foregroundStyle(.teal)
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(store.selectedIDs.count) selected").font(.system(size: 12, weight: .semibold))
                    Text(
                        store.selectedIDs.count > store.visibleSelectedCount
                            ? "\(store.selectedIDs.count - store.visibleSelectedCount) outside these results"
                            : "Choose a calendar app in Review"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Review…") { store.beginReview() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedIDs.isEmpty || store.isPresentingSheet)
            }
            .padding(16)
        }
    }

    @ViewBuilder private var emptyCatalog: some View {
        if !store.searchText.isEmpty || store.leagueFilter != nil {
            VStack {
                EmptyState(
                    symbol: "magnifyingglass", title: "No calendars found",
                    message: "Try another team or league, or clear your filters to see the full collection.")
                Button("Clear Filters") {
                    store.searchText = ""
                    store.leagueFilter = nil
                    store.subscriptionFilter = nil
                }.buttonStyle(.bordered).padding(.bottom, 36)
            }
        } else if store.section == .favorites {
            VStack {
                EmptyState(
                    symbol: "star", title: "Keep your favorites close",
                    message:
                        "Use the star in a calendar’s details to save it here. Favorites stay saved after you subscribe."
                )
                Button("Browse Calendars") { store.section = .discover }
                    .buttonStyle(.bordered).padding(.bottom, 36)
            }
        } else if store.section == .selected {
            EmptyState(
                symbol: "checkmark.circle", title: "Build your shortlist",
                message:
                    "Use the + beside a calendar to select it. You’ll review everything before opening your calendar app."
            )
        } else if store.section == .subscriptions {
            if let filter = store.subscriptionFilter {
                VStack {
                    EmptyState(
                        symbol: filter == .pending ? "clock" : "calendar.badge.checkmark",
                        title: filter == .pending ? "No calendars need confirmation" : "No confirmed subscriptions",
                        message: filter == .pending
                            ? "You have no saved handoffs awaiting confirmation. Team Calendar can’t verify changes in your calendar app."
                            : "After adding a calendar in your calendar app, return here to confirm it.")
                    Button("Show All Subscriptions") { store.subscriptionFilter = nil }
                        .buttonStyle(.bordered).padding(.bottom, 36)
                }
            } else {
                EmptyState(
                    symbol: "calendar.badge.checkmark", title: "Your subscriptions start here",
                    message:
                        "Select a calendar and review it. Saved handoffs and subscriptions you confirm will appear here."
                )
            }
        } else {
            VStack {
                EmptyState(
                    symbol: "link", title: "Bring your own calendar",
                    message:
                        "Add a public HTTPS or webcal feed to preview it and subscribe in your favorite calendar app.")
                Button("Add Calendar URL…") { store.beginCustomFeed() }
                    .disabled(store.isPresentingSheet)
                    .buttonStyle(.bordered).padding(.bottom, 36)
            }
        }
    }

    private func alignFocus() {
        if !store.visibleFeeds.contains(where: { $0.id == store.focusedID }) {
            store.focusedID = store.visibleFeeds.first?.id
        }
    }
}
