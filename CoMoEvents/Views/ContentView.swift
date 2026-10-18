import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
            UpcomingScreen()
                .tabItem { Label("Upcoming", systemImage: "calendar") }
            SavedScreen()
                .tabItem { Label("Saved", systemImage: "heart") }
                .badge(store.favoriteEvents.filter { $0.effectiveEnd >= Date() }.count)
        }
    }
}
