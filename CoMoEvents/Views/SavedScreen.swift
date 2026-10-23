import SwiftUI

struct SavedScreen: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                EventCardList(events: store.favoriteEvents.filter { $0.effectiveEnd >= Date() },
                              emptyText: "Tap the heart on any event and it lands here.")
            }
            .navigationTitle("Saved")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AppearanceButton() } }
        }
    }
}
