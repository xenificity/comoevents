import Foundation
import UIKit

/// Anonymous visit and tap counts for the public stats page (comoevent.com/stats/).
///
/// Each count is one GoatCounter request with a path such as "/ios/open", "ios-event/<id>" or
/// "click/directions". No cookies, no device or user identifier, nothing stored on the phone.
/// GoatCounter turns the request's internet address into a country/state and keeps no address.
/// The web map sends the same paths, so the dashboard adds both together. Off switch: Profile.
@MainActor
enum Analytics {
    private static let endpoint = "https://comoevent.goatcounter.com/count"
    private static var lastOpen: Date?

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "analytics.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "analytics.enabled") }
    }

    /// Counted once per visit: again only after the app has been away for 30 minutes.
    static func appOpened() {
        if let last = lastOpen, Date().timeIntervalSince(last) < 1800 { return }
        lastOpen = Date()
        send(path: "/ios/open", title: "iPhone app opened", event: false)
    }

    static func eventOpened(_ e: Event) {
        send(path: "ios-event/\(e.id)", title: e.title + (e.venue.map { " · \($0)" } ?? ""), event: true)
    }

    /// Same names as the web map: directions, save, going, here, went, share, calendar, tickets, post-event.
    /// Every tracked button press also ticks (saving has its own sound).
    static func tap(_ name: String) {
        if name != "save" { SoundPlayer.tap() }
        send(path: "click/\(name)", title: name, event: true)
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    private static var userAgent: String {
        // A browser-style agent so GoatCounter files the visit under iOS rather than as a bot.
        let os = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(os) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 CoMoEvents/\(app)"
    }

    private static func send(path: String, title: String, event: Bool) {
        guard enabled, var c = URLComponents(string: endpoint) else { return }
        c.queryItems = [
            URLQueryItem(name: "p", value: path),
            URLQueryItem(name: "t", value: title),
            URLQueryItem(name: "e", value: event ? "true" : "false"),
            URLQueryItem(name: "r", value: "iPhone app"),
            URLQueryItem(name: "rnd", value: String(Int.random(in: 0..<1_000_000_000))),
        ]
        guard let url = c.url else { return }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req).resume()
    }
}
