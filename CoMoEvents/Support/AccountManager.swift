import Foundation
import AuthenticationServices
import CloudKit
import SwiftUI

/// Sign in with Apple + CloudKit private database. No server of our own.
///
/// - Signed out: the profile is kept locally (Application Support/profile.json).
/// - Signed in: the same profile is also saved as one CKRecord ("Profile") in the user's
///   private iCloud database, and fetched back on launch / on other devices.
@MainActor
final class AccountManager: ObservableObject {
    enum SyncState: Equatable { case idle, syncing, synced(Date), unavailable(String), failed(String) }

    @Published private(set) var userID: String?          // Apple user identifier
    @Published var profile = UserProfile()
    @Published private(set) var sync: SyncState = .idle
    @Published var lastError: String?

    var isSignedIn: Bool { userID != nil }

    static let containerID = "iCloud.com.xenificity.comoevents"
    private let recordType = "Profile"
    private var saveTask: Task<Void, Never>?
    private var db: CKDatabase { CKContainer(identifier: Self.containerID).privateCloudDatabase }

    // MARK: lifecycle

    init() {
        userID = Keychain.read("apple.userID")
        profile = Self.loadLocal() ?? UserProfile()
    }

    /// Check the Apple credential is still valid, then pull the cloud copy.
    func restore() async {
        guard let id = userID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: id)
        if state == .revoked || state == .notFound {
            signOut(keepLocal: true)
            return
        }
        await pull()
    }

    // MARK: Sign in with Apple

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            let code = (err as? ASAuthorizationError)?.code
            if code == .canceled { return }
            lastError = "Sign in didn't finish: \(err.localizedDescription)"
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            Keychain.write("apple.userID", cred.user)
            userID = cred.user
            // Apple only sends the name on the very first sign in; keep it.
            if profile.displayName.isEmpty, let n = cred.fullName {
                let name = [n.givenName, n.familyName].compactMap { $0 }.joined(separator: " ")
                if !name.isEmpty { profile.displayName = name; profile.updatedAt = Date() }
            }
            saveLocal()
            Task { await pull(); await push() }
        }
    }

    func signOut(keepLocal: Bool = true) {
        Keychain.delete("apple.userID")
        userID = nil
        sync = .idle
        if !keepLocal { profile = UserProfile(); saveLocal() }
    }

    /// App Store rule 5.1.1(v): people must be able to delete what we hold about them.
    func deleteAccountData() async {
        if let id = userID {
            do { try await db.deleteRecord(withID: recordID(for: id)) } catch { /* nothing there is fine */ }
        }
        signOut(keepLocal: false)
    }

    // MARK: profile edits

    func update(_ change: (inout UserProfile) -> Void) {
        change(&profile)
        profile.updatedAt = Date()
        saveLocal()
        schedulePush()
    }

    func setFavorites(_ ids: Set<String>) {
        guard Set(profile.favorites) != ids else { return }
        update { $0.favorites = Array(ids) }
    }

    // MARK: CloudKit

    private func recordID(for id: String) -> CKRecord.ID { CKRecord.ID(recordName: "profile-\(id)") }

    func pull() async {
        guard let id = userID else { return }
        sync = .syncing
        do {
            let status = try await CKContainer(identifier: Self.containerID).accountStatus()
            guard status == .available else {
                sync = .unavailable("iCloud is off on this device, so the profile stays local.")
                return
            }
            let rec = try await db.record(for: recordID(for: id))
            if let remote = Self.profile(from: rec) {
                profile = profile.merged(with: remote)
                saveLocal()
            }
            sync = .synced(Date())
        } catch let e as CKError where e.code == .unknownItem {
            sync = .synced(Date())   // first device: nothing in the cloud yet
            await push()
        } catch {
            sync = .failed(Self.friendly(error))
        }
    }

    /// CloudKit's own messages are record dumps; the profile is always safe on the phone, so say that.
    static func friendly(_ error: Error) -> String {
        let code = (error as? CKError)?.code
        switch code {
        case .quotaExceeded: return "Your iCloud storage is full, so the profile is saved on this phone only."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is unreachable right now. Your profile is saved on this phone and will sync later."
        case .notAuthenticated: return "iCloud is signed out on this iPhone, so the profile stays on this phone."
        default: return "Could not sync with iCloud. Your profile is saved on this phone."
        }
    }

    private func schedulePush() {
        guard isSignedIn else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { await push() }
        }
    }

    func push() async {
        guard let id = userID else { return }
        sync = .syncing
        do {
            let rid = recordID(for: id)
            let rec = (try? await db.record(for: rid)) ?? CKRecord(recordType: recordType, recordID: rid)
            rec["displayName"] = profile.displayName as CKRecordValue
            rec["interests"] = profile.interests as CKRecordValue
            rec["audience"] = (profile.audience ?? "") as CKRecordValue
            rec["favorites"] = profile.favorites as CKRecordValue
            rec["updatedAt"] = profile.updatedAt as CKRecordValue
            _ = try await db.save(rec)
            sync = .synced(Date())
        } catch {
            sync = .failed(Self.friendly(error))
        }
    }

    private static func profile(from rec: CKRecord) -> UserProfile? {
        var p = UserProfile()
        p.displayName = rec["displayName"] as? String ?? ""
        p.interests = rec["interests"] as? [String] ?? []
        let a = rec["audience"] as? String ?? ""
        p.audience = a.isEmpty ? nil : a
        p.favorites = rec["favorites"] as? [String] ?? []
        p.updatedAt = rec["updatedAt"] as? Date ?? .distantPast
        return p
    }

    // MARK: local file

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }
    private static func loadLocal() -> UserProfile? {
        guard let d = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: d)
    }
    private func saveLocal() {
        if let d = try? JSONEncoder().encode(profile) { try? d.write(to: Self.fileURL, options: .atomic) }
    }
}

/// Minimal Keychain wrapper for the Apple user identifier.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.xenificity.comoevents",
         kSecAttrAccount as String: key]
    }
    static func read(_ key: String) -> String? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func write(_ key: String, _ value: String) {
        delete(key)
        var q = query(key); q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
