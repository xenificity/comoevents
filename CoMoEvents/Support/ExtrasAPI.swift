import Foundation

/// Version 1.3 calls to our worker (social/src/index.js) that need no sign-in:
/// - problem reports on feed events (a change only happens once 3 different people agree)
/// - "Who's in?" invites: a link friends open in any browser to say they're in
enum ExtrasAPI {
    static var base: String {
        #if DEBUG
        // Testing against `wrangler dev`: SIMCTL_CHILD_WORKER_URL=http://localhost:8799
        if let s = ProcessInfo.processInfo.environment["WORKER_URL"] { return s }
        #endif
        return SocialConnect.api
    }

    /// A random id for this iPhone. It counts as one person for reports and invites and is not linked to
    /// the person's account, name or Apple ID.
    static var anonymousID: String {
        if let id = UserDefaults.standard.string(forKey: "como.anon") { return id }
        let id = "i-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)
        UserDefaults.standard.set(id, forKey: "como.anon")
        return id
    }

    struct APIError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private static func send(_ path: String, method: String = "POST", body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.timeoutInterval = 20
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(message: msg ?? "Couldn't reach CoMo Events. Try again.")
        }
        return data
    }

    // MARK: problem reports

    enum ProblemKind: String, CaseIterable, Identifiable {
        case time, place, cancelled, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .time: return "Wrong time"
            case .place: return "Wrong place"
            case .cancelled: return "Cancelled or not happening"
            case .other: return "Something else"
            }
        }
        var symbol: String {
            switch self {
            case .time: return "clock.badge.exclamationmark"
            case .place: return "mappin.slash"
            case .cancelled: return "xmark.circle"
            case .other: return "questionmark.bubble"
            }
        }
    }

    /// Returns how many different people have reported the same thing, and how many it takes.
    static func report(_ e: Event, kind: ProblemKind, value: String) async throws -> (count: Int, needed: Int) {
        let data = try await send("/report", body: ["event": e.id, "kind": kind.rawValue, "value": value,
                                                   "reporter": anonymousID, "title": e.title])
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return ((obj["count"] as? Int) ?? 1, (obj["needed"] as? Int) ?? 3)
    }

    // MARK: Who's in? invites

    struct Invite: Decodable {
        struct Guest: Decodable, Identifiable { let name: String; let status: String; var id: String { name + status } }
        struct Counts: Decodable { let `in`: Int; let maybe: Int }
        let event: String
        let title: String
        let start: String
        let venue: String?
        let host: String
        let guests: [Guest]
        let counts: Counts
    }

    static func createInvite(for e: Event, host: String) async throws -> (id: String, url: URL) {
        let data = try await send("/invite", body: ["event": e.id, "title": e.title, "start": e.start,
                                                   "venue": e.venue ?? "", "host": host, "guest": anonymousID])
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let id = obj["id"] as? String, let u = (obj["url"] as? String).flatMap(URL.init(string:)) else {
            throw APIError(message: "Couldn't make the invite. Try again.")
        }
        return (id, u)
    }

    static func invite(_ id: String) async throws -> Invite {
        try JSONDecoder().decode(Invite.self, from: try await send("/invite/\(id)", method: "GET"))
    }

    static func inviteURL(_ id: String) -> URL { URL(string: "https://comoevent.com/in/?i=\(id)")! }
}

/// Invites this iPhone made, by event id (kept on the phone).
@MainActor
final class InviteStore: ObservableObject {
    static let shared = InviteStore()
    @Published private(set) var byEvent: [String: String] {
        didSet { UserDefaults.standard.set(byEvent, forKey: "como.invites") }
    }
    @Published private(set) var loaded: [String: ExtrasAPI.Invite] = [:]
    private init() { byEvent = UserDefaults.standard.dictionary(forKey: "como.invites") as? [String: String] ?? [:] }

    func remember(_ id: String, for event: Event) { byEvent[event.id] = id }

    func refresh(_ event: Event) async {
        guard let id = byEvent[event.id] else { return }
        if let inv = try? await ExtrasAPI.invite(id) { loaded[event.id] = inv }
    }
}
