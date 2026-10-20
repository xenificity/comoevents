import SwiftUI

struct SubmitEventView: View {
    @EnvironmentObject var community: CommunityStore
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CommunityStore.Draft()
    @State private var sending = false
    @State private var message: String?
    @State private var done = false
    @State private var showScanner = false
    @State private var prefilling = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Button { showScanner = true } label: { Label("Scan QR code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(Theme.ink)
                        Button { Task { await prefill(from: UIPasteboard.general.string ?? "") } } label: { Label("Paste link", systemImage: "link").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                    if prefilling { HStack { ProgressView(); Text("Reading the page…").font(.caption).foregroundStyle(.secondary) } }
                } header: { Text("Quick fill") } footer: { Text("A poster QR code or an Eventbrite, Facebook or venue link fills in what it can. You can edit everything after.") }
                Section {
                    TextField("Event title", text: $draft.title)
                    Picker("Type", selection: $draft.category) {
                        ForEach(Category.allCases) { c in Label(c.label, systemImage: c.symbol).tag(c) }
                    }
                    NavigationLink {
                        List(Category.allCases.filter { $0 != draft.category }) { c in
                            Button {
                                if draft.extraCategories.contains(c) { draft.extraCategories.remove(c) } else { draft.extraCategories.insert(c) }
                            } label: {
                                HStack { Label(c.label, systemImage: c.symbol); Spacer(); if draft.extraCategories.contains(c) { Image(systemName: "checkmark").foregroundStyle(Theme.gold) } }
                            }.foregroundStyle(.primary)
                        }
                        .navigationTitle("Also show under")
                    } label: {
                        HStack { Text("Also show under"); Spacer(); Text(draft.extraCategories.isEmpty ? "None" : draft.extraCategories.map(\.label).sorted().joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1) }
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
                } header: { Text("Posted by") }
                Section {
                    Toggle(isOn: $draft.agreedToGuidelines) {
                        Text("I agree to the community guidelines").font(.subheadline.weight(.semibold))
                    }.tint(Theme.gold)
                    Link("Read the guidelines", destination: URL(string: "https://xenificity.github.io/comoevents/guidelines.html")!).font(.subheadline)
                } footer: {
                    Text("Public events only. No spam, no hate, no adult content, no private parties, nothing illegal. A moderator checks every post before it appears, usually within a day. Posts can be reported, hidden and removed, and repeat offenders are blocked. Questions: xenificity@icloud.com")
                }
            }
            .navigationTitle("Post an event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Post") { Task { await post() } }.fontWeight(.bold)
                            .disabled(draft.title.count < 3 || !draft.agreedToGuidelines)
                    }
                }
            }
            .sheet(isPresented: $showScanner) { QRScanView { text in Task { await prefill(from: text) } } }
            .onAppear {
                if draft.submitterName.isEmpty { draft.submitterName = account.profile.displayName }
                if router.scanOnOpen { router.scanOnOpen = false; showScanner = true }
                draft.end = draft.start.addingTimeInterval(2 * 3600)
                Task { await community.prepare() }
            }
            .alert(done ? "Thanks!" : "Couldn't post", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil; if done { dismiss() } } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }

    private func prefill(from text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { message = "Nothing to read. Copy a link first."; return }
        if t.hasPrefix("comoevents://") { message = "That's a CoMo Events link to an event that's already in the app."; return }
        guard t.lowercased().hasPrefix("http") else { draft.details = t; return }
        prefilling = true
        let r = await LinkPrefill.fetch(t)
        prefilling = false
        draft.link = r.link
        if !r.title.isEmpty && draft.title.isEmpty { draft.title = r.title }
        if let s = r.start, s > Date() { draft.start = s; if let e = r.end { draft.hasEnd = true; draft.end = e } }
        if !r.venue.isEmpty && draft.venue.isEmpty { draft.venue = r.venue }
        if !r.address.isEmpty && draft.address.isEmpty { draft.address = r.address }
        if !r.details.isEmpty && draft.details.isEmpty { draft.details = r.details }
        draft.category = Category(rawValue: "community") ?? .community
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
