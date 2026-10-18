import SwiftUI

/// Day-grouped list used by the map sheet, Upcoming and Saved.
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

struct EventRow: View {
    @EnvironmentObject var store: EventStore
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(event.kind.color.gradient, in: RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.timeText).font(.caption.weight(.semibold)).foregroundStyle(event.kind.color)
                    if event.isHappeningNow {
                        Text("NOW").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.red, in: Capsule()).foregroundStyle(.white)
                    }
                    if let p = event.price { Text(p).font(.caption).foregroundStyle(.secondary) }
                }
                Text(event.title).font(.subheadline.weight(.medium)).lineLimit(2)
                if let v = event.venue ?? event.address {
                    Text(v).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                store.toggleFavorite(event)
            } label: {
                Image(systemName: store.isFavorite(event) ? "heart.fill" : "heart")
                    .foregroundStyle(store.isFavorite(event) ? .red : .secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isFavorite(event) ? "Remove from saved" : "Save")
        }
        .padding(.vertical, 2)
    }
}
