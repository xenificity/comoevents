import Foundation
import CoreLocation

/// A cluster of events on the map. Built once per filter/zoom change (see MapScreen), not per render.
struct Hotspot: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let events: [Event]
    /// Most common category in the cluster; decides the pin colour and symbol.
    let dominant: Category
    /// Seasonal star emoji (🎃) when this is a cluster of starred events; nil for normal pins.
    var badge: String? = nil
    /// The place's name when every event here is at one venue (shown on the map, and as the sheet title).
    var placeName: String? = nil

    var count: Int { events.count }
    var title: String {
        if let p = placeName { return p }
        if Set(events.map(Hotspot.venueKey)).count > 1 { return "\(count) events nearby" }
        if let v = events.first?.venue, !v.isEmpty { return v }
        if let a = events.first?.address, !a.isEmpty { return a }
        return "\(count) events"
    }
    var isBusy: Bool { count >= 3 }
    /// Radius in meters for the busy-area halo.
    var haloRadius: CLLocationDistance { min(120 + Double(count) * 35, 420) }

    static func == (a: Hotspot, b: Hotspot) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    private struct Cell: Hashable { let x: Int; let y: Int; var venue = "" }

    /// The venue, or the street address when a source gives no venue name.
    static func placeLabel(_ e: Event) -> String? {
        if let v = e.venue, !v.isEmpty { return v }
        return e.address?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    static func venueKey(_ e: Event) -> String { String(SmartSearch.norm(placeLabel(e)).prefix(40)) }

    /// Groups events into grid cells of `cellDegrees`; with `byVenue` (zoomed in) each venue in a cell gets
    /// its own pin. Events without coordinates are skipped.
    static func build(from events: [Event], cellDegrees: Double = 0.002, byVenue: Bool = false) -> [Hotspot] {
        var buckets: [Cell: [Event]] = [:]
        for e in events {
            guard let lat = e.lat, let lng = e.lng else { continue }
            buckets[Cell(x: Int((lat / cellDegrees).rounded()), y: Int((lng / cellDegrees).rounded()),
                         venue: byVenue ? venueKey(e) : ""), default: []].append(e)
        }
        return buckets.map { cell, evs in
            var lat = 0.0, lng = 0.0
            var counts: [Category: Int] = [:]
            for e in evs { lat += e.lat!; lng += e.lng!; counts[e.kind, default: 0] += 1 }
            let sorted = evs.sorted { $0.startDate < $1.startDate }
            let dom = counts.max { $0.value < $1.value }?.key ?? .community
            let keys = Set(evs.map(venueKey))
            let place = keys.count == 1 && !(keys.first ?? "").isEmpty ? evs.first.flatMap(placeLabel) : nil
            // Identity includes the contents, so a filter change re-renders the pin.
            return Hotspot(id: "\(cell.x)_\(cell.y)_\(cell.venue)|\(sorted.count)|\(dom.rawValue)",
                           coordinate: CLLocationCoordinate2D(latitude: lat / Double(evs.count), longitude: lng / Double(evs.count)),
                           events: sorted, dominant: dom, placeName: place)
        }
        .sorted { $0.count > $1.count }
    }

    /// Normal clusters plus separate emoji pins for seasonal stars (Event.badge), clustered only with each other,
    /// so one Halloween event doesn't turn a big downtown arts cluster into a pumpkin.
    static func buildWithStars(from events: [Event], cellDegrees: Double = 0.002, byVenue: Bool = false) -> [Hotspot] {
        let stars = build(from: events.filter { $0.badge != nil }, cellDegrees: cellDegrees, byVenue: byVenue).map { h in
            Hotspot(id: "star|" + h.id, coordinate: h.coordinate, events: h.events, dominant: h.dominant, badge: h.events.first?.badge, placeName: h.placeName)
        }
        return build(from: events.filter { $0.badge == nil }, cellDegrees: cellDegrees, byVenue: byVenue) + stars
    }
}
