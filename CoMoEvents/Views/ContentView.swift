import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            MapScreen().tabItem { Label("Map", systemImage: "map.fill") }.tag(AppTab.map)
            UpcomingScreen().tabItem { Label("Upcoming", systemImage: "sparkles.rectangle.stack.fill") }.tag(AppTab.upcoming)
            SavedScreen().tabItem { Label("Saved", systemImage: "heart.fill") }
                .badge(store.favoriteEvents.filter { $0.effectiveEnd >= Date() }.count).tag(AppTab.saved)
            FriendsScreen().tabItem { Label("Friends", systemImage: "person.2.fill") }.tag(AppTab.friends)
            ProfileScreen().tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }.tag(AppTab.profile)
        }
        .tint(Theme.gold)
        .sheet(isPresented: $router.showSubmit) { SubmitEventView() }
        .sheet(item: Binding(get: { router.pendingEventID.flatMap { id in store.events.first { $0.id == id } } },
                             set: { if $0 == nil { router.pendingEventID = nil } })) { e in
            NavigationStack { EventDetailView(event: e) }
        }
    }
}
