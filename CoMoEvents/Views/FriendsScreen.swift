import SwiftUI

struct FriendsScreen: View {
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var store: EventStore
    @State private var code = ""
    @State private var message: String?
    @State private var working = false
    @State private var showContacts = false
    @State private var smsTargets: [String]?
    @StateObject private var social = SocialConnect()

    var body: some View {
        content.task { await social.checkReady() }
    }

    private var content: some View {
        NavigationStack {
            ZStack {
                Theme.page
                ScrollView {
                    VStack(spacing: 16) {
                        if !friends.enabled { intro; socialCard } else { myCard; socialCard; addCard; list }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Friends")
            .refreshable { await friends.refresh() }
            .alert("Friends", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
            .sheet(isPresented: $showContacts) {
                ContactPicker { targets in
                    showContacts = false
                    let phones = targets.filter { !$0.contains("@") }
                    if !phones.isEmpty, MessageComposer.canSend { smsTargets = phones }
                    else if !targets.isEmpty { UIPasteboard.general.string = AppLinks.inviteText(friendCode: friends.myCode); message = "Invite text copied. Paste it into a message to \(targets.joined(separator: ", "))." }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(get: { smsTargets != nil }, set: { if !$0 { smsTargets = nil } })) {
                if let t = smsTargets { MessageComposer(recipients: t, body: AppLinks.inviteText(friendCode: friends.myCode)).ignoresSafeArea() }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Go together", systemImage: "person.2.fill").font(.headline)
            Text("Turn on Friends to get a 6-letter code. Swap codes with people, and you'll see which saved events you have in common and who's going where. Sharing your own saved events is a separate switch, off by default.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                Task { working = true; if await friends.enable() == false { message = friends.lastError }; working = false }
            } label: { Label(working ? "Setting up…" : "Turn on Friends", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(Theme.ink).disabled(working)
            Text("Uses the iCloud account on this iPhone. Nothing else is shared.").font(.caption2).foregroundStyle(.secondary)
            inviteButton
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var myCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your code").font(.headline)
            HStack {
                Text(friends.myCode ?? "······").font(.system(size: 34, weight: .heavy, design: .rounded)).kerning(4)
                Spacer()
                ShareLink(item: AppLinks.inviteText(friendCode: friends.myCode)) {
                    Image(systemName: "square.and.arrow.up").font(.title3).padding(10).glass(Circle(), interactive: true)
                }
                Button { UIPasteboard.general.string = friends.myCode; message = "Code copied." } label: {
                    Image(systemName: "doc.on.doc").font(.title3).padding(10).glass(Circle(), interactive: true)
                }.buttonStyle(.plain)
            }
            inviteButton
            Toggle(isOn: $friends.shareSaves) {
                VStack(alignment: .leading) {
                    Text("Share my saved events with friends").font(.subheadline.weight(.semibold))
                    Text("Friends who have your code see what you've hearted.").font(.caption).foregroundStyle(.secondary)
                }
            }.tint(Theme.gold)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Invite people who don't have the app yet: install link, plus your code once Friends is on.
    private var inviteButton: some View {
        VStack(spacing: 10) {
        Button { showContacts = true } label: {
            Label("Invite from Contacts", systemImage: "person.crop.circle.badge.plus")
                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .glass(Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        ShareLink(item: AppLinks.inviteText(friendCode: friends.enabled ? friends.myCode : nil)) {
            Label("Invite friends", systemImage: "person.badge.plus")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.primary)
                .overlay(Capsule().stroke(Theme.gold, lineWidth: 1.5))
                .glass(Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var socialCard: some View {
        if SocialConnect.isConfigured && !social.ready.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Find friends you know", systemImage: "person.2.fill").font(.headline)
                Text("Connect \(social.ready.map { $0 == .facebook ? "Facebook" : "your Google contacts" }.joined(separator: " or ")) to add friends who already use CoMo Events. We keep only a scrambled ID, never your friend list or contacts.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(social.ready) { p in
                    HStack {
                        Button {
                            Task { message = await social.connect(p, friends: friends) }
                        } label: {
                            HStack {
                                if social.working == p { ProgressView().tint(Theme.ink) }
                                Text((social.isConnected(p) ? "Check again: " : "Connect ") + p.title).fontWeight(.bold)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10).background(Theme.yellow, in: Capsule()).foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain).disabled(social.working != nil)
                        if social.isConnected(p) {
                            Button("Disconnect") { Task { message = await social.disconnect(p) } }.font(.subheadline)
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var addCard: some View {
        HStack {
            TextField("Friend's code", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .rounded).weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 10).glass(Capsule())
            Button {
                Task { working = true; if let err = await friends.add(code: code) { message = err } else { code = "" }; working = false }
            } label: { Text("Add").fontWeight(.bold).padding(.horizontal, 16).padding(.vertical, 10).background(Theme.yellow, in: Capsule()).foregroundStyle(Theme.ink) }
                .buttonStyle(.plain).disabled(code.count < 6 || working)
        }
    }

    @ViewBuilder private var list: some View {
        if friends.friends.isEmpty {
            ContentUnavailableView("No friends yet", systemImage: "person.badge.plus", description: Text("Add someone's code above."))
                .padding(.top, 30)
        } else {
            ForEach(friends.friends) { f in
                let going = store.events.filter { f.favorites.contains($0.id) && $0.effectiveEnd >= Date() }.sorted { $0.startDate < $1.startDate }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(f.name.prefix(1).uppercased()).font(.headline).foregroundStyle(Theme.ink).frame(width: 36, height: 36).background(Theme.yellow, in: Circle())
                        VStack(alignment: .leading) {
                            Text(f.name).font(.headline)
                            Text(f.sharing ? "\(going.count) upcoming saved" : "Not sharing saves").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Remove") { friends.remove(f) }
                            Button("Report name", role: .destructive) { Task { message = (await friends.report(f, reason: "Offensive or impersonating name")) ?? "Thanks. A moderator will take a look." } }
                            Button("Block", role: .destructive) { friends.block(f) }
                        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                    }
                    ForEach(going.prefix(5)) { e in
                        NavigationLink(value: e) { EventRow(event: e) }.buttonStyle(.plain)
                    }
                }
                .padding(16)
                .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
        }
    }
}
