import SwiftUI

struct UpcomingScreen: View {
    @EnvironmentObject var store: EventStore
    @State private var search = ""
    @State private var categories: Set<Category> = []

    private var list: [Event] { store.events(in: .all, categories: categories, search: search) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Category.allCases) { c in
                            let on = categories.contains(c)
                            Button {
                                if on { categories.remove(c) } else { categories.insert(c) }
                            } label: {
                                Label(c.label, systemImage: c.symbol)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(on ? c.color : Color(.secondarySystemBackground), in: Capsule())
                                    .foregroundStyle(on ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                EventList(events: list, emptyText: "No upcoming events match.")
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
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 4)
                }
            }
        }
    }
}
