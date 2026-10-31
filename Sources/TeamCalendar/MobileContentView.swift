#if os(iOS)
    import CalendarCore
    import SwiftUI

    /// The same library and approval flow, with navigation that collapses on narrow windows.
    struct MobileContentView: View {
        @Bindable var store: AppStore
        @State private var columns: NavigationSplitViewVisibility = .all
        @State private var compactColumn: NavigationSplitViewColumn = .content
        @State private var showingSettings = false

        var body: some View {
            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
                sidebar
                    .navigationTitle("Collections")
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } content: {
                catalog
                    .navigationTitle(store.section?.title ?? "Discover")
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
                    .searchable(text: $store.searchText, prompt: "Teams, shows, leagues")
            } detail: {
                if let feed = store.focusedFeed {
                    FeedDetailView(store: store, feed: feed)
                        .id(feed)
                        .navigationTitle(feed.name)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ContentUnavailableView(
                        "Choose a Calendar", systemImage: "calendar",
                        description: Text("Preview a schedule, then select it for review."))
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        store.beginReview()
                    } label: {
                        Label("Review \(store.selectedIDs.count)", systemImage: "calendar.badge.plus")
                    }
                    .disabled(store.selectedIDs.isEmpty || store.isPresentingSheet)
                    .accessibilityIdentifier("reviewCalendars")
                    Menu {
                        Button("Add Calendar URL", systemImage: "plus") { store.beginCustomFeed() }
                            .disabled(store.isPresentingSheet)
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $store.showingReview) {
                SubscriptionSheet(store: store, feeds: store.reviewQueue, target: store.reviewTarget)
            }
            .sheet(isPresented: $store.showingCustomFeed) { CustomFeedSheet(store: store) }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(store: store)
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
            }
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
            .onChange(of: store.visibleFeeds.map(\.id)) {
                // Filtering must not push the first result onto an iPhone's navigation stack.
                if let id = store.focusedID, !store.visibleFeeds.contains(where: { $0.id == id }) {
                    store.focusedID = nil
                }
            }
        }

        private var sidebar: some View {
            List(selection: $store.section) {
                Section("Library") {
                    collection(.discover)
                    collection(.favorites, count: store.favoriteIDs.count)
                    collection(.selected, count: store.selectedIDs.count)
                    collection(.subscriptions, count: store.subscriptionCalendarCount)
                }
                Section("Sports") {
                    ForEach([
                        LibrarySection.football, .americanFootball, .baseball, .basketball,
                        .golf, .motorsport, .tennis, .combatSports,
                    ]) { collection($0) }
                }
                Section("Beyond the stadium") {
                    ForEach([LibrarySection.esports, .actualPlay, .space]) { collection($0) }
                }
                Section("Your sources") { collection(.custom, count: store.customFeeds.count) }
            }
            .listStyle(.sidebar)
        }

        private func collection(_ section: LibrarySection, count: Int? = nil) -> some View {
            NavigationLink(value: section) {
                HStack {
                    Label(section.title, systemImage: section.symbol)
                    Spacer()
                    if let count, count > 0 {
                        Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }

        private var catalog: some View {
            let feeds = store.visibleFeeds
            let groups = Dictionary(grouping: feeds, by: \.league)
            let leagues = store.availableLeagues.filter { groups[$0] != nil }
            return List(selection: $store.focusedID) {
                Section {
                    if store.section == .subscriptions {
                        Picker("Status", selection: $store.subscriptionFilter) {
                            Text("All subscriptions").tag(SubscriptionStatus?.none)
                            Text("Needs confirmation").tag(Optional(SubscriptionStatus.pending))
                            Text("Confirmed").tag(Optional(SubscriptionStatus.confirmed))
                        }
                    }
                    if store.availableLeagues.count > 1 {
                        Picker("League", selection: $store.leagueFilter) {
                            Text("All leagues").tag(String?.none)
                            ForEach(store.availableLeagues, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    }
                    if !feeds.isEmpty {
                        Menu {
                            Button("Select All \(feeds.count) Visible") { store.selectVisible() }
                                .disabled(store.visibleSelectedCount == feeds.count)
                            Button("Deselect \(store.visibleSelectedCount) Visible") { store.deselectVisible() }
                                .disabled(store.visibleSelectedCount == 0)
                        } label: {
                            Label(
                                "\(store.visibleSelectedCount) of \(feeds.count) visible selected",
                                systemImage: "checkmark.circle")
                        }
                    }
                }
                if feeds.isEmpty {
                    ContentUnavailableView(
                        "No Calendars Here", systemImage: "calendar",
                        description: Text(emptyDescription)
                    )
                    .listRowBackground(Color.clear)
                    if !store.searchText.isEmpty || store.leagueFilter != nil || store.subscriptionFilter != nil {
                        Button("Clear Filters") {
                            store.searchText = ""
                            store.leagueFilter = nil
                            store.subscriptionFilter = nil
                        }
                    } else if store.section == .custom {
                        Button("Add Calendar URL") { store.beginCustomFeed() }
                    }
                }
                ForEach(leagues, id: \.self) { league in
                    Section(league) {
                        ForEach(groups[league] ?? []) { feed in
                            HStack(spacing: 8) {
                                NavigationLink(value: feed.id) { rowLabel(feed) }
                                Button {
                                    store.toggleSelection(feed)
                                } label: {
                                    Image(
                                        systemName: store.selectedIDs.contains(feed.id)
                                            ? "checkmark.circle.fill" : "plus.circle"
                                    )
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(
                                    "\(store.selectedIDs.contains(feed.id) ? "Deselect" : "Select") \(feed.name)"
                                )
                                .accessibilityValue(store.selectedIDs.contains(feed.id) ? "Selected" : "Not selected")
                                .accessibilityIdentifier("select.\(feed.id)")
                            }
                            .contextMenu {
                                Button(
                                    store.favoriteIDs.contains(feed.id) ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: "star"
                                ) { store.toggleFavorite(feed) }
                            }
                            .tag(feed.id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                if !store.selectedIDs.isEmpty {
                    HStack {
                        Text("\(store.selectedIDs.count) selected").font(.subheadline).monospacedDigit()
                        Spacer()
                        Button("Review") { store.beginReview() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isPresentingSheet)
                            .accessibilityIdentifier("reviewSelection")
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }

        private func rowLabel(_ feed: CalendarFeed) -> some View {
            let records = store.section == .subscriptions ? store.historyRecords(for: feed) : store.records(for: feed)
            return HStack(spacing: 12) {
                TeamBadge(feed: feed, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.name).font(.headline)
                    Text(feed.location).font(.caption).foregroundStyle(.secondary)
                    if store.favoriteIDs.contains(feed.id) {
                        Label("Favorite", systemImage: "star.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    if records.contains(where: { $0.status == .pending }) {
                        Label("Needs confirmation", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    } else if !records.isEmpty {
                        Label("Confirmed by you", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.teal)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var emptyDescription: String {
            if !store.searchText.isEmpty || store.leagueFilter != nil || store.subscriptionFilter != nil {
                return "Try another search or clear your filters."
            }
            switch store.section {
            case .favorites: return "Save calendars using the star in their details."
            case .selected: return "Use the + beside a calendar to select it for review."
            case .subscriptions: return "Review a calendar and finish setup to track it here."
            default: return "Add a public calendar URL or choose another collection."
            }
        }
    }
#endif
