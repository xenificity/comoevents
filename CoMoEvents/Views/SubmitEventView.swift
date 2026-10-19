import SwiftUI

struct SubmitEventView: View {
    @EnvironmentObject var community: CommunityStore
    @EnvironmentObject var account: AccountManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CommunityStore.Draft()
    @State private var sending = false
    @State private var message: String?
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event title", text: $draft.title)
                    Picker("Type", selection: $draft.category) {
                        ForEach(Category.allCases) { c in Label(c.label, systemImage: c.symbol).tag(c) }
                    }
                    DatePicker("Starts", selection: $draft.start, in: Date()...)
                    Toggle("Has an end time", isOn: $draft.hasEnd)
                    if draft.hasEnd { DatePicker("Ends", selection: $draft.end, in: draft.start...) }
                } header: { Text("What and when") }
                Section {
                    TextField("Venue (e.g. Cafe Berlin)", text: $draft.venue)
                    TextField("Address (optional if the venue is known)", text: $draft.address)
                } header: { Text("Where") } footer: { Text("We place the pin from this. Columbia, MO is assumed.") }
                Section {
                    TextField("Price (e.g. Free, $10)", text: $draft.price)
                    TextField("Link for tickets or details", text: $draft.link).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Tell people about it", text: $draft.details, axis: .vertical).lineLimit(3...8)
                } header: { Text("Details") }
                Section {
                    TextField("Your name or organization", text: $draft.submitterName)
                } header: { Text("Posted by") } footer: {
                    Text("Posts are checked by a human before they appear, usually within a day. No spam, no private parties, nothing illegal. Posts can be reported and removed.")
                }
            }
            .navigationTitle("Post an event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Post") { Task { await post() } }.fontWeight(.bold)
                            .disabled(draft.title.count < 3)
                    }
                }
            }
            .onAppear {
                if draft.submitterName.isEmpty { draft.submitterName = account.profile.displayName }
                draft.end = draft.start.addingTimeInterval(2 * 3600)
                Task { await community.prepare() }
            }
            .alert(done ? "Thanks!" : "Couldn't post", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil; if done { dismiss() } } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }

    private func post() async {
        sending = true
        let err = await community.submit(draft)
        sending = false
        if let err { message = err } else { done = true; message = "Your event is in. It shows up on the map once it's approved, usually within a day." }
    }
}

/// Moderator-only: approve or reject pending posts.
struct ModerationView: View {
    @EnvironmentObject var community: CommunityStore
    var body: some View {
        List {
            if community.pending.isEmpty { ContentUnavailableView("Nothing pending", systemImage: "checkmark.seal") }
            ForEach(community.pending, id: \.recordID) { r in
                let e = CommunityStore.event(from: r)
                VStack(alignment: .leading, spacing: 6) {
                    Text(e?.title ?? "?").font(.headline)
                    Text([e?.whenText, e?.placeText].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    if let d = e?.description, !d.isEmpty { Text(d).font(.footnote).lineLimit(4) }
                    if let o = e?.organizer { Text(o).font(.caption2).foregroundStyle(.secondary) }
                    HStack {
                        Button { Task { await community.setStatus(r, "approved") } } label: { Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.green)
                        Button(role: .destructive) { Task { await community.setStatus(r, "rejected") } } label: { Label("Reject", systemImage: "xmark").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Moderation")
        .task { await community.loadPending() }
        .refreshable { await community.loadPending() }
    }
}
