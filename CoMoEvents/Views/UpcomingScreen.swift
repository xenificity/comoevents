import SwiftUI

struct UpcomingScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var router: Router
    @State private var search = ""
    @State private var categories: Set<Category> = []

    private var list: [Event] { store.events(in: .all, categories: categories, search: search, audience: store.audience) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                EventCardList(events: list, emptyText: "Nothing matches. Try another filter.",
                              header: AnyView(VStack(spacing: 8) { AudienceBar(); chips; forYou }))
                    .refreshable { await store.refresh() }
            }
            .navigationTitle("Upcoming")
            .searchable(text: $search, prompt: "Search events or venues")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.showSubmit = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Post an event")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isRefreshing { ProgressView() } else {
                        Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
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
        let interests = account.profile.interestSet
        let picks = interests.isEmpty ? [] : Array(store.events(in: .week, categories: interests, audience: store.audience).prefix(10))
        if !picks.isEmpty && search.isEmpty && categories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.gold)
                    Text("For you").font(.headline)
                    Text("· from your interests").font(.caption).foregroundStyle(.secondary)
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
                        withAnimation(.snappy) { if on { categories.remove(c) } else { categories.insert(c) } }
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
