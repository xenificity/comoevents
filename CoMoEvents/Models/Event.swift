import Foundation
import CoreLocation
import SwiftUI

/// One row of feed/events.json. Produced by feed/aggregate.py.
struct Event: Codable, Identifiable, Hashable {
    let id: String
    let source: String
    let sourceName: String
    let title: String
    let start: String
    let end: String?
    let allDay: Bool
    let timeTBD: Bool
    let venue: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let url: String?
    let ticketUrl: String?
    let phone: String?
    let price: String?
    let category: String
    let imageUrl: String?
    let description: String?
    let organizer: String?
    let alsoOn: [String]?
    let audience: [String]

    // Parsed once at decode time; not part of the JSON.
    private(set) var startDate: Date = .distantPast
    private(set) var endDate: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, source, sourceName, title, start, end, allDay, timeTBD, venue, address, lat, lng
        case url, ticketUrl, phone, price, category, imageUrl, description, organizer, alsoOn, audience
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(String.self, forKey: .start)
        end = try c.decodeIfPresent(String.self, forKey: .end)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        timeTBD = try c.decodeIfPresent(Bool.self, forKey: .timeTBD) ?? false
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lng = try c.decodeIfPresent(Double.self, forKey: .lng)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        ticketUrl = try c.decodeIfPresent(String.self, forKey: .ticketUrl)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        price = try c.decodeIfPresent(String.self, forKey: .price)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "community"
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer)
        alsoOn = try c.decodeIfPresent([String].self, forKey: .alsoOn)
        audience = try c.decodeIfPresent([String].self, forKey: .audience) ?? []
        startDate = Event.parse(start) ?? .distantPast
        endDate = end.flatMap(Event.parse)
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static func parse(_ s: String) -> Date? {
        isoFull.date(from: s) ?? isoFrac.date(from: s)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Best guess at when the event stops being "happening now".
    var effectiveEnd: Date { endDate ?? startDate.addingTimeInterval(allDay ? 86_400 : 3 * 3600) }

    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && effectiveEnd >= now
    }

    var kind: Category { Category(rawValue: category) ?? .community }
    var audiences: [Audience] { audience.compactMap(Audience.init(rawValue:)) }
    func suits(_ a: Audience?) -> Bool { a == nil || audience.contains(a!.rawValue) }

    var whenText: String {
        if timeTBD || allDay { return Event.dayFormatter.string(from: startDate) + (allDay ? " · All day" : " · Time TBD") }
        var s = Event.dayTimeFormatter.string(from: startDate)
        if let endDate, Calendar.current.isDate(endDate, inSameDayAs: startDate) {
            s += " – " + Event.timeFormatter.string(from: endDate)
        }
        return s
    }
    var timeText: String {
        if allDay { return "All day" }
        if timeTBD { return "Time TBD" }
        return Event.timeFormatter.string(from: startDate)
    }
    var placeText: String {
        [venue, address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var primaryLink: URL? { URL(string: ticketUrl ?? url ?? "") }
    var infoLink: URL? { URL(string: url ?? "") }
    var telURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter(\.isNumber)
        return digits.count >= 10 ? URL(string: "tel://\(digits)") : nil
    }

    static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    static let dayTimeFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d · h:mm a"; return f }()
    static let timeFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
}

struct Feed: Codable {
    let generatedAt: String
    let count: Int?
    let withCoordinates: Int?
    let events: [Event]
}

enum Category: String, CaseIterable, Identifiable {
    case music, sports, arts, family, food, nightlife, campus, community
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .sports: return "sportscourt"
        case .arts: return "theatermasks"
        case .family: return "figure.2.and.child.holdinghands"
        case .food: return "fork.knife"
        case .nightlife: return "moon.stars"
        case .campus: return "graduationcap"
        case .community: return "person.3"
        }
    }
    var color: Color {
        switch self {
        case .music: return .pink
        case .sports: return .orange
        case .arts: return .purple
        case .family: return .green
        case .food: return .red
        case .nightlife: return .indigo
        case .campus: return .yellow
        case .community: return .blue
        }
    }
}

/// "Who is it for" filter. Tags come from feed/aggregate.py (keyword rules + category defaults).
enum Audience: String, CaseIterable, Identifiable {
    case singles, couples, groups, family
    var id: String { rawValue }
    var label: String {
        switch self {
        case .singles: return "Singles"
        case .couples: return "Couples"
        case .groups: return "Groups"
        case .family: return "Family"
        }
    }
    var symbol: String {
        switch self {
        case .singles: return "person.fill"
        case .couples: return "heart.fill"
        case .groups: return "person.3.fill"
        case .family: return "figure.2.and.child.holdinghands"
        }
    }
}
