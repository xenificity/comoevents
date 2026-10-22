import Foundation
import CloudKit
import SwiftUI

/// Friends by code. Each person who turns Friends on gets a public "FriendProfile" record
/// (name, a 6-letter code, and, if they opt in, their saved event ids). You add a friend by code.
@MainActor
final class FriendsStore: ObservableObject {
    struct Friend: Identifiable, Hashable {
        let id: String            // record name
        let name: String
        let code: String
        let favorites: [String]
        let going: [String]
        let here: [String]
        let sharing: Bool
        var initials: String { String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased() }
    }

    @Published private(set) var myCode: String?
    @Published var shareSaves: Bool = UserDefaults.standard.bool(forKey: "friends.share") {
        didSet { UserDefaults.standard.set(shareSaves, forKey: "friends.share"); Task { await publish() } }
    }
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "friends.enabled")
    @Published var lastError: String?

    private lazy var container = CKContainer(identifier: AccountManager.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }
    private var userRecordName: String?
    private var displayName = ""
    private var favorites: [String] = []
    private var going: [String] = []
    private var here: [String] = []
    private var friendIDs: [String] { get { UserDefaults.standard.stringArray(forKey: "friends.ids") ?? [] } set { UserDefaults.standard.set(newValue, forKey: "friends.ids") } }

    private var myRecordID: CKRecord.ID? { userRecordName.map { CKRecord.ID(recordName: "friend-\($0)") } }

    func update(displayName: String, favorites: [String]) {
        let changed = displayName != self.displayName || favorites != self.favorites
        self.displayName = displayName; self.favorites = favorites
        if changed && enabled { Task { await publish() } }
    }
    func update(attendance: [String: AttendanceStore.Status]) {
        let g = attendance.filter { $0.value == .going }.map(\.key).sorted()
        let h = attendance.filter { $0.value == .here }.map(\.key).sorted()
        let changed = g != going || h != here
        going = g; here = h
        if changed && enabled { Task { await publish() } }
    }

    /// Turn Friends on: needs iCloud on the phone. Creates or refreshes my public profile.
    func enable() async -> Bool {
        guard ((try? await container.accountStatus()) ?? .noAccount) == .available,
              let id = try? await container.userRecordID().recordName else {
            lastError = "Friends needs iCloud signed in on this iPhone."; return false
        }
        userRecordName = id
        myCode = Self.code(for: id)
        enabled = true
        UserDefaults.standard.set(true, forKey: "friends.enabled")
        await publish()
        await refresh()
        return true
    }

    func restore() async {
        guard enabled else { return }
        if let id = try? await container.userRecordID().recordName { userRecordName = id; myCode = Self.code(for: id) }
        await refresh()
    }

    func publish() async {
        guard enabled, let rid = myRecordID else { return }
        let rec = (try? await db.record(for: rid)) ?? CKRecord(recordType: "FriendProfile", recordID: rid)
        rec["displayName"] = ContentFilter.safeName(displayName) as CKRecordValue
        rec["code"] = (myCode ?? "") as CKRecordValue
        rec["sharing"] = (shareSaves ? 1 : 0) as CKRecordValue
        rec["favorites"] = (shareSaves ? favorites : []) as CKRecordValue
        rec["going"] = (shareSaves ? going : []) as CKRecordValue
        rec["here"] = (shareSaves ? here : []) as CKRecordValue
        rec["updatedAt"] = Date() as CKRecordValue
        do { _ = try await db.save(rec) } catch { lastError = error.localizedDescription }
    }

    func add(code raw: String) async -> String? {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 6 else { return "Codes are 6 letters." }
        guard code != myCode else { return "That's your own code." }
        do {
            let (results, _) = try await db.records(matching: CKQuery(recordType: "FriendProfile", predicate: NSPredicate(format: "code == %@", code)), resultsLimit: 1)
            guard let rec = results.compactMap({ try? $0.1.get() }).first else { return "No one has that code yet." }
            if blockedIDs.contains(rec.recordID.recordName) { return "You blocked this person." }
            var ids = friendIDs
            if !ids.contains(rec.recordID.recordName) { ids.append(rec.recordID.recordName); friendIDs = ids }
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    /// Add friends found through Facebook / Google (their FriendProfile record names). Returns how many were new.
    func add(recordNames: [String]) async -> Int {
        let blocked = Set(UserDefaults.standard.stringArray(forKey: "friends.blocked") ?? [])
        var ids = friendIDs, added = 0
        for n in recordNames where !ids.contains(n) && !blocked.contains(n) && n != myRecordID?.recordName { ids.append(n); added += 1 }
        friendIDs = ids
        await refresh()
        return added
    }

    func remove(_ f: Friend) {
        friendIDs.removeAll { $0 == f.id }
        friends.removeAll { $0.id == f.id }
    }

    /// Block: removes and refuses future adds of this profile (guideline 1.2).
    private var blockedIDs: [String] { get { UserDefaults.standard.stringArray(forKey: "friends.blocked") ?? [] } set { UserDefaults.standard.set(newValue, forKey: "friends.blocked") } }
    func block(_ f: Friend) {
        remove(f)
        if !blockedIDs.contains(f.id) { blockedIDs.append(f.id) }
    }
    func report(_ f: Friend, reason: String) async -> String? {
        let r = CKRecord(recordType: "Report")
        r["eventRecordName"] = f.id as CKRecordValue
        r["reason"] = "friend profile: \(reason)" as CKRecordValue
        r["reporterID"] = (userRecordName ?? "anonymous") as CKRecordValue
        do { _ = try await db.save(r); return nil } catch { return error.localizedDescription }
    }

    func refresh() async {
        let ids = friendIDs.map { CKRecord.ID(recordName: $0) }
        guard !ids.isEmpty else { friends = []; return }
        do {
            let results = try await db.records(for: ids)
            friends = ids.compactMap { id in
                guard let r = try? results[id]?.get() else { return nil }
                return Friend(id: id.recordName, name: ContentFilter.safeName(r["displayName"] as? String ?? "", fallback: "Friend"), code: r["code"] as? String ?? "",
                              favorites: r["favorites"] as? [String] ?? [], going: r["going"] as? [String] ?? [],
                              here: r["here"] as? [String] ?? [], sharing: (r["sharing"] as? Int64 ?? 0) == 1)
            }
        } catch { lastError = error.localizedDescription }
    }

    /// Friends who saved, are going to, or are at this event.
    func friendsGoing(to event: Event) -> [Friend] { friends.filter { $0.favorites.contains(event.id) || $0.going.contains(event.id) || $0.here.contains(event.id) } }
    func friendsHere(at event: Event) -> [Friend] { friends.filter { $0.here.contains(event.id) } }
    /// Friends at any event in a set of ids (for map pins).
    func friends(atAny ids: Set<String>) -> (here: [Friend], going: [Friend]) {
        let here = friends.filter { !ids.isDisjoint(with: $0.here) }
        let going = friends.filter { f in !here.contains(f) && (!ids.isDisjoint(with: f.going) || !ids.isDisjoint(with: f.favorites)) }
        return (here, going)
    }

    /// Deterministic 6-char code from the iCloud user record name. No lookup table to leak.
    static func code(for recordName: String) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var h: UInt64 = 1469598103934665603
        for b in recordName.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        var out = ""
        for _ in 0..<6 { out.append(alphabet[Int(h % UInt64(alphabet.count))]); h /= UInt64(alphabet.count) }
        return out
    }
}
