import SwiftUI

@main
struct CoMoEventsApp: App {
    @StateObject private var store = EventStore()
    @StateObject private var location = LocationManager()
    @StateObject private var account = AccountManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(account)
                .task {
                    // Profile <-> favorites: the profile is the durable copy, the store is the live one.
                    store.mergeFavorites(account.profile.favorites)
                    store.onFavoritesChanged = { [weak account] ids in account?.setFavorites(ids) }
                    if let a = account.profile.audiencePick { store.audience = a }
                    await store.loadIfNeeded()
                    await account.restore()
                    store.mergeFavorites(account.profile.favorites)
                }
                .onReceive(account.$profile) { p in
                    // Cloud pull may bring favorites from another device.
                    store.mergeFavorites(p.favorites)
                }
        }
    }
}
