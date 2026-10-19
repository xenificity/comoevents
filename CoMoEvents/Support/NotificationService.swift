import Foundation
import UserNotifications
import SwiftUI

/// Local notifications only. Two kinds:
///  - a reminder one hour before each saved event
///  - a "tonight in CoMo" digest at 4 PM built from the cached feed
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var remindersOn: Bool { didSet { UserDefaults.standard.set(remindersOn, forKey: "notif.reminders") } }
    @Published var digestOn: Bool { didSet { UserDefaults.standard.set(digestOn, forKey: "notif.digest") } }
    @Published private(set) var authorized = false

    var onOpenEvent: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        remindersOn = UserDefaults.standard.object(forKey: "notif.reminders") as? Bool ?? false
        digestOn = UserDefaults.standard.object(forKey: "notif.digest") as? Bool ?? false
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let s = await center.notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Ask once; returns whether we may schedule.
    func requestAuthorization() async -> Bool {
        do {
            let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorized = ok
            return ok
        } catch { return false }
    }

    /// Call after the feed loads or favorites change.
    func reschedule(favorites: [Event], all: [Event]) async {
        guard authorized else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        var keep = Set<String>()
        let now = Date()

        if remindersOn {
            for e in favorites.filter({ $0.startDate > now.addingTimeInterval(3600) }).prefix(50) {
                let id = "rem-\(e.id)"
                keep.insert(id)
                if pending.contains(id) { continue }
                let c = UNMutableNotificationContent()
                c.title = "In an hour: \(e.title)"
                c.body = [e.venue, e.timeText].compactMap { $0 }.joined(separator: " · ")
                c.sound = .default
                c.userInfo = ["eventID": e.id]
                let fire = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: e.startDate.addingTimeInterval(-3600))
                try? await center.add(UNNotificationRequest(identifier: id, content: c,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)))
            }
        }

        if digestOn {
            let cal = Calendar.current
            for dayOffset in 0...6 {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)),
                      let fire = cal.date(bySettingHour: 16, minute: 0, second: 0, of: day), fire > now else { continue }
                let evening = all.filter { cal.isDate($0.startDate, inSameDayAs: day) && cal.component(.hour, from: $0.startDate) >= 16 }
                guard !evening.isEmpty else { continue }
                let id = "digest-\(Int(day.timeIntervalSince1970))"
                keep.insert(id)
                if pending.contains(id) { continue }
                let c = UNMutableNotificationContent()
                c.title = dayOffset == 0 ? "Tonight in CoMo" : "\(Event.dayFormatter.string(from: day)) in CoMo"
                let top = evening.prefix(3).map { "\($0.timeText) \($0.title)" }.joined(separator: " · ")
                c.body = "\(evening.count) events. \(top)"
                c.sound = .default
                c.userInfo = ["tab": "map"]
                try? await center.add(UNNotificationRequest(identifier: id, content: c,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
            }
        }

        let stale = pending.filter { ($0.hasPrefix("rem-") || $0.hasPrefix("digest-")) && !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    // Show banners while the app is open, and route taps.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let id = info["eventID"] as? String {
            await MainActor.run { onOpenEvent?(id) }
        }
    }
}
