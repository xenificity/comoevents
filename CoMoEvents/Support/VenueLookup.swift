import Foundation
import MapKit

/// Fills in what a poster leaves out. Given a venue name it returns the address, coordinates, phone
/// and website, first from the bundled venue table (feed/venues.json, the same one the aggregator
/// uses), then from Apple Maps (MKLocalSearch around Columbia). No account, no paid API.
enum VenueLookup {
    struct Match {
        let name: String
        let address: String?
        let phone: String?
        let website: String?
        let coordinate: CLLocationCoordinate2D?
        let fromTable: Bool
    }

    private struct Row: Decodable {
        let aliases: [String]?
        let address: String?
        let lat: Double?
        let lng: Double?
        let phone: String?
        let website: String?
    }

    private static let table: [String: Row] = {
        guard let url = Bundle.main.url(forResource: "venues", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([String: Row].self, from: data) else { return [:] }
        return rows
    }()

    private static let columbia = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.9517, longitude: -92.3341),
                                                     latitudinalMeters: 20_000, longitudinalMeters: 20_000)

    /// Exact name or alias in the venue table.
    static func fromTable(_ name: String) -> Match? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.count >= 3 else { return nil }
        for (vname, row) in table {
            let aliases = (row.aliases ?? []).map { $0.lowercased() }
            if key == vname.lowercased() || aliases.contains(key) || (key.count > 4 && vname.lowercased().contains(key)) {
                let coord = (row.lat != nil && row.lng != nil) ? CLLocationCoordinate2D(latitude: row.lat!, longitude: row.lng!) : nil
                let addr = row.address.map { $0.contains("MO") ? $0 : "\($0), Columbia, MO" }
                return Match(name: vname, address: addr, phone: row.phone, website: row.website, coordinate: coord, fromTable: true)
            }
        }
        return nil
    }

    /// A known venue named anywhere in free text (a scanned flyer). Longest name or alias wins.
    static func mentioned(in text: String) -> Match? {
        let t = text.lowercased()
        var best: (len: Int, name: String)?
        for (vname, row) in table {
            for cand in [vname] + (row.aliases ?? []) where cand.count >= 5 && t.contains(cand.lowercased()) {
                if cand.count > (best?.len ?? 0) { best = (cand.count, vname) }
            }
        }
        return best.flatMap { fromTable($0.name) }
    }

    /// Table first, then Apple Maps.
    static func find(_ name: String) async -> Match? {
        if let m = fromTable(name) { return m }
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return nil }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.region = columbia
        req.resultTypes = .pointOfInterest
        guard let resp = try? await MKLocalSearch(request: req).start() else { return nil }
        // Apple Maps treats the region as a hint; keep only places actually near Columbia.
        let center = CLLocation(latitude: columbia.center.latitude, longitude: columbia.center.longitude)
        guard let item = resp.mapItems.first(where: {
            CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude).distance(from: center) < 40_000
        }) else { return nil }
        let pm = item.placemark
        let parts = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [pm.locality, pm.administrativeArea, pm.postalCode].compactMap { $0 }.joined(separator: " ")
        let address = [parts, city].filter { !$0.isEmpty }.joined(separator: ", ")
        return Match(name: item.name ?? q, address: address.isEmpty ? nil : address, phone: item.phoneNumber,
                     website: item.url?.absoluteString, coordinate: pm.coordinate, fromTable: false)
    }

    /// Community posts carry only what the poster typed; add the venue's phone, site and pin when the venue is known.
    static func enrich(_ e: Event) -> Event {
        guard e.isCommunity, let v = e.venue, let m = fromTable(v) else { return e }
        return Event(id: e.id, source: e.source, sourceName: e.sourceName, title: e.title, start: e.startDate, end: e.endDate,
                     allDay: e.allDay, venue: e.venue, address: e.address ?? m.address,
                     lat: e.lat ?? m.coordinate?.latitude, lng: e.lng ?? m.coordinate?.longitude,
                     url: e.url ?? m.website, ticketUrl: e.ticketUrl, phone: e.phone ?? m.phone, price: e.price,
                     category: e.category, categories: e.categories, imageUrl: e.imageUrl, description: e.description,
                     organizer: e.organizer, audience: e.audience, submitterID: e.submitterID)
    }
}
