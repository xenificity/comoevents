import SwiftUI
import StoreKit

struct ContentView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var router: Router
    @Environment(\.requestReview) private var requestReview

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
        .onAppear { SoundPlayer.shared.play(.welcome) }
        .onChange(of: router.tab) { _, _ in SoundPlayer.tap() }
        .onChange(of: store.favorites.count) { old, new in askForRatingIfDue(old: old, new: new) }
        .sheet(isPresented: $router.showSubmit) { SubmitEventView() }
        .sheet(item: Binding(get: { router.pendingEventID.flatMap { id in store.events.first { $0.id == id } } },
                             set: { if $0 == nil { router.pendingEventID = nil } })) { e in
            NavigationStack { EventDetailView(event: e) }
        }
    }

    /// Ask for an App Store rating once, the moment someone saves their third event:
    /// they have just found the app useful. Only a single tap counts (not a cloud sync on launch).
    /// iOS decides whether the prompt actually shows, and never shows it in TestFlight builds.
    private func askForRatingIfDue(old: Int, new: Int) {
        let key = "review.askedAfterThirdSave"
        guard new >= 3, new == old + 1, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // let the heart animation finish
            requestReview()
        }
    }
}
