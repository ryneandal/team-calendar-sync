import CalendarCore
import SwiftUI

@main
struct TeamCalendarApp: App {
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("Team Calendar", id: "main") {
            ContentView(store: store)
                .tint(.teal)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Add Calendar URL…") { store.beginCustomFeed() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(store.isPresentingSheet)
                Button("Review Selected Calendars…") { store.beginReview() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(store.selectedIDs.isEmpty || store.isPresentingSheet)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Preview") { store.refreshToken = UUID() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Menu("Calendar Sources") {
                    ForEach(CalendarSourceDirectory.sources) { source in
                        Link(source.name, destination: source.url)
                    }
                }
                Link(
                    "Apple Calendar Subscription Help",
                    destination: URL(string: "https://support.apple.com/guide/calendar/icl1022/mac")!)
                Link(
                    "Google Calendar Subscription Help",
                    destination: URL(string: "https://support.google.com/calendar/answer/37100?hl=en")!)
                Link(
                    "Outlook Subscription Help",
                    destination: URL(
                        string:
                            "https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c"
                    )!)
            }
        }

        Settings {
            SettingsView(store: store)
                .tint(.teal)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct SettingsView: View {
    @Bindable var store: AppStore
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Default calendar app", selection: $store.target.destination) {
                    ForEach(CalendarDestination.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("About your subscriptions") {
                Text(
                    "Your calendar app refreshes subscriptions, even when Team Calendar is closed. Refresh timing is controlled by your calendar provider."
                )
                Text(
                    "Team Calendar doesn’t read your personal calendar or ask for account passwords. Your selections and subscription history stay on this Mac. Previewing a feed connects directly to its provider."
                )
                .foregroundStyle(.secondary)
            }
            Section("Calendar sources") {
                Text(
                    "Each calendar’s details show its provider and coverage. Season-specific feeds may need a new subscription for the following season."
                )
                .font(.caption).foregroundStyle(.secondary)
                ForEach(CalendarSourceDirectory.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Link(source.name, destination: source.url)
                        Text(source.scope).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(
                    "Team Calendar is not affiliated with any provider, team, league, or show. Independent and community feeds may include provider messages."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
        .onChange(of: store.target) { store.save() }
    }
}
