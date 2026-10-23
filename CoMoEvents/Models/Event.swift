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
    /// All categories the event belongs to, primary first. Feed events can have several.
    let categories: [String]
    /// iCloud user record name of the poster, community posts only. Used for blocking.
    var submitterID: String? = nil

    // Parsed once at decode time; not part of the JSON.
    private(set) var startDate: Date = .distantPast
    private(set) var endDate: Date? = nil
    /// Every category this event belongs to, primary first. Resolved once; filters call this a lot.
    private(set) var kinds: [Category] = []

    enum CodingKeys: String, CodingKey {
        case id, source, sourceName, title, start, end, allDay, timeTBD, venue, address, lat, lng
        case url, ticketUrl, phone, price, category, imageUrl, description, organizer, alsoOn, audience, categories
    }

    /// Last line of defence against source junk like "<p> $6 </p>" or "&amp;": strips tags, decodes
    /// common entities, joins lines with "; " (unless keepLines) and drops placeholders like "N/A".
    static func plain(_ s: String?, keepLines: Bool = false) -> String? {
        guard var t = s, !t.isEmpty else { return nil }
        if t.contains("<") || t.contains("&") {
            t = t.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</li>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            for (k, v) in ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'",
                           "&lt;": "<", "&gt;": ">", "&ndash;": "–", "&mdash;": "—", "&rsquo;": "’", "&lsquo;": "‘",
                           "&ldquo;": "“", "&rdquo;": "”", "&hellip;": "…"] {
                t = t.replacingOccurrences(of: k, with: v)
            }
        }
        let lines = t.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        t = lines.joined(separator: keepLines ? "\n" : "; ")
        if t.range(of: "^(?i)(n/?a|none|tbd|tba|-+)?$", options: .regularExpression) != nil { return nil }
        return t
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        title = Event.plain(try c.decode(String.self, forKey: .title)) ?? ""
        start = try c.decode(String.self, forKey: .start)
        end = try c.decodeIfPresent(String.self, forKey: .end)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        timeTBD = try c.decodeIfPresent(Bool.self, forKey: .timeTBD) ?? false
        venue = Event.plain(try c.decodeIfPresent(String.self, forKey: .venue))
        address = Event.plain(try c.decodeIfPresent(String.self, forKey: .address))
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lng = try c.decodeIfPresent(Double.self, forKey: .lng)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        ticketUrl = try c.decodeIfPresent(String.self, forKey: .ticketUrl)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        price = Event.plain(try c.decodeIfPresent(String.self, forKey: .price))
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "community"
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        description = Event.plain(try c.decodeIfPresent(String.self, forKey: .description), keepLines: true)
        organizer = Event.plain(try c.decodeIfPresent(String.self, forKey: .organizer))
        alsoOn = try c.decodeIfPresent([String].self, forKey: .alsoOn)
        audience = try c.decodeIfPresent([String].self, forKey: .audience) ?? []
        let extra = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        categories = extra.isEmpty ? [category] : (extra.contains(category) ? extra : [category] + extra)
        startDate = Event.parse(start) ?? .distantPast
        endDate = end.flatMap(Event.parse)
        kinds = categories.compactMap(Category.init(rawValue:))
    }

    /// Memberwise init for events that don't come from the JSON feed (community submissions).
    init(id: String, source: String, sourceName: String, title: String, start: Date, end: Date?, allDay: Bool = false,
         venue: String?, address: String?, lat: Double?, lng: Double?, url: String?, ticketUrl: String? = nil, phone: String? = nil,
         price: String?, category: String, categories: [String] = [], imageUrl: String? = nil, description: String?, organizer: String?, audience: [String] = [],
         submitterID: String? = nil) {
        self.id = id; self.source = source; self.sourceName = sourceName; self.title = title
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        self.start = f.string(from: start); self.end = end.map { f.string(from: $0) }
        self.allDay = allDay; self.timeTBD = false
        self.venue = venue; self.address = address; self.lat = lat; self.lng = lng
        self.url = url; self.ticketUrl = ticketUrl; self.phone = phone; self.price = price
        self.category = category; self.imageUrl = imageUrl; self.description = description; self.organizer = organizer
        self.categories = categories.isEmpty ? [category] : (categories.contains(category) ? categories : [category] + categories)
        self.alsoOn = nil; self.audience = audience
        self.submitterID = submitterID
        self.startDate = start; self.endDate = end
        self.kinds = self.categories.compactMap(Category.init(rawValue:))
    }

    var isCommunity: Bool { source == "community" }
    /// Stable link for sharing and Spotlight: opens the app on this event.
    var deepLink: URL { URL(string: "comoevents://event/\(id)")! }
    var shareText: String {
        var s = "\(title) · \(whenText)"
        if let v = venue { s += " · \(v)" }
        if let u = url { s += "\n\(u)" }
        s += "\nFound on CoMo Events, free for iPhone: \(AppLinks.install(campaign: "share").absoluteString)"
        return s
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

    var kind: Category { kinds.first ?? .community }
    func belongs(to set: Set<Category>) -> Bool { set.isEmpty || kinds.contains { set.contains($0) } }
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
    case party, music, nightlife, food, arts, sports, family, campus, community
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .party: return "party.popper.fill"
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
        case .party: return Color(red: 1.0, green: 0.25, blue: 0.55)
        case .music: return Color(red: 0.55, green: 0.3, blue: 1.0)
        case .sports: return .orange
        case .arts: return Color(red: 0.0, green: 0.7, blue: 0.75)
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
