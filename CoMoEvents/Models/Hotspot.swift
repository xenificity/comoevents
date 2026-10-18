import Foundation
import CoreLocation

/// A cluster of events at (roughly) the same place. Drives map pins and "busy area" circles.
struct Hotspot: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let events: [Event]

    var count: Int { events.count }
    var title: String {
        if let v = events.first?.venue, !v.isEmpty { return v }
        if let a = events.first?.address, !a.isEmpty { return a }
        return "\(count) events"
    }
    var dominant: Category {
        let counts = Dictionary(grouping: events, by: \.kind).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? .community
    }
    var isBusy: Bool { count >= 3 }
    /// Radius in meters for the busy-area halo.
    var haloRadius: CLLocationDistance { min(120 + Double(count) * 35, 420) }

    static func == (a: Hotspot, b: Hotspot) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Groups events into ~200 m cells. Events without coordinates are skipped.
    static func build(from events: [Event], cellDegrees: Double = 0.002) -> [Hotspot] {
        var buckets: [String: [Event]] = [:]
        for e in events {
            guard let c = e.coordinate else { continue }
            let key = "\(Int((c.latitude / cellDegrees).rounded()))_\(Int((c.longitude / cellDegrees).rounded()))"
            buckets[key, default: []].append(e)
        }
        return buckets.map { key, evs in
            let lat = evs.map { $0.lat! }.reduce(0, +) / Double(evs.count)
            let lng = evs.map { $0.lng! }.reduce(0, +) / Double(evs.count)
            return Hotspot(id: key, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                           events: evs.sorted { $0.startDate < $1.startDate })
        }
        .sorted { $0.count > $1.count }
    }
}
