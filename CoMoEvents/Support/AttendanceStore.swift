import Foundation
import CloudKit
import SwiftUI

/// "Going", "I'm here" and "Went" for events. One public CloudKit record per person per event
/// (record name att-<user>-<event>) so a change overwrites instead of piling up.
/// Counts are computed on the phone from the records of upcoming events.
@MainActor
final class AttendanceStore: ObservableObject {
    enum Status: String, CaseIterable { case going, here, went
        var label: String { switch self { case .going: return "Going"; case .here: return "I'm here"; case .went: return "Went" } }
        var symbol: String { switch self { case .going: return "hand.thumbsup.fill"; case .here: return "location.fill"; case .went: return "checkmark.seal.fill" } }
    }

    /// My own status per event id (also kept locally so it works offline / signed out of iCloud).
    @Published private(set) var mine: [String: Status] = [:]
    /// Everyone's counts per event id.
    @Published private(set) var counts: [String: (going: Int, here: Int, went: Int)] = [:]
    @Published var lastError: String?

    private lazy var container = CKContainer(identifier: AccountManager.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }
    private var userID: String?
    var onMineChanged: (([String: Status]) -> Void)?

    init() {
        if let d = UserDefaults.standard.dictionary(forKey: "attendance.mine") as? [String: String] {
            mine = d.compactMapValues(Status.init(rawValue:))
        }
    }

    func prepare() async {
        guard ((try? await container.accountStatus()) ?? .noAccount) == .available else { return }
        userID = try? await container.userRecordID().recordName
    }

    func status(for e: Event) -> Status? { mine[e.id] }
    func count(for e: Event) -> (going: Int, here: Int, went: Int) { counts[e.id] ?? (0, 0, 0) }

    /// Tap the same status again to clear it.
    func set(_ status: Status?, for e: Event) async {
        if let status { mine[e.id] = status } else { mine.removeValue(forKey: e.id) }
        UserDefaults.standard.set(mine.mapValues(\.rawValue), forKey: "attendance.mine")
        onMineChanged?(mine)
        guard let uid = userID else { return }
        let rid = CKRecord.ID(recordName: "att-\(uid)-\(e.id)")
        do {
            if let status {
                let rec = (try? await db.record(for: rid)) ?? CKRecord(recordType: "Attendance", recordID: rid)
                rec["eventID"] = e.id as CKRecordValue
                rec["status"] = status.rawValue as CKRecordValue
                rec["userID"] = uid as CKRecordValue
                rec["eventStart"] = e.startDate as CKRecordValue
                rec["updatedAt"] = Date() as CKRecordValue
                _ = try await db.save(rec)
            } else {
                try await db.deleteRecord(withID: rid)
            }
            await refreshCounts()
        } catch {
            if (error as? CKError)?.code != .unknownItem { lastError = error.localizedDescription }
        }
    }

    /// Pull everyone's attendance for events from yesterday on, and total it per event.
    func refreshCounts() async {
        let since = Date().addingTimeInterval(-36 * 3600)
        let q = CKQuery(recordType: "Attendance", predicate: NSPredicate(format: "eventStart >= %@", since as NSDate))
        var totals: [String: (going: Int, here: Int, went: Int)] = [:]
        var cursor: CKQueryOperation.Cursor?
        do {
            var page = try await db.records(matching: q, resultsLimit: 400)
            repeat {
                for r in page.matchResults.compactMap({ try? $0.1.get() }) {
                    guard let id = r["eventID"] as? String, let s = (r["status"] as? String).flatMap(Status.init(rawValue:)) else { continue }
                    var t = totals[id] ?? (0, 0, 0)
                    switch s { case .going: t.going += 1; case .here: t.here += 1; case .went: t.went += 1 }
                    totals[id] = t
                }
                cursor = page.queryCursor
                if let c = cursor { page = try await db.records(continuingMatchFrom: c, resultsLimit: 400) }
            } while cursor != nil
            counts = totals
        } catch { /* schema not deployed yet or offline: keep what we had */ }
    }
}
