import AppIntents
import SwiftUI

/// "Hey Siri, what's happening this weekend in CoMo Events?"
struct WeekendIntent: AppIntent {
    static var title: LocalizedStringResource = "What's happening this weekend"
    static var description = IntentDescription("The best things to do in Columbia, MO this weekend.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let events = FeedCache.loadEvents()
        let (weekend, top) = await Self.weekend(events, now: Date())
        guard !top.isEmpty else { return .result(dialog: "Nothing listed for this weekend yet. Check back Thursday.") { EmptySnippet(text: "Nothing this weekend yet") } }
        let day = DateFormatter(); day.dateFormat = "EEEE"
        let spoken = top.prefix(3).map { "\(day.string(from: $0.startDate)): \($0.title)" }.joined(separator: ". ")
        return .result(dialog: IntentDialog("\(weekend.count) things this weekend in CoMo. \(spoken).")) {
            EventsSnippet(heading: "This weekend · \(weekend.count)", events: top, showDay: true)
        }
    }

    /// Friday 4 PM to Sunday night of this week (from now, on a weekend day), and the top four.
    @MainActor static func weekend(_ events: [Event], now: Date) -> (all: [Event], top: [Event]) {
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: now)              // Sunday = 1 ... Saturday = 7
        let back = wd == 1 ? -2 : wd == 7 ? -1 : 6 - wd           // Saturday/Sunday look back to Friday
        let friday = cal.date(byAdding: .day, value: back, to: cal.startOfDay(for: now)) ?? now
        let from = max(now, cal.date(bySettingHour: 16, minute: 0, second: 0, of: friday) ?? friday)
        let to = cal.date(byAdding: .day, value: 3, to: friday) ?? now
        let all = events.filter { ($0.startDate >= from && $0.startDate < to) || ($0.isHappeningNow && $0.startDate >= friday) }
        var seen = Set<String>()
        let top = all.sorted { SmartSearch.shared.baseRank($0) > SmartSearch.shared.baseRank($1) }
            .filter { seen.insert(SmartSearch.norm($0.title)).inserted }
        return (all, Array(top.prefix(4)))
    }
}

/// "Hey Siri, where's free food in CoMo Events?"
struct FreeFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Find free food"
    static var description = IntentDescription("Events in Columbia, MO that mention free food, today and the next few days.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let now = Date()
        let soon = FeedCache.loadEvents().filter { $0.isFreeFood && $0.effectiveEnd >= now && $0.startDate < now.addingTimeInterval(4 * 86_400) }
            .sorted { $0.startDate < $1.startDate }
        guard let first = soon.first else {
            return .result(dialog: "No free food listed in the next few days.") { EmptySnippet(text: "No free food listed yet") }
        }
        let today = soon.filter { Calendar.current.isDateInToday($0.startDate) }
        let dialog: IntentDialog
        if let t = today.first {
            dialog = IntentDialog("\(today.count) with free food today. First up: \(t.title), \(t.timeText)\(t.venue.map { " at \($0)" } ?? "").")
        } else {
            dialog = IntentDialog("Nothing today, but \(first.title) on \(Event.dayFormatter.string(from: first.startDate)) has free food.")
        }
        return .result(dialog: dialog) { EventsSnippet(heading: "Free food · \(soon.count)", events: Array(soon.prefix(4)), showDay: true) }
    }
}

/// "Hey Siri, is it game day in CoMo Events?"
struct GameDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Game day"
    static var description = IntentDescription("Today's Mizzou home game, or the next one.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let events = FeedCache.loadEvents()
        let cal = Calendar.current
        let today = GameDay.today
        if let game = GameDay.homeGame(on: today, in: events) {
            let plan = GameDay.plan(for: game, on: today, in: events)
            var line = "It's game day! \(game.title), \(game.timeText)\(game.venue.map { " at \($0)" } ?? "")."
            if let pre = plan.before.first { line += " Before: \(pre.title)." }
            if let aft = plan.after.first { line += " After: \(aft.title)." }
            let shown = [game] + Array(plan.before.prefix(1)) + Array(plan.after.prefix(2))
            return .result(dialog: IntentDialog(stringLiteral: line)) { EventsSnippet(heading: "Game day", events: shown, showDay: false) }
        }
        for d in 1...14 {
            guard let day = cal.date(byAdding: .day, value: d, to: today), let game = GameDay.homeGame(on: day, in: events) else { continue }
            return .result(dialog: IntentDialog("Not today. Next home game: \(game.title), \(Event.dayFormatter.string(from: game.startDate)) at \(game.timeText).")) {
                EventsSnippet(heading: "Next home game", events: [game], showDay: true)
            }
        }
        return .result(dialog: "No Mizzou home games in the next two weeks.") { EmptySnippet(text: "No home games soon") }
    }
}

/// "Open places in CoMo Events": bowling, escape rooms, trails, museums, coffee.
struct OpenPlacesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open places to go"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("places", forKey: "pendingTab")
        return .result()
    }
}

struct EventsSnippet: View {
    let heading: String
    let events: [Event]
    var showDay = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline)
            ForEach(events) { e in
                HStack(spacing: 10) {
                    Image(systemName: e.kind.symbol).foregroundStyle(.white).frame(width: 28, height: 28)
                        .background(e.kind.color, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text([showDay ? Event.dayFormatter.string(from: e.startDate) : nil, e.timeText, e.venue].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding()
    }
}
