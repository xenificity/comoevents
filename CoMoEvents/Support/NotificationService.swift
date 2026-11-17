import Foundation
import UserNotifications
import BackgroundTasks
import SwiftUI
import UIKit

/// Local notifications only. Three kinds:
///  - a reminder one hour before each saved event (opt-in, asks for permission)
///  - the weekend digest: Thursday 6 PM and Friday 3 PM, three picks for the weekend from what the person
///    saves and goes to (on by default, same quiet permission as tonight's pick)
///  - "Tonight's pick" at 7 PM: the one event most worth going to that evening, built from the cached feed.
///    On by default. It uses provisional authorization, so iOS shows no permission prompt: the
///    notifications arrive quietly in Notification Center with iOS's own Keep / Turn Off buttons, and
///    Profile has an off switch and a button to get them as banners.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    static let refreshTaskID = "com.xenificity.comoevents.refresh"
    /// How many days of picks are queued ahead. iOS keeps at most 64 pending requests:
    /// 14 picks + 6 weekend digests (3 weekends x Thursday and Friday) + up to 40 reminders stays under it.
    static let pickDays = 14
    static let weekendsAhead = 3
    static let maxReminders = 40
    static let pickHour = 19

    @Published var remindersOn: Bool { didSet { UserDefaults.standard.set(remindersOn, forKey: "notif.reminders") } }
    @Published var digestOn: Bool { didSet { UserDefaults.standard.set(digestOn, forKey: "notif.digest") } }
    @Published var weekendOn: Bool { didSet { UserDefaults.standard.set(weekendOn, forKey: "notif.weekend") } }
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    /// May we schedule at all (quietly or with banners)?
    var authorized: Bool { status == .authorized || status == .provisional || status == .ephemeral }
    /// Delivered quietly to Notification Center only; the user can upgrade to banners.
    var isQuiet: Bool { status == .provisional }

    /// A tap can arrive before launch() has wired this up (cold start from the notification): keep it until then.
    var onOpenEvent: ((String) -> Void)? {
        didSet { if let id = waitingOpen, let onOpenEvent { waitingOpen = nil; onOpenEvent(id) } }
    }
    private var waitingOpen: String?
    private func open(_ id: String) { if let onOpenEvent { onOpenEvent(id) } else { waitingOpen = id } }
    /// A tap on the weekend digest opens Upcoming on "this weekend".
    var onOpenWeekend: (() -> Void)? {
        didSet { if waitingWeekend, let onOpenWeekend { waitingWeekend = false; onOpenWeekend() } }
    }
    private var waitingWeekend = false
    private func openWeekend() { if let onOpenWeekend { onOpenWeekend() } else { waitingWeekend = true } }
    private let center = UNUserNotificationCenter.current()
    private var scheduling = false
    private var rerun: (favorites: [Event], all: [Event])?

    override init() {
        remindersOn = UserDefaults.standard.object(forKey: "notif.reminders") as? Bool ?? false
        // On unless the person turned it off.
        digestOn = UserDefaults.standard.object(forKey: "notif.digest") as? Bool ?? true
        weekendOn = UserDefaults.standard.object(forKey: "notif.weekend") as? Bool ?? true
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        status = await center.notificationSettings().authorizationStatus
    }

    /// No prompt: if the person has never been asked, take provisional (quiet) permission.
    func ensureQuietPermission() async {
        await refreshAuthorization()
        guard status == .notDetermined, digestOn || remindersOn || weekendOn else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        await refreshAuthorization()
    }

    /// The real iOS prompt (from the Profile switches). Upgrades quiet delivery to banners.
    func requestAuthorization() async -> Bool {
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return ok
    }

    /// Call after the feed loads or favorites change. Calls that arrive while one is running are folded into one rerun.
    func reschedule(favorites: [Event], all: [Event]) async {
        if scheduling { rerun = (favorites, all); return }
        scheduling = true
        defer { scheduling = false }
        var job: (favorites: [Event], all: [Event])? = (favorites, all)
        while let j = job {
            rerun = nil
            await schedule(favorites: j.favorites, all: j.all)
            job = rerun
        }
    }

    private func schedule(favorites: [Event], all: [Event]) async {
        guard authorized else { return }
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        let now = Date()
        let cal = Calendar.current
        var adds: [UNNotificationRequest] = []
        var keep = Set<String>()

        if remindersOn {
            for e in favorites.filter({ $0.startDate > now.addingTimeInterval(3600) }).sorted(by: { $0.startDate < $1.startDate }).prefix(Self.maxReminders) {
                let id = "rem-\(e.id)"
                keep.insert(id)
                if pending.contains(id) { continue }
                let c = UNMutableNotificationContent()
                c.title = "In an hour: \(e.title)"
                c.body = [e.venue, e.timeText].compactMap { $0 }.joined(separator: " · ")
                c.sound = .default
                c.userInfo = ["eventID": e.id]
                let fire = cal.dateComponents([.year, .month, .day, .hour, .minute], from: e.startDate.addingTimeInterval(-3600))
                adds.append(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)))
            }
        }

        if digestOn {
            var used = Set<String>()   // no repeat of the same show on two evenings
            var withPhoto = 0
            for dayOffset in 0..<Self.pickDays {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)),
                      let fire = cal.date(bySettingHour: Self.pickHour, minute: 0, second: 0, of: day), fire > now,
                      let (pick, others) = Self.pick(for: day, fire: fire, from: all, avoiding: used) else { continue }
                used.insert(Self.titleKey(pick))
                let id = "pick-\(cal.component(.year, from: day))-\(cal.ordinality(of: .day, in: .year, for: day) ?? 0)"
                keep.insert(id)
                let c = UNMutableNotificationContent()
                c.title = dayOffset == 0 ? "Tonight's pick in CoMo" : "\(Self.weekday.string(from: day)) night in CoMo"
                c.subtitle = pick.title
                var body = pick.timeText == "All day" || pick.timeText == "Time TBD" ? "Tonight" : pick.timeText
                if let v = Self.venueText(pick) { body += " at \(v)" }
                body += "."
                if others > 0 { body += " Plus \(others) more thing\(others == 1 ? "" : "s") on tonight. Tap to see." }
                c.body = body
                c.sound = .default
                c.threadIdentifier = "tonight"
                c.relevanceScore = 0.6
                c.userInfo = ["eventID": pick.id, "kind": "pick"]
                // A picture makes it stand out in Notification Center. Only for the next few nights (it is downloaded now).
                if withPhoto < 3, let a = await Self.attachment(for: pick) { c.attachments = [a]; withPhoto += 1 }
                // Always replace: the feed may have changed since last time.
                adds.append(UNNotificationRequest(identifier: id, content: c,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
            }
        }

        if weekendOn {
            for r in Self.weekendRequests(from: all, now: now) {
                keep.insert(r.identifier)
                adds.append(r)   // always replace: the picks follow the latest feed and taste
            }
        }

        // Remove first so the adds never push us over iOS's 64-request cap.
        let stale = pending.filter { ($0.hasPrefix("rem-") || $0.hasPrefix("digest-") || $0.hasPrefix("pick-") || $0.hasPrefix("wknd-")) && !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        for r in adds { try? await center.add(r) }
    }

    #if DEBUG
    /// Testing: `SIMCTL_CHILD_WEEKEND_TEST=1 xcrun simctl launch booted com.xenificity.comoevents` fires the
    /// coming weekend's Thursday digest 10 seconds after launch.
    func debugFireWeekendSoon(all: [Event]) async {
        guard ProcessInfo.processInfo.environment["WEEKEND_TEST"] != nil, authorized,
              let r = Self.weekendRequests(from: all, now: Date()).first else { return }
        try? await center.add(UNNotificationRequest(identifier: "wknd-test", content: r.content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
    }

    /// Testing: `SIMCTL_CHILD_PICK_TEST=1 xcrun simctl launch booted com.xenificity.comoevents` fires
    /// tonight's pick 10 seconds after launch, with the same content the 7 PM one would have.
    func debugFirePickSoon(all: [Event]) async {
        guard ProcessInfo.processInfo.environment["PICK_TEST"] != nil, authorized else { return }
        let fire = Calendar.current.date(bySettingHour: Self.pickHour, minute: 0, second: 0, of: Date()) ?? Date()
        guard let (pick, others) = Self.pick(for: Date(), fire: fire, from: all, avoiding: []) else { return }
        let c = UNMutableNotificationContent()
        c.title = "Tonight's pick in CoMo"; c.subtitle = pick.title
        c.body = "\(pick.timeText)\(Self.venueText(pick).map { " at \($0)" } ?? ""). Plus \(others) more things on tonight. Tap to see."
        c.sound = .default; c.threadIdentifier = "tonight"; c.userInfo = ["eventID": pick.id, "kind": "pick"]
        if let a = await Self.attachment(for: pick) { c.attachments = [a] }
        try? await center.add(UNNotificationRequest(identifier: "pick-test", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
    }
    #endif

    // MARK: weekend digest

    /// Thursday 6 PM and Friday 3 PM for the next few weekends: the three best weekend events for this person.
    static func weekendRequests(from all: [Event], now: Date) -> [UNNotificationRequest] {
        let cal = Calendar.current
        var out: [UNNotificationRequest] = []
        // The coming Friday (today if it is Friday), then the next ones.
        let today = cal.startOfDay(for: now)
        let wd = cal.component(.weekday, from: today)            // Sunday = 1 ... Friday = 6
        let toFriday = (6 - wd + 7) % 7
        guard let firstFriday = cal.date(byAdding: .day, value: toFriday, to: today) else { return [] }
        for w in 0..<weekendsAhead {
            guard let friday = cal.date(byAdding: .day, value: 7 * w, to: firstFriday),
                  let thursday = cal.date(byAdding: .day, value: -1, to: friday) else { continue }
            let picks = weekendPicks(friday: friday, from: all)
            guard !picks.top.isEmpty else { continue }
            let key = "\(cal.component(.year, from: friday))-\(cal.ordinality(of: .day, in: .year, for: friday) ?? 0)"
            for (day, hour, kind) in [(thursday, 18, "thu"), (friday, 15, "fri")] {
                guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { continue }
                let c = UNMutableNotificationContent()
                c.title = kind == "thu" ? "This weekend in CoMo" : "Your weekend starts now"
                c.subtitle = kind == "thu" ? "3 picks for you" : picks.top[0].title
                c.body = weekendBody(picks.top, more: picks.total - picks.top.count, friday: kind == "fri")
                c.sound = .default
                c.threadIdentifier = "weekend"
                c.relevanceScore = 0.7
                c.userInfo = ["kind": "weekend"]
                out.append(UNNotificationRequest(identifier: "wknd-\(kind)-\(key)", content: c,
                    trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
            }
        }
        return out
    }

    /// Friday 4 PM to Sunday night: the three best for this person (quality + what they save and go to), no repeats.
    static func weekendPicks(friday: Date, from all: [Event]) -> (top: [Event], total: Int) {
        let cal = Calendar.current
        guard let from = cal.date(bySettingHour: 16, minute: 0, second: 0, of: friday),
              let to = cal.date(byAdding: .day, value: 3, to: cal.startOfDay(for: friday)) else { return ([], 0) }
        let weekend = all.filter { $0.startDate >= from && $0.startDate < to && !$0.timeTBD }
        var seen = Set<String>()
        let ranked = weekend
            .map { (e: $0, r: rank($0) + TasteProfile.shared.personal($0)) }
            .sorted { $0.r > $1.r }
            .filter { seen.insert(titleKey($0.e)).inserted }
            .map(\.e)
        return (Array(ranked.prefix(3)), weekend.count)
    }

    static func weekendBody(_ top: [Event], more: Int, friday: Bool) -> String {
        let day = DateFormatter(); day.dateFormat = "EEE"
        let lines = top.map { e -> String in
            var s = "\(day.string(from: e.startDate)): \(e.title)"
            if let v = venueText(e) { s += " at \(v)" }
            return s
        }
        var body = lines.joined(separator: "\n")
        if more > 0 { body += "\nPlus \(more) more this weekend. Tap to see them all." }
        return body
    }

    // MARK: choosing the pick

    private static let weekday: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE"; return f }()
    /// The venue, unless the title already says it ("Heidi Gardner – University Concert Series").
    static func venueText(_ e: Event) -> String? {
        guard let v = e.venue?.trimmingCharacters(in: .whitespaces), !v.isEmpty,
              !e.title.localizedCaseInsensitiveContains(v) else { return nil }
        return v
    }
    private static func titleKey(_ e: Event) -> String { e.title.lowercased().filter { $0.isLetter || $0.isNumber } }
    /// A real photo, not one of the drawn covers (docs/img/gen/*, except resized photos p-*).
    private static func hasPhoto(_ e: Event) -> Bool {
        guard let u = e.imageUrl, !u.isEmpty else { return false }
        return !u.contains("/img/gen/") || u.contains("/img/gen/p-")
    }

    /// The best event starting that evening (6:30 PM to midnight), and how many others are on tonight.
    static func pick(for day: Date, fire: Date, from all: [Event], avoiding used: Set<String>) -> (Event, Int)? {
        let cal = Calendar.current
        guard let from = cal.date(bySettingHour: 18, minute: 30, second: 0, of: day),
              let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) else { return nil }
        let tonight = all.filter { e in
            if e.allDay || e.timeTBD { return false }
            if e.startDate >= from && e.startDate < to { return true }
            return e.startDate < fire && e.effectiveEnd > fire.addingTimeInterval(3600)   // already on and still going
        }
        let fresh = tonight.filter { $0.startDate >= from && !used.contains(titleKey($0)) }
        guard let best = fresh.max(by: { rank($0) < rank($1) }) else { return nil }
        return (best, tonight.count - 1)
    }

    private static func rank(_ e: Event) -> Double {
        var r = SmartSearch.shared.baseRank(e)
        if hasPhoto(e) { r += 12 }
        if e.badge != nil { r += 8 }
        if e.kinds.contains(.religious) { r -= 30 }   // a service is a poor "you must go" nudge for most people
        if e.kinds.contains(where: { [.music, .nightlife, .party, .arts, .food].contains($0) }) { r += 5 }
        return r
    }

    // MARK: photo attachment

    private static func attachment(for e: Event) async -> UNNotificationAttachment? {
        // Real photos and the drawn covers both work (covers have no text, the notification carries the title).
        guard let s = e.imageUrl, !s.isEmpty, let url = URL(string: s) else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("notif", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cached = dir.appendingPathComponent("\(e.id).jpg")
        if !FileManager.default.fileExists(atPath: cached.path) {
            var req = URLRequest(url: url); req.timeoutInterval = 10
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let jpg = await Task.detached(priority: .utility, operation: { jpeg(from: data) }).value else { return nil }
            try? jpg.write(to: cached)
        }
        // iOS moves the attachment file into its own store, so hand it a copy.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard (try? FileManager.default.copyItem(at: cached, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "photo", url: copy, options: nil)
    }

    /// Notifications take JPEG/PNG/GIF, not WebP, so re-encode; also keep it small.
    nonisolated private static func jpeg(from data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxW: CGFloat = 1000
        let scale = min(1, maxW / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.8)
    }

    // MARK: background refresh

    /// Ask iOS to wake the app in the afternoon so tonight's pick comes from a fresh feed.
    /// iOS decides when (and whether) it runs; the three weeks of queued picks cover the gaps.
    static func scheduleBackgroundRefresh() {
        let cal = Calendar.current, now = Date()
        var next = cal.date(bySettingHour: 15, minute: 0, second: 0, of: now) ?? now
        if next <= now.addingTimeInterval(1800) { next = cal.date(byAdding: .day, value: 1, to: next) ?? now.addingTimeInterval(86_400) }
        let r = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        r.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(r)
    }

    static func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        guard let events = await EventStore.fetchLive() else { return }
        let fav = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        await shared.refreshAuthorization()
        await shared.reschedule(favorites: events.filter { fav.contains($0.id) }, all: events)
    }

    // MARK: delegate

    // Show banners while the app is open, and route taps.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let id = info["eventID"] as? String {
            if info["kind"] as? String == "pick" { await MainActor.run { Analytics.count("notif-pick") } }
            await MainActor.run { open(id) }
        } else if info["kind"] as? String == "weekend" {
            await MainActor.run { Analytics.count("notif-weekend"); openWeekend() }
        }
    }
}
