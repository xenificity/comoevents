import SwiftUI

struct UpcomingScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var router: Router
    @EnvironmentObject var attendance: AttendanceStore
    @State private var search = ""
    @State private var categories: Set<Category> = []
    // Cached: filtering the whole feed on every keystroke redraw was a visible hang.
    @State private var list: [Event] = []
    @State private var picks: [Event] = []
    /// Set while searching: "Best matches · Hindu temple".
    @State private var rankedTitle: String? = nil
    @State private var personalPicks = false

    private var inputs: String {
        "\(search)|\(categories.map(\.rawValue).sorted().joined())|\(store.audience?.rawValue ?? "")|\(store.events.count)|\(store.generatedAt?.timeIntervalSince1970 ?? 0)|\(account.profile.interests.sorted().joined())|\(store.favorites.count)|\(attendance.mine.count)"
    }
    private func recompute() {
        let smart = SmartSearch.shared
        let going: (Event) -> Int = { attendance.count(for: $0).going }
        let base = store.events(in: .all, categories: categories, audience: store.audience)
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty && smart.ready {
            let r = smart.search(q, in: base, going: going)
            list = r.hits.map(\.event)
            var got = r.parsed.units.filter { $0.concepts != nil }.map(\.label)
            if let t = r.parsed.time { got.append(["today": "Today", "tomorrow": "Tomorrow", "weekend": "This weekend"][t] ?? t) }
            rankedTitle = "Best matches" + (got.isEmpty ? "" : " · " + got.joined(separator: " · "))
        } else {
            list = smart.rankWithinDays(q.isEmpty ? base : store.events(in: .all, categories: categories, search: q, audience: store.audience), going: going)
            rankedTitle = nil
        }
        // Best of the next 7 days for this person: quality + what they save, attend and open (+ interests).
        let now = Date()
        var seen = Set<String>()
        picks = store.events(in: .week, audience: store.audience)
            .filter { $0.startDate >= now || $0.isHappeningNow }
            .map { (e: $0, r: smart.baseRank($0, going: going($0)) + TasteProfile.shared.personal($0)) }
            .sorted { $0.r > $1.r }
            .filter { seen.insert(SmartSearch.norm($0.e.title)).inserted }
            .prefix(10).map(\.e)
        personalPicks = TasteProfile.shared.hasTaste
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                EventCardList(events: list,
                              emptyText: rankedTitle == nil ? "Nothing matches. Try another filter." : "Nothing found. Try a simpler word, like music, church or tech.",
                              header: AnyView(VStack(spacing: 8) { AudienceBar(); chips; forYou }),
                              rankedTitle: rankedTitle)
                    .refreshable { await store.refresh() }
            }
            .navigationTitle("Upcoming")
            .searchable(text: $search, prompt: "Search anything: tech, temple, jazz, free…")
            .onAppear { TasteProfile.shared.seed(account.profile.interests); recompute() }
            .onChange(of: inputs) { _, _ in recompute() }
            .onReceive(router.$pendingSearch.compactMap { $0 }) { q in search = q; router.pendingSearch = nil }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { router.showSubmit = true } label: { Label("Post an event", systemImage: "square.and.pencil") }
                        Button { router.showSubmit = true; router.scanOnOpen = true } label: { Label("Scan a QR code", systemImage: "qrcode.viewfinder") }
                    } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Post an event")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isRefreshing { ProgressView() } else {
                        Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { AppearanceButton() }
            }
            .safeAreaInset(edge: .bottom) {
                if let err = store.lastError {
                    Text(err).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glass(Capsule())
                        .padding(.bottom, 4)
                }
            }
        }
    }

    /// Events in the next week that match the profile's interests. Hidden when there are no interests.
    @ViewBuilder private var forYou: some View {
        if !picks.isEmpty && search.isEmpty && categories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.gold)
                    Text(personalPicks ? "For you" : "Popular this week").font(.headline)
                    if personalPicks { Text("· from what you save and go to").font(.caption).foregroundStyle(.secondary) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(picks) { e in
                            NavigationLink(value: e) { MiniCard(event: e) }
                                .buttonStyle(CardPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
            .padding(.top, 4)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.allCases) { c in
                    let on = categories.contains(c)
                    Button {
                        SoundPlayer.tap(); withAnimation(.snappy) { if on { categories.remove(c) } else { categories.insert(c) } }
                    } label: {
                        Label(c.label, systemImage: c.symbol)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(on ? Theme.ink : .primary)
                            .glass(Capsule(), tint: on ? Theme.yellow : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: on)
                }
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, -16)
        .padding(.leading, 16)
    }
}
