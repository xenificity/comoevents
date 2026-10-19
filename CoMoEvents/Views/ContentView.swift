import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }
            UpcomingScreen()
                .tabItem { Label("Upcoming", systemImage: "sparkles.rectangle.stack.fill") }
            SavedScreen()
                .tabItem { Label("Saved", systemImage: "heart.fill") }
                .badge(store.favoriteEvents.filter { $0.effectiveEnd >= Date() }.count)
        }
        .tint(Theme.gold)
    }
}
