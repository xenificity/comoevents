import SwiftUI
import PhotosUI
import VisionKit

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
    @State private var venueHint: String?
    @State private var venueTask: Task<Void, Never>?
    @State private var photoItem: PhotosPickerItem?
    @State private var flyerItem: PhotosPickerItem?
    @State private var showFlyerCamera = false
    @State private var scanning = false
    @State private var scanNote = false

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
                    HStack(spacing: 10) {
                        if VNDocumentCameraViewController.isSupported {
                            Button { showFlyerCamera = true } label: { Label("Scan flyer", systemImage: "doc.viewfinder").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(Theme.ink)
                        }
                        PhotosPicker(selection: $flyerItem, matching: .images) {
                            Label(VNDocumentCameraViewController.isSupported ? "Flyer photo" : "Scan flyer photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if prefilling { HStack { ProgressView(); Text("Reading the page…").font(.caption).foregroundStyle(.secondary) } }
                    if scanning { HStack { ProgressView(); Text("Reading the flyer…").font(.caption).foregroundStyle(.secondary) } }
                } header: { Text("Quick fill") } footer: { Text("Scan a flyer, a poster QR code, or paste an Eventbrite, Facebook or venue link: it fills in what it can, and the flyer becomes the event photo. You can edit everything after.") }
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
                        .autocorrectionDisabled()
                        .onChange(of: draft.venue) { _, v in lookupVenue(v) }
                    TextField("Address (optional if the venue is known)", text: $draft.address)
                } header: { Text("Where") } footer: {
                    Text(venueHint ?? "Type the venue and we fill in the address, phone and website from the venue table or Apple Maps. Columbia, MO is assumed.")
                }
                Section {
                    if let photo = draft.photo {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button { draft.photo = nil } label: { Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)) }
                                .buttonStyle(.plain).padding(6).accessibilityLabel("Remove photo")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(draft.photo == nil ? "Add a photo (optional)" : "Change photo", systemImage: "photo.badge.plus")
                    }
                } header: { Text("Photo") } footer: { Text("Shown on the event card and page. Without one, CoMo Events draws a cover from the details.") }
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
                    Link("Read the guidelines", destination: URL(string: "https://comoevent.com/guidelines.html")!).font(.subheadline)
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
                        Button("Post") { Analytics.tap("post-event"); Task { await post() } }.fontWeight(.bold)
                            .disabled(draft.title.count < 3 || !draft.agreedToGuidelines)
                    }
                }
            }
            .sheet(isPresented: $showScanner) { QRScanView { text in Task { await prefill(from: text) } } }
            .fullScreenCover(isPresented: $showFlyerCamera) {
                FlyerCamera { image in Task { await scanFlyer(image) } }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { draft.photo = img }; photoItem = nil }
            }
            .onChange(of: flyerItem) { _, item in
                guard let item else { return }
                Task { if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { await scanFlyer(img) }; flyerItem = nil }
            }
            .onAppear {
                if draft.submitterName.isEmpty { draft.submitterName = account.profile.displayName }
                if router.scanOnOpen { router.scanOnOpen = false; showScanner = true }
                draft.end = draft.start.addingTimeInterval(2 * 3600)
                Task { await community.prepare() }
            }
            .alert(done ? "Thanks!" : (scanNote ? "Flyer" : "Couldn't post"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil; scanNote = false; if done { dismiss() } } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }

    /// Smart fill: a venue name is enough; the address, website and pin come from the venue table or Apple Maps.
    private func lookupVenue(_ name: String) {
        venueTask?.cancel()
        let q = name.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { venueHint = nil; return }
        venueTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let m = await VenueLookup.find(q), !Task.isCancelled else { return }
            if draft.address.isEmpty, let a = m.address { draft.address = a }
            if draft.link.isEmpty, let w = m.website { draft.link = w }
            venueHint = "Found \(m.name)" + (m.address.map { " · \($0)" } ?? "") + (m.phone.map { " · \($0)" } ?? "") + (m.fromTable ? "" : " (Apple Maps)")
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

    /// Fill the form from a flyer photo; the flyer also becomes the event photo.
    private func scanFlyer(_ image: UIImage) async {
        scanning = true
        let r = await FlyerScanner.read(image)
        scanning = false
        Analytics.tap("scan-flyer")
        if draft.photo == nil { draft.photo = image }
        guard r.foundAnything else { scanNote = true; message = "Couldn't read that flyer. Try a sharper, straight-on photo, or fill the form by hand."; return }
        if !r.title.isEmpty { draft.title = String(r.title.prefix(120)) }
        if let s = r.start, s > Date() {
            draft.start = s
            if let e = r.end, e > s { draft.hasEnd = true; draft.end = e } else { draft.end = s.addingTimeInterval(2 * 3600) }
        }
        if !r.venue.isEmpty { draft.venue = r.venue }
        if !r.address.isEmpty && draft.address.isEmpty { draft.address = r.address }
        if !r.price.isEmpty { draft.price = r.price }
        if !r.link.isEmpty && draft.link.isEmpty { draft.link = r.link }
        if !r.details.isEmpty && draft.details.isEmpty { draft.details = r.details }
        if !r.venue.isEmpty { lookupVenue(r.venue) }
    }

    private func post() async {
        sending = true
        let err = await community.submit(draft)
        sending = false
        if let err { message = err } else { done = true; message = "Your event is in. It shows up on the map once it's approved, usually within a day." }
    }
}

/// VisionKit document camera: finds the flyer's edges and flattens it. Returns the first page.
struct FlyerCamera: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: FlyerCamera
        init(_ p: FlyerCamera) { parent = p }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let img = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            parent.dismiss()
            if let img { parent.onScan(img) }
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
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
