import SwiftUI

enum AppTab: Hashable { case map, upcoming, places, saved, profile }

/// Cross-screen navigation: which tab is up, and an event to open (from Spotlight, a link, a notification or Siri).
@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .map
    @Published var pendingEventID: String?
    @Published var showSubmit = false
    /// Friends moved under Saved (Places took its tab): opens as a sheet.
    @Published var showFriends = false
    /// comoevents://freefood turns the Free food filter on; comoevents://gameday opens the game day plan.
    @Published var pendingFreeFood = false
    @Published var showGameDay = false
    /// When the submit sheet opens, start with the QR scanner.
    @Published var scanOnOpen = false
    /// comoevents://upcoming?q=jazz opens Upcoming with that search.
    @Published var pendingSearch: String?

    func open(eventID: String) { pendingEventID = eventID }

    func handle(url: URL) {
        guard url.scheme == "comoevents" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "event": if let id = parts.first { open(eventID: id) }
        case "map": tab = .map
        case "submit": showSubmit = true
        case "friends": tab = .saved; showFriends = true
        case "places": tab = .places
        case "freefood": tab = .upcoming; pendingFreeFood = true
        case "gameday": tab = .map; showGameDay = true
        case "weekend": tab = .upcoming; pendingSearch = "this weekend"
        case "upcoming":
            tab = .upcoming
            pendingSearch = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        default: break
        }
    }
}
