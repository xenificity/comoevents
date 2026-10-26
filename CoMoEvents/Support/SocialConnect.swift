import Foundation
import CloudKit
import AuthenticationServices
import UIKit

/// Find friends through Facebook or Google contacts, via the comoevents-social Cloudflare Worker (social/ in
/// the repo). The phone hands the worker a CloudKit web-auth token (proves which iCloud user this is), the user
/// signs in to Facebook/Google in Apple's secure web sheet, and the worker returns friend profiles to add.
/// Nothing from Facebook or Google is stored on the phone.
@MainActor
final class SocialConnect: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    enum Provider: String, CaseIterable, Identifiable {
        case facebook, google
        var id: String { rawValue }
        var title: String { self == .facebook ? "Facebook friends" : "Google contacts" }
        var who: String { self == .facebook ? "Facebook friends" : "Google contacts" }
    }

    /// Worker address; empty hides the feature. Keep in step with window.SOCIAL_API in docs/ck-config.js.
    static let api = "https://comoevents-social.comoevent.workers.dev"
    /// Same public CloudKit API token the web app uses (restricted to comoevent.com origins).
    static let ckAPIToken = "ebf54f9ddaf48d86548cd8798feee69f76e47dee8a95df9cb865520ae2728a48"
    static var isConfigured: Bool { !api.isEmpty }

    @Published var working: Provider?
    /// Providers the server says are fully set up (from /health). Empty until checked.
    @Published private(set) var ready: [Provider] = []

    func checkReady() async {
        guard Self.isConfigured, let url = URL(string: "\(Self.api)/health"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let h = try? JSONDecoder().decode([String: Bool].self, from: data), h["cloudkit"] == true else { return }
        ready = Provider.allCases.filter { h[$0.rawValue] == true }
    }
    private var session: ASWebAuthenticationSession?

    func isConnected(_ p: Provider) -> Bool { UserDefaults.standard.object(forKey: "social.\(p.rawValue)") != nil }

    /// Returns a message for the user.
    func connect(_ p: Provider, friends: FriendsStore) async -> String {
        guard Self.isConfigured else { return "Facebook and Google sign-in aren't set up yet." }
        working = p; defer { working = nil }
        if !friends.enabled, !(await friends.enable()) { return friends.lastError ?? "Friends needs you signed in." }
        // Google/Facebook-account users are identified by their CoMo session, iCloud users by CloudKit.
        let ident: URLQueryItem
        if let s = CoMoAPI.session { ident = URLQueryItem(name: "session", value: s) }
        else if let token = await Self.ckWebAuthToken() { ident = URLQueryItem(name: "ck", value: token) }
        else { return "Couldn't confirm your account. Check that iCloud is signed in." }
        var c = URLComponents(string: "\(Self.api)/auth/\(p.rawValue)/start")!
        c.queryItems = [ident, URLQueryItem(name: "return", value: "comoevents://social")]
        guard let url = c.url else { return "Couldn't start sign-in." }
        let callback: URL
        do { callback = try await authenticate(url) } catch { return "Sign-in was cancelled." }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "social_error" })?.value { return "Not connected: \(err)" }
        guard let id = items.first(where: { $0.name == "social" })?.value else { return "Couldn't finish connecting." }
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "\(Self.api)/result/\(id)")!)
            let res = try JSONDecoder().decode(Result.self, from: data)
            UserDefaults.standard.set(Date(), forKey: "social.\(p.rawValue)")
            let added = await friends.add(recordNames: res.matches.map(\.recordName))
            if added > 0 { return "Added \(added) friend\(added == 1 ? "" : "s") from your \(p.who)." }
            if res.linkedUsers > 0 { return "Your \(p.who) on CoMo Events haven't turned on Friends yet. They'll appear when they do." }
            return "Connected. None of your \(p.who) use CoMo Events yet. Invite them, and check again later."
        } catch { return "Couldn't finish connecting. Try again." }
    }

    func disconnect(_ p: Provider) async -> String {
        guard Self.isConfigured else { return "Couldn't confirm your account." }
        var body = ["provider": p.rawValue]
        if let s = CoMoAPI.session { body["session"] = s }
        else if let token = await Self.ckWebAuthToken() { body["ck"] = token }
        else { return "Couldn't confirm your account." }
        var req = URLRequest(url: URL(string: "\(Self.api)/unlink")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(body)
        guard (try? await URLSession.shared.data(for: req)) != nil else { return "Couldn't disconnect. Try again." }
        UserDefaults.standard.removeObject(forKey: "social.\(p.rawValue)")
        objectWillChange.send()
        return "Disconnected \(p == .facebook ? "Facebook" : "Google")."
    }

    private struct Result: Decodable {
        struct Match: Decodable { let recordName: String; let displayName: String }
        let provider: String; let checked: Int; let linkedUsers: Int; let matches: [Match]
    }

    /// CloudKit web auth token for this iPhone's iCloud user (the worker checks it with CloudKit).
    static func ckWebAuthToken() async -> String? {
        await withCheckedContinuation { cont in
            let op = CKFetchWebAuthTokenOperation(apiToken: Self.ckAPIToken)
            op.qualityOfService = .userInitiated
            op.fetchWebAuthTokenResultBlock = { result in
                if case .success(let t) = result { cont.resume(returning: t) } else { cont.resume(returning: nil) }
            }
            CKContainer(identifier: AccountManager.containerID).privateCloudDatabase.add(op)
        }
    }

    private func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "comoevents") { callback, error in
                if let callback { cont.resume(returning: callback) } else { cont.resume(throwing: error ?? URLError(.cancelled)) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            s.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
