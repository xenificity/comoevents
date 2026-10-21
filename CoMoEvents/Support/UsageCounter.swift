import Foundation
import CloudKit
import SwiftUI

/// "How many people use CoMo Events": one anonymous public "Install" record per install, created once
/// and touched at most once a week. No name, no device identifier, no location: a random record
/// name, the platform, the app version and two dates. Counts are read back by everyone.
@MainActor
final class UsageCounter: ObservableObject {
    @Published private(set) var total: Int = UserDefaults.standard.integer(forKey: "usage.total")
    @Published private(set) var updatedAt: Date? = UserDefaults.standard.object(forKey: "usage.updatedAt") as? Date

    private lazy var container = CKContainer(identifier: AccountManager.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }

    /// Register this install (needs an iCloud account on the phone, like every other public write).
    func register() async {
        guard ((try? await container.accountStatus()) ?? .noAccount) == .available else { return }
        let d = UserDefaults.standard
        let name = d.string(forKey: "usage.recordName") ?? "install-\(UUID().uuidString.lowercased())"
        let last = d.object(forKey: "usage.lastSeen") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 86_400 else { return }
        let rid = CKRecord.ID(recordName: name)
        let rec = (try? await db.record(for: rid)) ?? CKRecord(recordType: "Install", recordID: rid)
        if rec["installedAt"] == nil { rec["installedAt"] = Date() as CKRecordValue }
        rec["lastSeen"] = Date() as CKRecordValue
        rec["platform"] = "ios" as CKRecordValue
        rec["appVersion"] = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") as CKRecordValue
        do {
            _ = try await db.save(rec)
            d.set(name, forKey: "usage.recordName")
            d.set(Date(), forKey: "usage.lastSeen")
        } catch { /* schema not deployed yet or offline: try again next launch */ }
    }

    /// Everyone's installs (iPhone and web). Refreshed at most once a day; cached between launches.
    func refresh(force: Bool = false) async {
        if !force, let u = updatedAt, Date().timeIntervalSince(u) < 86_400 { return }
        var count = 0
        var cursor: CKQueryOperation.Cursor?
        do {
            var page = try await db.records(matching: CKQuery(recordType: "Install", predicate: NSPredicate(format: "installedAt > %@", Date.distantPast as NSDate)),
                                            desiredKeys: [], resultsLimit: 400)
            repeat {
                count += page.matchResults.count
                cursor = page.queryCursor
                if let c = cursor { page = try await db.records(continuingMatchFrom: c, desiredKeys: [], resultsLimit: 400) }
            } while cursor != nil && count < 50_000
            total = count
            updatedAt = Date()
            UserDefaults.standard.set(count, forKey: "usage.total")
            UserDefaults.standard.set(updatedAt, forKey: "usage.updatedAt")
        } catch { /* keep the cached number */ }
    }

    var text: String? {
        guard total > 0 else { return nil }
        return total == 1 ? "1 person uses CoMo Events" : "\(total.formatted()) people use CoMo Events"
    }
}
