import CalendarCore
import SwiftUI

struct CustomFeedSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var validating = false
    @State private var error: String?
    @State private var validationTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        #if os(iOS)
            NavigationStack {
                Form {
                    Section {
                        TextField("Calendar name", text: $name)
                            .focused($focused)
                            .disabled(validating)
                        TextField("https://example.com/calendar.ics", text: $address)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Feed URL")
                            .disabled(validating)
                    } header: {
                        Text("Public calendar feed")
                    } footer: {
                        Text(
                            "Use an HTTPS or webcal iCalendar link. We’ll check its source. You’ll review and approve before subscribing."
                        )
                    }
                    if validating { ProgressView("Checking calendar…") }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("Add Calendar URL")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            validationTask?.cancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Check & Add") { validationTask = Task { await add() } }
                            .disabled(
                                validating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || address.isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
            .onDisappear { validationTask?.cancel() }
        #else
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "link.circle").font(.system(size: 32, weight: .light)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bring your own calendar").font(.title2.weight(.bold))
                        Text("A school, a club, a community. Keep it all in view.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Form {
                    TextField("Name", text: $name, prompt: Text("e.g. Local running club"))
                        .focused($focused)
                    TextField("Feed URL", text: $address, prompt: Text("https://example.com/calendar.ics"))
                }.textFieldStyle(.roundedBorder).disabled(validating)
                Text(
                    "Use a public HTTPS or webcal iCalendar link. We’ll connect to the source to check the feed. Adding a source here doesn’t subscribe you yet."
                )
                .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") {
                        validationTask?.cancel()
                        dismiss()
                    }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if validating { ProgressView().controlSize(.small) }
                    Button(validating ? "Checking…" : "Check & Add Source") {
                        validationTask = Task { await add() }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(
                        validating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || address.isEmpty)
                }
            }
            .padding(28).frame(width: 520)
            .onAppear { focused = true }
            .onDisappear { validationTask?.cancel() }
        #endif
    }

    private func add() async {
        validating = true
        error = nil
        defer { validating = false }
        do {
            let url = try FeedURL.validated(address)
            _ = try await store.client.preview(for: url)
            guard !Task.isCancelled else { return }
            store.addCustomFeed(name: name.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
            dismiss()
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
