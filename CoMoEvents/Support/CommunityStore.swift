import Foundation
import CloudKit
import CoreLocation
import SwiftUI

/// Events people post from inside the app. Public CloudKit database, record type "SubmittedEvent".
/// New posts are "pending" until a moderator approves them; the app only shows "approved".
@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var approved: [Event] = []
    @Published private(set) var pending: [CKRecord] = []
    @Published private(set) var userRecordName: String?
    @Published private(set) var iCloudAvailable = false
    @Published var lastError: String?

    /// Moderators: iCloud user record names allowed to approve. Add yours here (shown in Profile › Account).
    static let moderators: Set<String> = ["_c8e8240fd2a875267839a35bf9779b30v"]
    var isModerator: Bool { userRecordName.map { Self.moderators.contains($0) || UserDefaults.standard.bool(forKey: "moderator.override") } ?? false }

    private lazy var container = CKContainer(identifier: AccountManager.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }

    func prepare() async {
        iCloudAvailable = ((try? await container.accountStatus()) ?? .noAccount) == .available
        if iCloudAvailable { userRecordName = try? await container.userRecordID().recordName }
    }

    // MARK: read

    func loadApproved() async {
        let pred = NSPredicate(format: "status == %@ AND start >= %@", "approved", Date().addingTimeInterval(-6 * 3600) as NSDate)
        let q = CKQuery(recordType: "SubmittedEvent", predicate: pred)
        q.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        do {
            let (results, _) = try await db.records(matching: q, resultsLimit: 200)
            approved = results.compactMap { try? $0.1.get() }.compactMap(Self.event(from:))
        } catch {
            // No schema yet or offline: keep what we had.
        }
    }

    func loadPending() async {
        let q = CKQuery(recordType: "SubmittedEvent", predicate: NSPredicate(format: "status == %@", "pending"))
        q.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        do {
            let (results, _) = try await db.records(matching: q, resultsLimit: 100)
            pending = results.compactMap { try? $0.1.get() }
        } catch { lastError = error.localizedDescription }
    }

    // MARK: write

    struct Draft {
        var title = ""; var category: Category = .community
        var start = Calendar.current.date(byAdding: .day, value: 1, to: Date())!.rounded(to: 30)
        var hasEnd = false; var end = Date()
        var venue = ""; var address = ""; var price = ""; var link = ""; var details = ""; var submitterName = ""
    }

    /// Geocodes the address on device, then saves a pending record. Returns an error message or nil.
    func submit(_ d: Draft) async -> String? {
        guard iCloudAvailable else { return "Posting needs iCloud signed in on this iPhone (Settings › your name)." }
        guard d.title.trimmingCharacters(in: .whitespaces).count >= 3 else { return "Give the event a title." }
        guard !d.venue.isEmpty || !d.address.isEmpty else { return "Where is it? Add a venue or an address." }
        var lat: Double?, lng: Double?
        let query = [d.venue, d.address, "Columbia, MO"].filter { !$0.isEmpty }.joined(separator: ", ")
        if let pm = try? await CLGeocoder().geocodeAddressString(query).first, let loc = pm.location {
            lat = loc.coordinate.latitude; lng = loc.coordinate.longitude
        }
        let rec = CKRecord(recordType: "SubmittedEvent")
        rec["title"] = d.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        rec["category"] = d.category.rawValue as CKRecordValue
        rec["start"] = d.start as CKRecordValue
        if d.hasEnd { rec["end"] = d.end as CKRecordValue }
        rec["venue"] = d.venue as CKRecordValue
        rec["address"] = d.address as CKRecordValue
        if let lat, let lng { rec["lat"] = lat as CKRecordValue; rec["lng"] = lng as CKRecordValue }
        rec["price"] = d.price as CKRecordValue
        rec["link"] = d.link as CKRecordValue
        rec["details"] = d.details as CKRecordValue
        rec["submitterName"] = d.submitterName as CKRecordValue
        rec["submitterID"] = (userRecordName ?? "") as CKRecordValue
        rec["status"] = "pending" as CKRecordValue
        rec["reports"] = 0 as CKRecordValue
        do { _ = try await db.save(rec); return nil } catch { return "Couldn't post: \(error.localizedDescription)" }
    }

    func setStatus(_ rec: CKRecord, _ status: String) async {
        rec["status"] = status as CKRecordValue
        do { _ = try await db.save(rec); pending.removeAll { $0.recordID == rec.recordID }; await loadApproved() }
        catch { lastError = "Couldn't update: \(error.localizedDescription)" }
    }

    /// Anyone can flag a community post. Three flags hide it until a moderator looks.
    func report(_ event: Event, reason: String) async -> String? {
        guard event.isCommunity, let name = event.id.split(separator: ":").last else { return "Only community posts can be reported here." }
        let r = CKRecord(recordType: "Report")
        r["eventRecordName"] = String(name) as CKRecordValue
        r["reason"] = reason as CKRecordValue
        r["reporterID"] = (userRecordName ?? "anonymous") as CKRecordValue
        do { _ = try await db.save(r); return nil } catch { return error.localizedDescription }
    }

    // MARK: mapping

    static func event(from r: CKRecord) -> Event? {
        guard let title = r["title"] as? String, let start = r["start"] as? Date else { return nil }
        let venue = (r["venue"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let address = (r["address"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = (r["submitterName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Event(id: "community:\(r.recordID.recordName)", source: "community", sourceName: "Posted in CoMo Events",
                     title: title, start: start, end: r["end"] as? Date,
                     venue: venue, address: address, lat: r["lat"] as? Double, lng: r["lng"] as? Double,
                     url: (r["link"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                     price: (r["price"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                     category: r["category"] as? String ?? "community",
                     description: r["details"] as? String,
                     organizer: name.map { "Posted by \($0)" },
                     audience: ["groups", "singles", "couples", "family"])
    }
}

extension Date {
    func rounded(to minutes: Int) -> Date {
        let s = TimeInterval(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / s).rounded(.up) * s)
    }
}
