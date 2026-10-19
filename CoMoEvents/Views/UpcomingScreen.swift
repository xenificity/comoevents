import SwiftUI

struct UpcomingScreen: View {
    @EnvironmentObject var store: EventStore
    @State private var search = ""
    @State private var categories: Set<Category> = []

    private var list: [Event] { store.events(in: .all, categories: categories, search: search, audience: store.audience) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                EventCardList(events: list, emptyText: "Nothing matches. Try another filter.",
                              header: AnyView(VStack(spacing: 8) { AudienceBar(); chips }))
                    .refreshable { await store.refresh() }
            }
            .navigationTitle("Upcoming")
            .searchable(text: $search, prompt: "Search events or venues")
            .toolbar {
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
