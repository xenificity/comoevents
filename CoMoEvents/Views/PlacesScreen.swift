import SwiftUI
import CoreLocation

/// One row of docs/places.json (scripts/build_places.py): everyday spots, open most days.
struct Place: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let address: String?
    let lat: Double
    let lng: Double
    let website: String?
    let phone: String?
    let blurb: String?
    let imageUrl: String?
    let tags: [String]?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var group: PlaceGroup { PlaceGroup(rawValue: category) ?? .fun }
    var directions: URL? {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: "\(lat),\(lng)"), URLQueryItem(name: "q", value: name)]
        return c.url
    }
}

enum PlaceGroup: String, CaseIterable, Identifiable {
    case fun, outdoors, culture, coffee, nightlife, shopping
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fun: return "Fun & games"
        case .outdoors: return "Parks & trails"
        case .culture: return "Museums & arts"
        case .coffee: return "Coffee & hangouts"
        case .nightlife: return "Bars & breweries"
        case .shopping: return "Shopping"
        }
    }
    var symbol: String {
        switch self {
        case .fun: return "gamecontroller.fill"
        case .outdoors: return "tree.fill"
        case .culture: return "building.columns.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .nightlife: return "wineglass.fill"
        case .shopping: return "bag.fill"
        }
    }
    var color: Color {
        switch self {
        case .fun: return Category.party.color
        case .outdoors: return Category.family.color
        case .culture: return Category.arts.color
        case .coffee: return Category.religious.color
        case .nightlife: return Category.nightlife.color
        case .shopping: return Category.sports.color
        }
    }
}

private struct PlacesFile: Codable { let places: [Place] }

/// The bundled places snapshot, refreshed from comoevent.com/places.json (rebuilt from Visit Columbia's directory).
@MainActor
final class PlacesStore: ObservableObject {
    static let shared = PlacesStore()
    @Published private(set) var places: [Place] = []
    private var loadedRemote = false

    private init() {
        if let u = Bundle.main.url(forResource: "places", withExtension: "json"),
           let d = try? Data(contentsOf: u), let f = try? JSONDecoder().decode(PlacesFile.self, from: d) { places = f.places }
    }

    func refresh() async {
        guard !loadedRemote, let u = URL(string: "https://comoevent.com/places.json") else { return }
        var req = URLRequest(url: u); req.timeoutInterval = 15; req.cachePolicy = .reloadRevalidatingCacheData
        if let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
           let f = try? JSONDecoder().decode(PlacesFile.self, from: d), !f.places.isEmpty {
            places = f.places; loadedRemote = true
        }
    }

    /// Upcoming events in the same building (within 35 m) or with the same name.
    static func events(at p: Place, in all: [Event]) -> [Event] {
        let here = CLLocation(latitude: p.lat, longitude: p.lng)
        let name = SmartSearch.norm(p.name)
        let now = Date()
        return all.filter { e in
            guard e.effectiveEnd >= now else { return false }
            if let c = e.coordinate, CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: here) < 35 { return true }
            let v = SmartSearch.norm(e.venue ?? "")
            return !v.isEmpty && (v == name || (v.count > 6 && name.contains(v)) || (name.count > 6 && v.contains(name)))
        }.sorted { $0.startDate < $1.startDate }
    }
}

struct PlacesScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var location: LocationManager
    @StateObject private var placesStore = PlacesStore.shared
    @State private var search = ""
    @State private var group: PlaceGroup? = nil
    @State private var tags: Set<String> = []
    private static let tagChips: [(String, String)] = [("free", "Free"), ("kids", "Kids"), ("indoor", "Indoors"), ("outdoor", "Outdoors"), ("dogs", "Dogs OK"), ("21+", "21+")]

    private var shown: [Place] {
        let q = SmartSearch.norm(search)
        return placesStore.places.filter { p in
            if let group, p.group != group { return false }
            if !tags.isSubset(of: Set(p.tags ?? [])) { return false }
            if q.isEmpty { return true }
            let hay = SmartSearch.norm("\(p.name) \(p.blurb ?? "") \(p.group.label) \((p.tags ?? []).joined(separator: " "))")
            return q.split(separator: " ").allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        chips
                        if shown.isEmpty {
                            ContentUnavailableView("Nothing here. Try another word or filter.", systemImage: "safari").padding(.top, 50)
                        }
                        ForEach(shown) { p in PlaceCard(place: p, events: PlacesStore.events(at: p, in: store.events)) }
                        Text("Places come from Visit Columbia's directory and our own list. Check hours before you go.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Places")
            .searchable(text: $search, prompt: "Bowling, trails, coffee, escape room…")
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AppearanceButton(inToolbar: true) } }
            .task { await placesStore.refresh() }
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(label: "All", symbol: "safari", color: Theme.gold, on: group == nil) { group = nil }
                    ForEach(PlaceGroup.allCases) { g in
                        chip(label: g.label, symbol: g.symbol, color: g.color, on: group == g) { group = group == g ? nil : g }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 4)
            }
            .padding(.horizontal, -16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.tagChips, id: \.0) { t in
                        let on = tags.contains(t.0)
                        Button {
                            SoundPlayer.tap(); if on { tags.remove(t.0) } else { tags.insert(t.0) }
                        } label: {
                            Text(t.1).font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(on ? Theme.ink : .primary)
                                .glass(Capsule(), tint: on ? Theme.yellow : nil, interactive: true)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 2)
            }
            .padding(.horizontal, -16)
        }
    }

    private func chip(label: String, symbol: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button { SoundPlayer.tap(); withAnimation(.snappy) { action() } } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(color, in: Circle())
                Text(label).font(.caption.weight(.bold))
            }
            .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 5)
            .foregroundStyle(on ? Theme.ink : .primary)
            .glass(Capsule(), tint: on ? Theme.yellow : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct PlaceCard: View {
    let place: Place
    let events: [Event]
    @Environment(\.openURL) private var openURL

    private static let tagLabels = ["free": "Free", "kids": "Kids", "indoor": "Indoors", "outdoor": "Outdoors", "dogs": "Dogs OK", "21+": "21+"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: place.group.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(place.group.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    Text(([place.group.label] + (place.tags ?? []).compactMap { Self.tagLabels[$0] }).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let b = place.blurb, !b.isEmpty { Text(b).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            if let a = place.address { Label(a, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                if let u = place.directions { pill("Directions", "car.fill") { Analytics.tap("place-directions"); openURL(u) } }
                if let w = place.website, let u = URL(string: w) { pill("Website", "safari") { openURL(u) } }
                if let p = place.phone, let u = URL(string: "tel://" + p.filter { $0.isNumber || $0 == "+" }) { pill("Call", "phone.fill") { openURL(u) } }
            }
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(events.count) event\(events.count == 1 ? "" : "s") coming up", systemImage: "sparkles").font(.caption.weight(.bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(events.prefix(6)) { e in NavigationLink(value: e) { MiniCard(event: e) }.buttonStyle(CardPressStyle()) }
                        }.padding(.horizontal, 16)
                    }.padding(.horizontal, -16)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 8)
                .glass(Capsule(), interactive: true)
        }.buttonStyle(.plain)
    }
}
