import Foundation
import SwiftUI

/// Loads the event feed (bundled copy first, then the live copy) and keeps favorites.
@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [Event] = []
    @Published private(set) var generatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    /// Who-is-it-for filter, shared by the Map and Upcoming tabs.
    @Published var audience: Audience? = nil
    @Published private(set) var favorites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") }
    }

    /// Where the self-updating feed lives once the repo is on GitHub (Actions rebuilds it on a schedule).
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/xenificity/comoevents/main/feed/events.json")!

    private var loaded = false

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        loadBundled()
        await refresh()
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "events", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        apply(data)
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
            apply(data)
            lastError = nil
        } catch {
            lastError = "Offline; showing the last saved events."
        }
    }

    private func apply(_ data: Data) {
        do {
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            // Only replace if the new feed is at least as fresh.
            let newDate = Event.parse(feed.generatedAt)
            if let newDate, let old = generatedAt, newDate < old { return }
            events = feed.events.sorted { $0.startDate < $1.startDate }
            generatedAt = newDate
        } catch {
            lastError = "Could not read the feed: \(error.localizedDescription)"
        }
    }

    // MARK: favorites
    func isFavorite(_ e: Event) -> Bool { favorites.contains(e.id) }
    func toggleFavorite(_ e: Event) {
        if favorites.contains(e.id) { favorites.remove(e.id) } else { favorites.insert(e.id) }
    }
    var favoriteEvents: [Event] { events.filter { favorites.contains($0.id) } }

    // MARK: queries
    func events(in window: TimeWindow, categories: Set<Category> = [], search: String = "", audience: Audience? = nil) -> [Event] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return events.filter { e in
            window.contains(e)
            && e.suits(audience)
            && (categories.isEmpty || categories.contains(e.kind))
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

    var updatedText: String {
        guard let generatedAt else { return "" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return "Updated " + f.localizedString(for: generatedAt, relativeTo: Date())
    }
}
