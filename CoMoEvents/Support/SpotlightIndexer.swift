import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Puts every upcoming event into Spotlight so "blue note" or "farmers market" finds it from the home screen.
enum SpotlightIndexer {
    static let domain = "events"

    static func index(_ events: [Event]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items: [CSSearchableItem] = events.prefix(1500).map { e in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = e.title
            a.contentDescription = [e.whenText, e.venue].compactMap { $0 }.joined(separator: " · ")
            a.keywords = [e.kind.label, e.venue ?? "", "Columbia", "CoMo", "event"].filter { !$0.isEmpty }
            a.startDate = e.startDate
            a.endDate = e.endDate
            a.namedLocation = e.venue
            if let lat = e.lat, let lng = e.lng { a.latitude = NSNumber(value: lat); a.longitude = NSNumber(value: lng) }
            let item = CSSearchableItem(uniqueIdentifier: e.id, domainIdentifier: domain, attributeSet: a)
            item.expirationDate = e.effectiveEnd.addingTimeInterval(3600)
            return item
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }
}
