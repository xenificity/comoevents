import SwiftUI

struct SavedScreen: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        NavigationStack {
            EventList(events: store.favoriteEvents.filter { $0.effectiveEnd >= Date() },
                      emptyText: "Tap the heart on any event to keep it here.")
                .navigationTitle("Saved")
        }
    }
}
