import SwiftUI

/// Day-grouped card list used by Upcoming and Saved.
struct EventCardList: View {
    @EnvironmentObject var store: EventStore
    let events: [Event]
    var emptyText: String = "No events."
    var header: AnyView? = nil

    var body: some View {
        let groups = store.groupedByDay(events)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: .sectionHeaders) {
                if let header { header }
                if events.isEmpty {
                    ContentUnavailableView(emptyText, systemImage: "sparkles")
                        .padding(.top, 60)
                }
                ForEach(groups, id: \.day) { g in
                    Section {
                        ForEach(g.events) { e in
                            NavigationLink(value: e) { EventCard(event: e) }
                                .buttonStyle(CardPressStyle())
                        }
                    } header: {
                        HStack {
                            Text(EventList.header(for: g.day))
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .glass(Capsule())
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
    }
}

/// Plain grouped rows, used in the hotspot sheet.
struct EventList: View {
    @EnvironmentObject var store: EventStore
    let events: [Event]
    var emptyText: String = "No events."

    var body: some View {
        let groups = store.groupedByDay(events)
        List {
            if events.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "calendar.badge.exclamationmark")
                    .listRowSeparator(.hidden)
            }
            ForEach(groups, id: \.day) { g in
                Section(EventList.header(for: g.day)) {
                    ForEach(g.events) { e in
                        NavigationLink(value: e) { EventRow(event: e) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
    }

    static func header(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: day)
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
