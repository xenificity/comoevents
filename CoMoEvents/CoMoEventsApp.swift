import SwiftUI
import CoreSpotlight

@main
struct CoMoEventsApp: App {
    @StateObject private var store = EventStore()
    @StateObject private var location = LocationManager()
    @StateObject private var account = AccountManager()
    @StateObject private var notifications = NotificationService.shared
    @StateObject private var community = CommunityStore()
    @StateObject private var friends = FriendsStore()
    @StateObject private var attendance = AttendanceStore()
    @StateObject private var router = Router()
    @StateObject private var usage = UsageCounter()

    @AppStorage("appearance") private var appearance = ""
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(ColorScheme.from(appearance: appearance))
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(account)
                .environmentObject(notifications)
                .environmentObject(community)
                .environmentObject(friends)
                .environmentObject(attendance)
                .environmentObject(router)
                .environmentObject(usage)
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
                    Analytics.appOpened()
                    // Siri / Shortcuts that open the app on a tab (CoMoIntents.swift)
                    switch UserDefaults.standard.string(forKey: "pendingTab") {
                    case "map": router.tab = .map
                    case "places": router.tab = .places
                    case "weekend": router.tab = .upcoming; router.pendingSearch = "this weekend"
                    case "freefood": router.tab = .upcoming; store.freeFoodOnly = true
                    default: break
                    }
                    UserDefaults.standard.removeObject(forKey: "pendingTab")
                }
        }
        // iOS wakes the app now and then (usually in the afternoon) to refresh tonight's pick.
        .backgroundTask(.appRefresh(NotificationService.refreshTaskID)) {
            await NotificationService.backgroundRefresh()
        }
    }

    private func launch() async {
        store.mergeFavorites(account.profile.favorites)
        store.onFavoritesChanged = { [weak account, weak notifications, weak store] ids in
            account?.setFavorites(ids)
            if let store, let notifications { Task { await notifications.reschedule(favorites: store.favoriteEvents, all: store.events) } }
        }
        notifications.onOpenEvent = { [weak router] id in router?.open(eventID: id) }
        notifications.onOpenWeekend = { [weak router] in router?.tab = .upcoming; router?.pendingSearch = "this weekend" }
        if let a = account.profile.audiencePick { store.audience = a }
        await store.loadIfNeeded()
        await account.restore()
        store.mergeFavorites(account.profile.favorites)
        await community.prepare()
        community.onApprovedChanged = { [weak store] posts in store?.communityEvents = posts }
        await community.loadApproved()
        store.communityEvents = community.approved
        // New community posts reach everyone within a minute: refresh while the app runs.
        Task { [weak community] in
            while true {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await community?.loadApproved()
            }
        }
        await friends.restore()
        attendance.onMineChanged = { [weak friends] m in friends?.update(attendance: m) }
        friends.update(attendance: attendance.mine)
        await attendance.prepare()
        await attendance.refreshCounts()
        // Tonight's pick is on by default with quiet (provisional) permission: no prompt.
        await notifications.ensureQuietPermission()
        NotificationService.scheduleBackgroundRefresh()
        await notifications.reschedule(favorites: store.favoriteEvents, all: store.events)
        #if DEBUG
        await notifications.debugFirePickSoon(all: store.events)
        await notifications.debugFireWeekendSoon(all: store.events)
        #endif
        let snapshot = store.events
        Task.detached(priority: .background) { SpotlightIndexer.index(snapshot) }
        await usage.register()
        await usage.refresh()
    }
}
