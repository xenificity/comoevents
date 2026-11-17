import SwiftUI

struct SavedScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var router: Router

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                EventCardList(events: store.favoriteEvents.filter { $0.effectiveEnd >= Date() },
                              emptyText: "Tap the heart on any event and it lands here.")
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.showFriends = true } label: { Label("Friends", systemImage: "person.2.fill") }
                        .accessibilityLabel("Friends")
                }
                ToolbarItem(placement: .topBarTrailing) { AppearanceButton(inToolbar: true) }
            }
        }
    }
}
