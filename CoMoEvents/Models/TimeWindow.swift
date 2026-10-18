import Foundation

enum TimeWindow: String, CaseIterable, Identifiable {
    case now = "Now", today = "Today", weekend = "Weekend", week = "7 days", all = "All"
    var id: String { rawValue }

    func contains(_ e: Event, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch self {
        case .now:
            // Ongoing, or starting within the next 3 hours.
            return e.effectiveEnd >= now && e.startDate <= now.addingTimeInterval(3 * 3600)
        case .today:
            return e.effectiveEnd >= now && cal.isDateInToday(e.startDate) || (e.startDate < now && e.effectiveEnd >= now)
        case .weekend:
            let (sat, sunEnd) = TimeWindow.weekendBounds(from: now)
            return e.startDate >= sat && e.startDate < sunEnd || (e.startDate < sat && e.effectiveEnd >= sat && e.effectiveEnd >= now)
        case .week:
            return e.effectiveEnd >= now && e.startDate < now.addingTimeInterval(7 * 86_400)
        case .all:
            return e.effectiveEnd >= now
        }
    }

    /// Start of the coming (or current) Saturday, and end of that Sunday.
    static func weekendBounds(from now: Date) -> (Date, Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let wd = cal.component(.weekday, from: today) // 1 = Sunday ... 7 = Saturday
        let daysToSat = wd == 1 ? -1 : (7 - wd)
        let sat = cal.date(byAdding: .day, value: daysToSat, to: today)!
        let sunEnd = cal.date(byAdding: .day, value: 2, to: sat)!
        return (sat, sunEnd)
    }
}
