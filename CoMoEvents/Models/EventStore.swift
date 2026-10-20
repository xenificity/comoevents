import Foundation
import SwiftUI

/// Loads the event feed (bundled copy first, then the live copy) and keeps favorites.
@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [Event] = []
    private var feedEvents: [Event] = []
    /// Approved community posts, merged into `events`.
    var communityEvents: [Event] = [] { didSet { recombine() } }
    private func recombine() {
        let ids = Set(feedEvents.map(\.id))
        events = (feedEvents + communityEvents.filter { !ids.contains($0.id) }).sorted { $0.startDate < $1.startDate }
    }
    @Published private(set) var generatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    /// Who-is-it-for filter, shared by the Map and Upcoming tabs.
    @Published var audience: Audience? = nil
    @Published private(set) var favorites: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(favorites), forKey: "favorites")
            onFavoritesChanged?(favorites)
        }
    }
    /// AccountManager listens here to mirror favorites into the profile (and iCloud when signed in).
    var onFavoritesChanged: ((Set<String>) -> Void)?

    func mergeFavorites(_ ids: [String]) {
        let merged = favorites.union(ids)
        if merged != favorites { favorites = merged }
    }
    func replaceFavorites(_ ids: [String]) { favorites = Set(ids) }

    /// Where the self-updating feed lives once the repo is on GitHub (Actions rebuilds it on a schedule).
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/xenificity/comoevents/main/feed/events.json")!

    private var loaded = false

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        await loadBundled()
        await refresh()
    }

    private func loadBundled() async {
        guard let url = Bundle.main.url(forResource: "events", withExtension: "json") else { return }
        if let (feed, data) = await Self.decode(from: url) { apply(feed, data: data) }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        var req = URLRequest(url: Self.remoteURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "Live feed not published yet; showing the bundled snapshot."
                return
            }
            guard let feed = await Self.decode(data) else {
                lastError = "Could not read the live feed; showing the last saved events."
                return
            }
            apply(feed, data: data)
            lastError = nil
        } catch {
            lastError = "Offline; showing the last saved events."
        }
    }

    /// JSON decoding of ~1,000 events takes a noticeable slice of a second; keep it off the main thread.
    nonisolated private static func decode(_ data: Data) async -> Feed? {
        await Task.detached(priority: .userInitiated) { try? JSONDecoder().decode(Feed.self, from: data) }.value
    }
    nonisolated private static func decode(from url: URL) async -> (Feed, Data)? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url), let feed = try? JSONDecoder().decode(Feed.self, from: data) else { return nil }
            return (feed, data)
        }.value
    }

    private func apply(_ feed: Feed, data: Data) {
        // Only replace if the new feed is at least as fresh.
        let newDate = Event.parse(feed.generatedAt)
        if let newDate, let old = generatedAt, newDate < old { return }
        feedEvents = feed.events
        generatedAt = newDate
        recombine()
        FeedCache.save(data)
    }

    // MARK: favorites
    func isFavorite(_ e: Event) -> Bool { favorites.contains(e.id) }
    func toggleFavorite(_ e: Event) {
        if favorites.contains(e.id) { favorites.remove(e.id) } else { favorites.insert(e.id); SoundPlayer.shared.play(.favorite) }
    }
    var favoriteEvents: [Event] { events.filter { favorites.contains($0.id) } }

    // MARK: queries
    func events(in window: TimeWindow, categories: Set<Category> = [], search: String = "", audience: Audience? = nil) -> [Event] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let now = Date()
        return events.filter { e in
            window.contains(e, now: now)
            && e.suits(audience)
            && e.belongs(to: categories)
            && (q.isEmpty || e.title.lowercased().contains(q) || (e.venue ?? "").lowercased().contains(q))
        }
    }

    var upcoming: [Event] { events.filter { $0.effectiveEnd >= Date() } }

    /// Upcoming events grouped by calendar day, in order.
    func groupedByDay(_ list: [Event]) -> [(day: Date, events: [Event])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: list) { cal.startOfDay(for: $0.startDate) }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.startDate < $1.startDate }) }
    }

    private static let relative: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f }()
    var updatedText: String {
        guard let generatedAt else { return "" }
        return "Updated " + Self.relative.localizedString(for: generatedAt, relativeTo: Date())
    }
}
