import SwiftUI

/// Game day mode: on a Mizzou home game day, one screen with the game, tailgates and watch parties,
/// and what's on after. Mirrors docs/extras.js (homeGame / gameDayPlan).
enum GameDay {
    private static let homeVenue = try! NSRegularExpression(pattern: "faurot|memorial stadium|mizzou arena|hearnes|champions dr|walton stadium|taylor stadium|mizzou softball|simmons field|university of missouri", options: [.caseInsensitive])
    private static let sport = try! NSRegularExpression(pattern: "football|basketball|volleyball|gymnastics|wrestling|soccer|softball|baseball", options: [.caseInsensitive])
    private static let pre = try! NSRegularExpression(pattern: "tailgat|watch party|watch-party|pregame|pre-game|game ?day|tiger walk|homecoming|fan fest|kickoff party", options: [.caseInsensitive])

    private static func has(_ rx: NSRegularExpression, _ s: String) -> Bool { rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    /// The day to show. Debug builds can preview a date: launch with GAMEDAY=2026-11-21.
    static var today: Date {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["GAMEDAY"] {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: s) { return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d }
        }
        #endif
        return Date()
    }

    static func homeGame(on day: Date, in all: [Event]) -> Event? {
        let cal = Calendar.current
        let games = all.filter { e in
            guard cal.isDate(e.startDate, inSameDayAs: day) else { return false }
            let t = e.title
            guard e.kinds.contains(.sports) || has(sport, t), t.range(of: "mizzou|missouri|tigers", options: [.regularExpression, .caseInsensitive]) != nil, has(sport, t) else { return false }
            if t.range(of: #"\b(at|@)\s+[A-Z]"#, options: .regularExpression) != nil && t.range(of: #"\bvs\.?\b"#, options: [.regularExpression, .caseInsensitive]) == nil { return false }
            return has(homeVenue, "\(e.venue ?? "") \(e.address ?? "")") || t.range(of: #"\b(mizzou|missouri)\b[^v]*\bvs\.?"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func rank(_ e: Event) -> Int { e.title.localizedCaseInsensitiveContains("football") ? 3 : e.title.localizedCaseInsensitiveContains("basketball") ? 2 : 1 }
        return games.max { (rank($0), $0.score ?? 0) < (rank($1), $1.score ?? 0) }
    }

    struct Plan { var before: [Event]; var after: [Event]; var also: [Event] }

    static func plan(for game: Event, on day: Date, in all: [Event]) -> Plan {
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: day)
        let dayEnd = d0.addingTimeInterval(86_400), lateEnd = dayEnd.addingTimeInterval(3 * 3600)
        let kickoff = game.startDate, after = kickoff.addingTimeInterval(3 * 3600)
        // The opponent ("Kentucky" in "Football - Missouri vs. Kentucky"): other listings of the same game mention it.
        var opp = ""
        if let r = game.title.range(of: #"\bvs\.?\s*"#, options: [.regularExpression, .caseInsensitive]) {
            let rest = game.title[r.upperBound...]
            opp = rest.split(whereSeparator: { !$0.isLetter }).first.map { String($0).lowercased() } ?? ""
        }
        let sameGame: (Event) -> Bool = { !opp.isEmpty && $0.title.lowercased().contains(opp) }
        let near = all.filter { $0.id != game.id && $0.startDate >= d0 && $0.startDate < lateEnd }
        let dayOnly = near.filter { $0.startDate < dayEnd }
        let before = dayOnly.filter { has(pre, "\($0.title) \($0.description ?? "")") && $0.startDate <= kickoff.addingTimeInterval(3600) && !sameGame($0) }
        let afterList = near.filter { $0.startDate >= after.addingTimeInterval(-1800) && $0.kinds.contains { [.nightlife, .music, .party].contains($0) } }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        let also = dayOnly.filter { e in !before.contains(e) && !afterList.contains(e) && !sameGame(e) && e.kinds.contains(.sports)
            && e.title.range(of: "mizzou|missouri|tigers", options: [.regularExpression, .caseInsensitive]) != nil }
        return Plan(before: Array(before.prefix(8)), after: Array(afterList.prefix(8)), also: Array(also.prefix(4)))
    }
}

struct GameDayBanner: View {
    @EnvironmentObject var store: EventStore
    @State private var showPlan = false

    var body: some View {
        let day = GameDay.today
        if let game = GameDay.homeGame(on: day, in: store.events) {
            Button { Analytics.tap("gameday"); showPlan = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.yellow)
                        .frame(width: 34, height: 34).background(Theme.ink, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GAME DAY").font(.caption2.weight(.heavy)).tracking(0.8)
                        Text("\(game.title) · \(game.timeText)").font(.footnote.weight(.semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("Plan ›").font(.footnote.weight(.heavy))
                }
                .foregroundStyle(Theme.ink)
                .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                .background(LinearGradient(colors: [Theme.yellow, .orange.opacity(0.85)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Game day: \(game.title) at \(game.timeText). Open the game day plan.")
            .sheet(isPresented: $showPlan) { GameDayView(game: game, day: day) }
        }
    }
}

struct GameDayView: View {
    @EnvironmentObject var store: EventStore
    let game: Event
    let day: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = GameDay.plan(for: game, on: day, in: store.events)
        NavigationStack {
            ZStack {
                Theme.page
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("The game", "trophy.fill") {
                            NavigationLink(value: game) { EventCard(event: game, showDay: false) }.buttonStyle(CardPressStyle())
                        }
                        strip("Before: tailgates and watch parties", "party.popper.fill", plan.before,
                              empty: "No tailgates or watch parties listed yet. Bars downtown fill up early on game day.")
                        strip("After the game", "moon.stars.fill", plan.after, empty: "Nothing listed for after the game yet.")
                        if !plan.also.isEmpty { strip("More Mizzou today", "sportscourt.fill", plan.also, empty: "") }
                        Text("Parking near Faurot Field and Mizzou Arena fills up fast: the MKT trail and the free campus shuttles from downtown are the easy way in.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Game day")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline).labelStyle(TintedIconLabel())
            content()
        }
    }

    @ViewBuilder private func strip(_ title: String, _ symbol: String, _ list: [Event], empty: String) -> some View {
        section(title, symbol) {
            if list.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(list) { e in NavigationLink(value: e) { MiniCard(event: e) }.buttonStyle(CardPressStyle()) }
                    }.padding(.horizontal, 16)
                }.padding(.horizontal, -16)
            }
        }
    }
}

private struct TintedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(Theme.gold); configuration.title }
    }
}
