import SwiftUI

@main
struct CoMoEventsApp: App {
    @StateObject private var store = EventStore()
    @StateObject private var location = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                .task { await store.loadIfNeeded() }
        }
    }
}
