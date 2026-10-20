import SwiftUI
import CoreSpotlight

@main
struct CoMoEventsApp: App {
    @StateObject private var store = EventStore()
    @StateObject private var location = LocationManager()
    @StateObject private var account = AccountManager()
    @StateObject private var notifications = NotificationService()
    @StateObject private var community = CommunityStore()
    @StateObject private var friends = FriendsStore()
    @StateObject private var attendance = AttendanceStore()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(account)
                .environmentObject(notifications)
                .environmentObject(community)
                .environmentObject(friends)
                .environmentObject(attendance)
                .environmentObject(router)
                .task { await launch() }
                .onReceive(account.$profile) { p in
                    store.mergeFavorites(p.favorites)
                    friends.update(displayName: p.displayName, favorites: p.favorites)
                }
                .onOpenURL { router.handle(url: $0) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String { router.open(eventID: id) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    if UserDefaults.standard.string(forKey: "pendingTab") == "map" {
                        UserDefaults.standard.removeObject(forKey: "pendingTab"); router.tab = .map
                    }
                }
        }
    }

    private func launch() async {
        store.mergeFavorites(account.profile.favorites)
        store.onFavoritesChanged = { [weak account, weak notifications, weak store] ids in
            account?.setFavorites(ids)
            if let store, let notifications { Task { await notifications.reschedule(favorites: store.favoriteEvents, all: store.events) } }
        }
        notifications.onOpenEvent = { [weak router] id in router?.open(eventID: id) }
        if let a = account.profile.audiencePick { store.audience = a }
        await store.loadIfNeeded()
        await account.restore()
        store.mergeFavorites(account.profile.favorites)
        await community.prepare()
        await community.loadApproved()
        store.communityEvents = community.approved
        await friends.restore()
        attendance.onMineChanged = { [weak friends] m in friends?.update(attendance: m) }
        friends.update(attendance: attendance.mine)
        await attendance.prepare()
        await attendance.refreshCounts()
        await notifications.refreshAuthorization()
        await notifications.reschedule(favorites: store.favoriteEvents, all: store.events)
        let snapshot = store.events
        Task.detached(priority: .background) { SpotlightIndexer.index(snapshot) }
    }
}
