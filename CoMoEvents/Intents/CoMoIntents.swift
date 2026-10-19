import AppIntents
import SwiftUI

/// "Hey Siri, what's happening in CoMo Events tonight?"
struct TonightIntent: AppIntent {
    static var title: LocalizedStringResource = "What's happening tonight"
    static var description = IntentDescription("Tells you what's on in Columbia, MO this evening.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let events = FeedCache.loadEvents()
        let cal = Calendar.current
        let now = Date()
        let tonight = events.filter { cal.isDateInToday($0.startDate) && $0.effectiveEnd >= now }
            .sorted { $0.startDate < $1.startDate }
        guard !tonight.isEmpty else {
            return .result(dialog: "Nothing left on the calendar tonight in Columbia. Try tomorrow.") { EmptySnippet() }
        }
        let top = Array(tonight.prefix(4))
        let spoken = top.map { "\($0.title) at \($0.venue ?? "Columbia"), \($0.timeText)" }.joined(separator: ". ")
        let dialog = IntentDialog("\(tonight.count) things tonight in CoMo. \(spoken).")
        return .result(dialog: dialog) { TonightSnippet(events: top, total: tonight.count) }
    }
}

/// "Open the CoMo Events map"
struct OpenMapIntent: AppIntent {
    static var title: LocalizedStringResource = "Open the events map"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("map", forKey: "pendingTab")
        return .result()
    }
}

struct CoMoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TonightIntent(),
                    phrases: ["What's happening in \(.applicationName) tonight",
                              "What's going on in \(.applicationName)",
                              "Show tonight's events in \(.applicationName)",
                              "Anything fun in \(.applicationName) tonight"],
                    shortTitle: "Tonight in CoMo",
                    systemImageName: "sparkles")
        AppShortcut(intent: OpenMapIntent(),
                    phrases: ["Open the \(.applicationName) map", "Show the map in \(.applicationName)"],
                    shortTitle: "Events map",
                    systemImageName: "map.fill")
    }
}

struct TonightSnippet: View {
    let events: [Event]
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tonight in CoMo · \(total)").font(.headline)
            ForEach(events) { e in
                HStack(spacing: 10) {
                    Image(systemName: e.kind.symbol).foregroundStyle(.white).frame(width: 28, height: 28)
                        .background(e.kind.color, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text([e.timeText, e.venue].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding()
    }
}
struct EmptySnippet: View { var body: some View { Text("Nothing tonight").padding() } }

/// The last feed the app saw, on disk, so intents can answer without the app running.
enum FeedCache {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("feed-cache.json")
    }
    static func save(_ data: Data) { try? data.write(to: url, options: .atomic) }
    static func loadEvents() -> [Event] {
        let data = (try? Data(contentsOf: url)) ?? (Bundle.main.url(forResource: "events", withExtension: "json").flatMap { try? Data(contentsOf: $0) })
        guard let data, let feed = try? JSONDecoder().decode(Feed.self, from: data) else { return [] }
        return feed.events
    }
}
