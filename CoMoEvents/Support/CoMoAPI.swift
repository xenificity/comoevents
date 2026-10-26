import Foundation
import AuthenticationServices
import UIKit

/// Our small backend, the Cloudflare worker at `SocialConnect.api` (source: social/src/index.js):
/// - Sign in with Google or Facebook (a CoMo account alongside Sign in with Apple)
/// - photo hosting for event photos and profile pictures
/// - writes for Google/Facebook-account users, who have no iCloud identity in CloudKit
///   (Going, friend profile, posts, reports). iCloud users keep writing to CloudKit directly.
@MainActor
enum CoMoAPI {
    static var base: String { SocialConnect.api }

    // MARK: account session

    struct Account: Codable, Equatable {
        var id: String
        var provider: String          // "google" | "facebook"
        var name: String?
        var email: String?
        var providerLabel: String { provider == "facebook" ? "Facebook" : "Google" }
    }

    /// Signed session token from the worker (180 days), kept in the Keychain.
    static var session: String? { Keychain.read("como.session") }
    static var account: Account? {
        get { UserDefaults.standard.data(forKey: "como.account").flatMap { try? JSONDecoder().decode(Account.self, from: $0) } }
        set {
            if let newValue, let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: "como.account") }
            else { UserDefaults.standard.removeObject(forKey: "como.account") }
        }
    }
    static func signOut() { Keychain.delete("como.session"); account = nil }

    struct LoginResult: Decodable {
        struct Acct: Decodable { let id: String; let provider: String; let name: String?; let email: String?; let profile: RemoteProfile? }
        let token: String
        let account: Acct
    }
    struct RemoteProfile: Codable {
        var displayName: String?; var interests: [String]?; var audience: String?; var favorites: [String]?
        var avatarUrl: String?; var updatedAt: Double?
    }

    /// Runs the provider sign-in in a secure browser sheet and stores the session. Returns the remote profile.
    static func signIn(_ provider: String) async throws -> RemoteProfile? {
        var c = URLComponents(string: "\(base)/login/\(provider)/start")!
        c.queryItems = [URLQueryItem(name: "client", value: "ios"), URLQueryItem(name: "return", value: "comoevents://login")]
        let callback = try await WebAuth.run(c.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "login_error" })?.value { throw APIError(message: err) }
        guard let rid = items.first(where: { $0.name == "login" })?.value else { throw APIError(message: "Sign-in didn't finish.") }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/result/\(rid)")!)
        let r = try JSONDecoder().decode(LoginResult.self, from: data)
        Keychain.write("como.session", r.token)
        account = Account(id: r.account.id, provider: r.account.provider, name: r.account.name, email: r.account.email)
        return r.account.profile
    }

    // MARK: calls

    struct APIError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Our session if signed in with Google/Facebook, else this iPhone's iCloud user (CloudKit web auth token).
    static func authHeader() async -> String? {
        if let s = session { return "Bearer " + s }
        if let t = await SocialConnect.ckWebAuthToken() { return "CK " + t }
        return nil
    }

    @discardableResult
    static func call(_ path: String, method: String = "POST", json body: [String: Any]? = nil) async throws -> Data {
        guard let auth = await authHeader() else { throw APIError(message: "Sign in first.") }
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 25
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(message: msg ?? "Server error \(code). Try again.")
        }
        return data
    }

    /// Uploads a photo (scaled so its longest side is at most `maxSide`, JPEG) and returns its public URL.
    static func upload(_ image: UIImage, maxSide: CGFloat = 1600) async throws -> String {
        guard let auth = await authHeader() else { throw APIError(message: "Sign in to add photos.") }
        let jpeg = image.scaledDown(maxSide: maxSide).jpegData(compressionQuality: 0.82) ?? Data()
        var req = URLRequest(url: URL(string: base + "/img")!)
        req.httpMethod = "POST"
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.upload(for: req, from: jpeg)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let url = obj?["url"] as? String else {
            throw APIError(message: obj?["error"] as? String ?? "Couldn't upload the photo.")
        }
        return url
    }
}

/// ASWebAuthenticationSession with async/await, presented from the key window.
@MainActor
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: WebAuth?
    private var session: ASWebAuthenticationSession?

    static func run(_ url: URL) async throws -> URL {
        let w = WebAuth(); current = w
        defer { current = nil }
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "comoevents") { callback, error in
                if let callback { cont.resume(returning: callback) } else { cont.resume(throwing: error ?? URLError(.cancelled)) }
            }
            s.presentationContextProvider = w
            s.prefersEphemeralWebBrowserSession = false
            w.session = s
            s.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

extension UIImage {
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let k = maxSide / longest
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
