import SwiftUI
import AuthenticationServices

struct ProfileScreen: View {
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var notifications: NotificationService
    @EnvironmentObject var community: CommunityStore
    @EnvironmentObject var router: Router
    @EnvironmentObject var usage: UsageCounter
    @Environment(\.colorScheme) private var scheme
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var resetDone = false
    @State private var soundsOn = SoundPlayer.enabled
    @State private var countsOn = Analytics.enabled
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if !account.isSignedIn { signInCard }
                        aboutYou
                        interestsCard
                        notificationsCard
                        communityCard
                        savedCard
                        if account.isSignedIn { accountCard }
                        supportCard
                        idCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Profile")
            .onAppear { name = account.profile.displayName; Task { await community.prepare() } }
            .alert("Sign in", isPresented: Binding(get: { account.lastError != nil }, set: { if !$0 { account.lastError = nil } })) {
                Button("OK") { account.lastError = nil }
            } message: { Text(account.lastError ?? "") }
            .confirmationDialog("Delete your profile?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete profile and saved events", role: .destructive) {
                    Task { await account.deleteAccountData(); store.replaceFavorites([]) }
                }
            } message: {
                Text("Removes your name, interests and saved events from this device and from your iCloud. Events on the map are not affected.")
            }
        }
    }

    // MARK: sections

    private var header: some View {
        HStack(spacing: 14) {
            Text(account.profile.initials)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(width: 68, height: 68)
                .background(Theme.yellow.gradient, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                .shadow(color: Theme.yellow.opacity(0.5), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.profile.displayName.isEmpty ? "Hey there" : account.profile.displayName)
                    .font(.title2.bold())
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
                if let t = usage.text {
                    Label(t, systemImage: "person.2.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                }
            }
            Spacer()
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var statusLine: String {
        guard account.isSignedIn else { return "Not signed in · profile saved on this phone only" }
        switch account.sync {
        case .idle: return "Signed in with Apple"
        case .syncing: return "Syncing with iCloud…"
        case .synced: return "Signed in · synced with iCloud"
        case .unavailable(let m), .failed(let m): return m
        }
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep your profile", systemImage: "icloud.fill").font(.headline)
            Text("Sign in to save your name, interests and saved events to your iCloud, so they're there on your next phone. No password, no email list. You can also just keep using the app without an account.")
                .font(.subheadline).foregroundStyle(.secondary)
            SignInWithAppleButton(.continue) { req in
                req.requestedScopes = [.fullName]
            } onCompletion: { result in
                account.handle(result)
                name = account.profile.displayName
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About you").font(.headline)
            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .focused($nameFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glass(Capsule())
                .onSubmit { commitName() }
                .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
            Text("I'm usually out as…").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Audience.allCases) { a in
                    let on = account.profile.audiencePick == a
                    Button {
                        account.update { $0.audience = on ? nil : a.rawValue }
                        store.audience = on ? nil : a
                    } label: {
                        Label(a.label, systemImage: a.symbol)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .foregroundStyle(on ? Theme.ink : .primary)
                            .glass(Capsule(), tint: on ? Theme.yellow : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            }
            .padding(.horizontal, -16)
            .padding(.leading, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var interestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interests").font(.headline)
            Text("Pick what you're into. Upcoming gets a \"For you\" row from these.").font(.subheadline).foregroundStyle(.secondary)
            FlowChips(items: Category.allCases, selected: account.profile.interestSet) { c in
                account.update {
                    var set = $0.interestSet
                    if set.contains(c) { set.remove(c) } else { set.insert(c); TasteProfile.shared.seed([c.rawValue]) }
                    $0.interests = set.map(\.rawValue).sorted()
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Suggestions and search order also learn from what you save, go to and open. That stays on this iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Reset") {
                    TasteProfile.shared.reset()
                    TasteProfile.shared.seed(account.profile.interests)
                    resetDone = true
                }
                .font(.caption.weight(.bold))
                .disabled(resetDone)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications").font(.headline)
            Toggle(isOn: Binding(get: { notifications.remindersOn }, set: { on in Task { await setNotif(reminders: on, digest: nil) } })) {
                VStack(alignment: .leading) {
                    Text("Remind me before saved events").font(.subheadline.weight(.semibold))
                    Text("One hour before anything you've hearted.").font(.caption).foregroundStyle(.secondary)
                }
            }.tint(Theme.gold)
            Toggle(isOn: Binding(get: { notifications.digestOn }, set: { on in Task { await setNotif(reminders: nil, digest: on) } })) {
                VStack(alignment: .leading) {
                    Text("Tonight in CoMo").font(.subheadline.weight(.semibold))
                    Text("A 4 PM heads-up with what's on this evening.").font(.caption).foregroundStyle(.secondary)
                }
            }.tint(Theme.gold)
            if (notifications.remindersOn || notifications.digestOn) && !notifications.authorized {
                Text("Notifications are off for CoMo Events in Settings.").font(.caption).foregroundStyle(.red)
            }
            Toggle(isOn: $soundsOn) {
                VStack(alignment: .leading) {
                    Text("Sounds").font(.subheadline.weight(.semibold))
                    Text("A soft chime when the app opens and when you save an event. Follows the silent switch.").font(.caption).foregroundStyle(.secondary)
                }
            }.tint(Theme.gold)
            .onChange(of: soundsOn) { _, on in SoundPlayer.enabled = on; if on { SoundPlayer.shared.play(.favorite) } }
            Toggle(isOn: $countsOn) {
                VStack(alignment: .leading) {
                    Text("Anonymous usage counts").font(.subheadline.weight(.semibold))
                    Text("Adds your app opens and taps to the public stats at comoevent.com/stats. No name, no device ID.").font(.caption).foregroundStyle(.secondary)
                }
            }.tint(Theme.gold)
            .onChange(of: countsOn) { _, on in Analytics.enabled = on }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func setNotif(reminders: Bool?, digest: Bool?) async {
        if (reminders ?? false) || (digest ?? false) {
            if !notifications.authorized { _ = await notifications.requestAuthorization() }
        }
        if let reminders { notifications.remindersOn = reminders }
        if let digest { notifications.digestOn = digest }
        await notifications.reschedule(favorites: store.favoriteEvents, all: store.events)
    }

    private var communityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community").font(.headline)
            Button { router.showSubmit = true } label: {
                Label("Post an event", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(Theme.ink)
            Text("Student orgs, venues, anyone: post a public event and it appears on the map after a quick check.").font(.caption).foregroundStyle(.secondary)
            if community.isModerator {
                NavigationLink { ModerationView() } label: { Label("Moderation queue", systemImage: "checkmark.seal") }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Help & contact").font(.headline)
            Link(destination: URL(string: "mailto:xenificity@icloud.com?subject=CoMo%20Events%20feedback&body=What%20I%20liked%3A%0A%0AWhat%20was%20confusing%20or%20broken%3A%0A%0AEvents%20or%20places%20missing%3A%0A")!) {
                Label("Send feedback", systemImage: "bubble.left.and.text.bubble.right").frame(maxWidth: .infinity, alignment: .leading)
            }
            Link(destination: URL(string: "https://apps.apple.com/app/id6824363992?action=write-review")!) {
                Label("Rate CoMo Events on the App Store", systemImage: "star").frame(maxWidth: .infinity, alignment: .leading)
            }
            Link(destination: URL(string: "mailto:xenificity@icloud.com?subject=CoMo%20Events")!) {
                Label("Email us: xenificity@icloud.com", systemImage: "envelope").frame(maxWidth: .infinity, alignment: .leading)
            }
            Link(destination: URL(string: "https://comoevent.com/guidelines.html")!) {
                Label("Community guidelines", systemImage: "checkmark.shield").frame(maxWidth: .infinity, alignment: .leading)
            }
            Link(destination: URL(string: "https://comoevent.com/privacy.html")!) {
                Label("Privacy policy", systemImage: "lock").frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Events without a picture get one drawn from their details, with Twemoji art (CC-BY 4.0).")
                .font(.caption2).foregroundStyle(.secondary)
            if !community.blockedSubmitters.isEmpty {
                Button { community.unblockAll(); store.communityEvents = community.approved } label: {
                    Label("Unblock \(community.blockedSubmitters.count) blocked poster\(community.blockedSubmitters.count == 1 ? "" : "s")", systemImage: "hand.raised.slash").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Reports are read by a person, usually the same day. Blocking hides someone's posts for you right away.").font(.caption2).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var idCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your CoMo ID").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(community.userRecordName ?? "iCloud not signed in").font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let id = community.userRecordName {
                Button { UIPasteboard.general.string = id } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var savedCard: some View {
        let upcoming = store.favoriteEvents.filter { $0.effectiveEnd >= Date() }.count
        return HStack {
            Label("\(upcoming) saved event\(upcoming == 1 ? "" : "s") coming up", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: account.isSignedIn ? "icloud.fill" : "iphone")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account").font(.headline)
            Button {
                Task { await account.pull(); await account.push() }
            } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Button {
                account.signOut(keepLocal: true)
            } label: { Label("Sign out (keep profile on this phone)", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Button(role: .destructive) {
                confirmDelete = true
            } label: { Label("Delete my profile", systemImage: "trash").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Text("Your data: a name, interests and saved event ids, in your own iCloud. We run no server and keep no copy.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != account.profile.displayName else { return }
        account.update { $0.displayName = trimmed }
    }
}

/// Wrapping row of category chips.
struct FlowChips: View {
    let items: [Category]
    let selected: Set<Category>
    let toggle: (Category) -> Void

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    ForEach(rows[i]) { c in
                        let on = selected.contains(c)
                        Button { toggle(c) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: c.symbol).font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white).frame(width: 22, height: 22)
                                    .background(c.color, in: Circle())
                                Text(c.label).font(.caption.weight(.bold))
                            }
                            .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
                            .foregroundStyle(.primary)
                            .glass(Capsule(), tint: on ? c.color.opacity(0.6) : nil, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: on)
                    }
                }
            }
        }
    }
}
