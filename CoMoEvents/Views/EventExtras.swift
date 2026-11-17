import SwiftUI
import UIKit

// MARK: - Report a problem (feed events)

/// Wrong time, wrong place, cancelled or something else. One report changes nothing on its own:
/// the listing changes once 3 different people report the same thing (worker /report and /fixes).
struct ReportProblemView: View {
    let event: Event
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ExtrasAPI.ProblemKind = .time
    @State private var time = Date()
    @State private var place = ""
    @State private var other = ""
    @State private var sending = false
    @State private var error: String?
    var onDone: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("What is wrong with “\(event.title)”? We change the listing once **3 people** report the same thing, so one mistaken report can't break it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Problem", selection: $kind) {
                        ForEach(ExtrasAPI.ProblemKind.allCases) { k in Label(k.label, systemImage: k.symbol).tag(k) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                switch kind {
                case .time:
                    Section("Right start time") { DatePicker("Starts at", selection: $time, displayedComponents: .hourAndMinute) }
                case .place:
                    Section("Right place") { TextField("e.g. Rose Music Hall", text: $place).textInputAutocapitalization(.words) }
                case .other:
                    Section("What is wrong?") { TextField("A few words", text: $other) }
                case .cancelled:
                    EmptyView()
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else { Button("Send") { Task { await send() } }.disabled(!ready) }
                }
            }
            .onAppear { time = event.startDate }
        }
    }

    private var ready: Bool {
        switch kind {
        case .place: return place.trimmingCharacters(in: .whitespaces).count >= 3
        case .other: return !other.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func send() async {
        sending = true; error = nil
        defer { sending = false }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        let value: String = kind == .time ? f.string(from: time) : kind == .place ? place : kind == .other ? other : ""
        do {
            let r = try await ExtrasAPI.report(event, kind: kind, value: value.trimmingCharacters(in: .whitespaces))
            Analytics.tap("report-problem")
            dismiss()
            onDone(r.count >= r.needed ? "Thanks. 3 people agree, so it changes at the next update."
                                       : "Thanks. It changes once \(r.needed) people report the same thing (\(r.count) so far).")
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Who's in?

/// Card on the event page once you've sent an invite: who said they're in.
struct WhosInCard: View {
    let event: Event
    @ObservedObject private var invites = InviteStore.shared
    var onInviteMore: () -> Void

    var body: some View {
        if invites.byEvent[event.id] != nil {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill").foregroundStyle(Theme.gold).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    if let inv = invites.loaded[event.id] {
                        let ins = inv.guests.filter { $0.status == "in" }.map(\.name)
                        Text("Who's in: " + (ins.isEmpty ? "nobody yet" : ins.joined(separator: ", "))).font(.subheadline.weight(.semibold))
                        if inv.counts.maybe > 0 { Text("\(inv.counts.maybe) maybe").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("Who's in: checking…").font(.subheadline.weight(.semibold))
                    }
                }
                Spacer()
                Button("Invite more", action: onInviteMore).font(.caption.weight(.bold)).buttonStyle(.bordered).tint(Theme.gold)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: Theme.yellow.opacity(0.35))
            .task { await invites.refresh(event) }
        }
    }
}

/// Makes (or reuses) the invite link and returns the text to share.
@MainActor
enum WhosIn {
    static func shareText(for e: Event, host: String) async throws -> [Any] {
        let id: String
        if let have = InviteStore.shared.byEvent[e.id] { id = have }
        else {
            id = try await ExtrasAPI.createInvite(for: e, host: host).id
            InviteStore.shared.remember(id, for: e)
        }
        Analytics.tap("whos-in")
        let url = ExtrasAPI.inviteURL(id)
        var text = "Who's in? \(e.title), \(e.whenText)"
        if let v = e.venue { text += " at \(v)" }
        text += ". Tap to say you're in:"
        return [text, url]
    }
}

// MARK: - Instagram Story picture (1080 x 1920)

struct StoryCard: View {
    let event: Event
    var photo: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [event.kind.color, Color(red: 0.11, green: 0.10, blue: 0.20), Color(red: 0.06, green: 0.05, blue: 0.11)],
                           startPoint: .topLeading, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text("CoMo Events").font(.system(size: 46, weight: .heavy)).foregroundStyle(Theme.yellow)
                Text("Columbia, MO").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 60)
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.1)
                            Image(systemName: event.kind.symbol).font(.system(size: 200, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .frame(width: 900, height: 440).clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .padding(.bottom, 60)
                Text(event.whenText).font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 32).padding(.vertical, 18)
                    .background(Theme.yellow, in: Capsule())
                    .padding(.bottom, 40)
                Text(event.title).font(.system(size: 92, weight: .black)).foregroundStyle(.white)
                    .lineLimit(4).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
                if let v = event.venue {
                    Label(v, systemImage: "mappin").font(.system(size: 46, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2).padding(.top, 28)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Find it on CoMo Events").font(.system(size: 50, weight: .heavy)).foregroundStyle(.white)
                    Text("comoevent.com").font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.yellow)
                }
                .padding(44).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            }
            .padding(.horizontal, 90).padding(.top, 140).padding(.bottom, 140)
        }
        .frame(width: 1080, height: 1920)
    }
}

@MainActor
enum StoryShare {
    /// Renders the story picture, with the event photo when it loads within a few seconds.
    static func image(for e: Event) async -> UIImage? {
        var photo: UIImage?
        if let s = e.imageUrl, let u = URL(string: s) {
            var req = URLRequest(url: u); req.timeoutInterval = 6
            if let (d, _) = try? await URLSession.shared.data(for: req) { photo = UIImage(data: d) }
        }
        let r = ImageRenderer(content: StoryCard(event: e, photo: photo))
        r.scale = 1
        return r.uiImage
    }
}
