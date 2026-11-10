import Foundation
import CloudKit
import CoreLocation
import SwiftUI

/// Events people post from inside the app. Public CloudKit database, record type "SubmittedEvent".
/// Posts are approved automatically within seconds (our worker writes the Approval as the moderator,
/// after the same word filter); a moderator can still remove one, and three reports hide it.
@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var approved: [Event] = [] { didSet { onApprovedChanged?(approved) } }
    /// The app mirrors approved posts into EventStore.communityEvents so they're on the map and in search.
    var onApprovedChanged: (([Event]) -> Void)?
    /// Ids this person posts under: iCloud user, or Google/Facebook account.
    private var myIDs: Set<String> { Set([userRecordName, CoMoAPI.account?.id].compactMap { $0 }) }
    @Published private(set) var pending: [CKRecord] = []
    @Published private(set) var userRecordName: String?
    @Published private(set) var iCloudAvailable = false
    @Published var lastError: String?

    /// Moderators: iCloud user record names allowed to approve. Add yours here (shown in Profile › Account).
    static let moderators: Set<String> = ["_c8e8240fd2a875267839a35bf9779b30", "_c8e8240fd2a875267839a35bf9779b30v"]   // Ajay; the "v" form was a paste slip, kept so old Approval records still count
    var isModerator: Bool { userRecordName.map { Self.moderators.contains($0) } ?? false }

    /// Posters this user has blocked (guideline 1.2). Kept on device.
    @Published private(set) var blockedSubmitters: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "community.blocked") ?? [])
    func block(submitterOf event: Event) {
        guard let id = event.submitterID, !id.isEmpty else { return }
        blockedSubmitters.insert(id)
        UserDefaults.standard.set(Array(blockedSubmitters), forKey: "community.blocked")
        approved.removeAll { $0.submitterID == id }
    }
    func unblockAll() {
        blockedSubmitters = []
        UserDefaults.standard.removeObject(forKey: "community.blocked")
        Task { await loadApproved() }
    }

    private lazy var container = CKContainer(identifier: AccountManager.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }

    func prepare() async {
        iCloudAvailable = ((try? await container.accountStatus()) ?? .noAccount) == .available
        if iCloudAvailable { userRecordName = try? await container.userRecordID().recordName }
    }

    // MARK: read

    /// Approvals are separate records; only ones created by a moderator's iCloud user count.
    /// That way no custom CloudKit role is needed: anyone can create an Approval, nobody else's matters.
    private var decisions: [String: Bool] = [:]      // eventRecordName -> approved?
    private var reportCounts: [String: Int] = [:]

    private func loadDecisions() async {
        do {
            let (results, _) = try await db.records(matching: CKQuery(recordType: "Approval", predicate: NSPredicate(value: true)), resultsLimit: 500)
            var d: [String: Bool] = [:]
            for r in results.compactMap({ try? $0.1.get() }) {
                guard let by = r.creatorUserRecordID?.recordName, Self.moderators.contains(by) || by == "__defaultOwner__",
                      let name = r["eventRecordName"] as? String else { continue }
                // A moderator's removal (approved = 0) always wins over the automatic approval.
                d[name] = (d[name] ?? true) && (r["approved"] as? Int64 ?? 0) == 1
            }
            decisions = d
        } catch { /* no schema yet or offline */ }
        do {
            let (results, _) = try await db.records(matching: CKQuery(recordType: "Report", predicate: NSPredicate(value: true)), resultsLimit: 500)
            var c: [String: Int] = [:]
            for r in results.compactMap({ try? $0.1.get() }) {
                if let name = r["eventRecordName"] as? String { c[name, default: 0] += 1 }
            }
            reportCounts = c
        } catch {}
    }

    private func fetchUpcoming() async -> [CKRecord] {
        let q = CKQuery(recordType: "SubmittedEvent", predicate: NSPredicate(format: "start >= %@", Date().addingTimeInterval(-6 * 3600) as NSDate))
        q.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        do {
            let (results, _) = try await db.records(matching: q, resultsLimit: 300)
            return results.compactMap { try? $0.1.get() }
        } catch { return [] }
    }

    func loadApproved() async {
        await loadDecisions()
        let recs = await fetchUpcoming()
        let mine = myIDs
        approved = recs.filter { r in
            let name = r.recordID.recordName
            // Your own post shows right away, even before the approval lands (unless it was removed).
            let ok = decisions[name] == true || (decisions[name] == nil && mine.contains(r["submitterID"] as? String ?? "-"))
            return ok && reportCounts[name, default: 0] < 3
        }
            .compactMap(Self.event(from:))
            .map(VenueLookup.enrich)
            .filter { !blockedSubmitters.contains($0.submitterID ?? "") }
    }

    /// Moderation list: every upcoming post (they go live automatically), newest decisions shown per post.
    func loadPending() async {
        await loadDecisions()
        pending = await fetchUpcoming()
    }
    func decision(for rec: CKRecord) -> Bool? { decisions[rec.recordID.recordName] }

    /// Asks the worker to approve new posts now instead of within the minute.
    private func approveNow() async {
        var req = URLRequest(url: URL(string: CoMoAPI.base + "/approve")!)
        req.httpMethod = "POST"; req.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Show a just-posted event at once, then pick up the approval (CloudKit's query index lags a few seconds).
    private func showNow(_ rec: CKRecord) async {
        if let e = Self.event(from: rec).map(VenueLookup.enrich) {
            approved.removeAll { $0.id == e.id }
            approved.append(e)
        }
        await approveNow()
        Task { try? await Task.sleep(nanoseconds: 8_000_000_000); await loadApproved() }
    }

    // MARK: write

    struct Draft {
        var title = ""; var category: Category = .community
        var extraCategories: Set<Category> = []
        var start = Calendar.current.date(byAdding: .day, value: 1, to: Date())!.rounded(to: 30)
        var hasEnd = false; var end = Date()
        var venue = ""; var address = ""; var price = ""; var link = ""; var details = ""; var submitterName = ""
        var agreedToGuidelines = false
        /// Optional photo (picked, or the scanned flyer); uploaded when posting.
        var photo: UIImage? = nil
    }

    /// Geocodes the address on device, then saves a pending record. Returns an error message or nil.
    func submit(_ d: Draft) async -> String? {
        let viaAccount = !iCloudAvailable && CoMoAPI.session != nil   // signed in with Google/Facebook, no iCloud
        guard iCloudAvailable || viaAccount else { return "Posting needs you signed in: iCloud on this iPhone, or Google or Facebook in Profile." }
        guard d.title.trimmingCharacters(in: .whitespaces).count >= 3 else { return "Give the event a title." }
        guard !d.venue.isEmpty || !d.address.isEmpty else { return "Where is it? Add a venue or an address." }
        guard d.agreedToGuidelines else { return "Please agree to the community guidelines first." }
        for text in [d.title, d.details, d.venue, d.submitterName, d.link] {
            if let bad = ContentFilter.offendingTerm(in: text) { return "That post can't go up: it contains \"\(bad)\". Please reword it." }
        }
        var lat: Double?, lng: Double?
        if let m = VenueLookup.fromTable(d.venue), let c = m.coordinate {
            lat = c.latitude; lng = c.longitude          // known venue: exact pin, no geocoder round trip
        } else {
            let query = [d.venue, d.address, "Columbia, MO"].filter { !$0.isEmpty }.joined(separator: ", ")
            if let pm = try? await CLGeocoder().geocodeAddressString(query).first, let loc = pm.location {
                lat = loc.coordinate.latitude; lng = loc.coordinate.longitude
            } else if let m = await VenueLookup.find(d.venue), let c = m.coordinate {
                lat = c.latitude; lng = c.longitude
            }
        }
        var imageUrl: String?
        if let photo = d.photo {
            do { imageUrl = try await CoMoAPI.upload(photo) } catch { return "Couldn't upload the photo: \(error.localizedDescription)" }
        }
        let cats = ([d.category] + d.extraCategories.filter { $0 != d.category }).map(\.rawValue)
        if viaAccount {
            var body: [String: Any] = ["title": d.title.trimmingCharacters(in: .whitespaces), "category": d.category.rawValue, "categories": cats,
                                       "start": d.start.timeIntervalSince1970 * 1000, "venue": d.venue, "address": d.address, "price": d.price,
                                       "link": d.link, "details": d.details, "submitterName": d.submitterName]
            if d.hasEnd { body["end"] = d.end.timeIntervalSince1970 * 1000 }
            if let lat, let lng { body["lat"] = lat; body["lng"] = lng }
            if let imageUrl { body["imageUrl"] = imageUrl }
            do {
                let data = try await CoMoAPI.call("/me/post", json: body)
                if let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["recordName"] as? String {
                    let rec = CKRecord(recordType: "SubmittedEvent", recordID: CKRecord.ID(recordName: name))
                    for (k, v) in body { if let cv = v as? CKRecordValue, !["start", "end"].contains(k) { rec[k] = cv } }
                    rec["start"] = d.start as CKRecordValue
                    if d.hasEnd { rec["end"] = d.end as CKRecordValue }
                    rec["submitterID"] = (CoMoAPI.account?.id ?? "") as CKRecordValue
                    await showNow(rec)
                }
                return nil
            } catch { return "Couldn't post: \(error.localizedDescription)" }
        }
        let rec = CKRecord(recordType: "SubmittedEvent")
        rec["title"] = d.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        rec["category"] = d.category.rawValue as CKRecordValue
        rec["categories"] = cats as CKRecordValue
        if let imageUrl { rec["imageUrl"] = imageUrl as CKRecordValue }
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
        do { let saved = try await db.save(rec); await showNow(saved); return nil } catch { return "Couldn't post: \(error.localizedDescription)" }
    }

    /// Moderator decision: writes an Approval record (the moderator is its creator, which is what the app checks).
    func decide(_ rec: CKRecord, approved: Bool) async {
        let a = CKRecord(recordType: "Approval")
        a["eventRecordName"] = rec.recordID.recordName as CKRecordValue
        a["approved"] = (approved ? 1 : 0) as CKRecordValue
        do {
            _ = try await db.save(a)
            decisions[rec.recordID.recordName] = approved
            pending.removeAll { $0.recordID == rec.recordID }
            await loadApproved()
        } catch { lastError = "Couldn't save decision: \(error.localizedDescription)" }
    }

    func setStatus(_ rec: CKRecord, _ status: String) async { await decide(rec, approved: status == "approved") }

    /// Anyone can flag a community post. Three flags hide it until a moderator looks.
    func report(_ event: Event, reason: String) async -> String? {
        guard event.isCommunity, let name = event.id.split(separator: ":").last else { return "Only community posts can be reported here." }
        if !iCloudAvailable, CoMoAPI.session != nil {
            do { try await CoMoAPI.call("/me/report", json: ["eventRecordName": String(name), "reason": reason]); return nil }
            catch { return error.localizedDescription }
        }
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
                     categories: r["categories"] as? [String] ?? [],
                     imageUrl: (r["imageUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                     description: r["details"] as? String,
                     organizer: name.map { "Posted by \(ContentFilter.safeName($0, fallback: "a community member"))" },
                     audience: ["groups", "singles", "couples", "family"],
                     submitterID: r["submitterID"] as? String)
    }
}

extension Date {
    func rounded(to minutes: Int) -> Date {
        let s = TimeInterval(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / s).rounded(.up) * s)
    }
}
