import Foundation

/// Smart search + ranking. Mirrors docs/search.js; change both together.
///
/// - Concepts come from search.json (bundled, refreshed from comoevent.com). The feed tags events with
///   the same concepts (`Event.tags`, "x~" = only the description mentions it).
/// - A query becomes units: a concept (typos forgiven: "intellignece", "shanti") or a plain word.
/// - Rank = relevance + quality (`Event.score`) + what this person likes (`TasteProfile`) + how soon.
@MainActor
final class SmartSearch {
    static let shared = SmartSearch()

    struct Unit { var concepts: Set<String>?; var words: [String]; var broad: Bool; var label: String }
    struct Parsed { var units: [Unit]; var time: String? }
    struct Hit { let event: Event; let rel: Double; let rank: Double }

    private struct Alias { let words: [String]; let key: String; let head: Bool }
    private(set) var labels: [String: String] = [:]
    private var conceptCategory: [String: String] = [:]
    private var aliases: [Alias] = []
    private(set) var stop: Set<String> = []
    private var timeWords: [String: String] = [:]
    private var vocab: Set<String> = []
    private(set) var ready = false

    static let remoteURL = URL(string: "https://comoevent.com/search.json")!

    private init() {
        if let url = Bundle.main.url(forResource: "search", withExtension: "json"), let data = try? Data(contentsOf: url) { load(data) }
    }

    func refresh() async {
        var req = URLRequest(url: Self.remoteURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 { load(data) }
    }

    func load(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cs = root["concepts"] as? [String: [String: Any]] else { return }
        var al: [Alias] = [], lab: [String: String] = [:], cat: [String: String] = [:]
        for (k, c) in cs {
            let label = c["label"] as? String ?? k
            let query = c["query"] as? [String] ?? []
            lab[k] = label
            if let category = c["category"] as? String { cat[k] = category }
            // Head words name the whole topic ("tech", "church"); other aliases are narrower ("volleyball", "jazz").
            var heads: Set<String> = [Self.norm(k), Self.norm(label)]
            query.prefix(2).forEach { heads.insert(Self.norm($0)) }
            for q in query + [label] {
                let w = Self.words(q)
                if !w.isEmpty { al.append(Alias(words: w, key: k, head: heads.contains(w.joined(separator: " ")))) }
            }
        }
        aliases = al.sorted { $0.words.count != $1.words.count ? $0.words.count > $1.words.count : $0.key < $1.key }
        labels = lab; conceptCategory = cat
        stop = Set(root["stopwords"] as? [String] ?? [])
        var tw: [String: String] = [:]
        for (k, ws) in root["time"] as? [String: [String]] ?? [:] { ws.forEach { tw[$0] = k } }
        timeWords = tw
        ready = true
    }

    /// Words that really occur in titles, venues and organizers: a real word ("james") is never a typo ("games").
    func setVocab(_ events: [Event]) {
        var v = Set<String>()
        for e in events { v.formUnion(e.search.title); v.formUnion(e.search.venue); v.formUnion(e.search.org) }
        vocab = v
    }

    // MARK: text

    nonisolated static func norm(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = String.UnicodeScalarView()
        var space = true
        for ch in folded.unicodeScalars {
            if ch == "'" || ch == "’" { continue }
            if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) || ch == "+" || ch == "&" { out.append(ch); space = false }
            else if !space { out.append(" "); space = true }
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }
    nonisolated static func words(_ s: String?) -> [String] { norm(s).split(separator: " ").map(String.init) }

    /// Damerau-Levenshtein (optimal string alignment), stops early past `maxD`.
    nonisolated static func dist(_ a: [UInt8], _ b: [UInt8], _ maxD: Int) -> Int {
        if abs(a.count - b.count) > maxD { return maxD + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            var rowMin = Int.max
            for j in 1...b.count {
                var v = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { v = min(v, d[i - 2][j - 2] + 1) }
                d[i][j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > maxD { return maxD + 1 }
        }
        return d[a.count][b.count]
    }
    /// 1 exact, 0.85 typo, 0 no. Short words must match exactly.
    nonisolated static func wordSim(_ q: String, _ w: String) -> Double {
        if q == w { return 1 }
        let m = q.count >= 8 ? 2 : q.count >= 5 ? 1 : 0
        return m > 0 && dist(Array(q.utf8), Array(w.utf8), m) <= m ? 0.85 : 0
    }

    // MARK: query

    func parse(_ q: String) -> Parsed {
        let toks = Self.words(q)
        var units: [Unit] = [], time: String? = nil, i = 0
        while i < toks.count {
            if let t = timeWords[toks[i]] { time = t; i += 1; continue }
            if toks[i] == "this", i + 1 < toks.count, toks[i + 1] == "weekend" { time = "weekend"; i += 2; continue }
            // Longest alias phrase wins, then the closest spelling; ties add every concept they name.
            var hitN = 0, hitSim = 0.0, hitKeys: [String] = [], hitHead = false
            for al in aliases {
                let n = al.words.count
                if hitN > 0 && n < hitN { break }
                if i + n > toks.count { continue }
                var sim = 1.0
                for k in 0..<n where sim > 0 {
                    let t = toks[i + k]
                    var s1 = Self.wordSim(t, al.words[k])
                    if s1 < 1 && vocab.contains(t) { s1 = 0 }
                    sim = min(sim, s1)
                }
                if sim == 0 { continue }
                if hitN == 0 || sim > hitSim { hitN = n; hitSim = sim; hitKeys = [al.key]; hitHead = al.head }
                else if sim == hitSim { if !hitKeys.contains(al.key) { hitKeys.append(al.key) }; hitHead = hitHead || al.head }
            }
            if hitN > 0 {
                let span = Array(toks[i..<(i + hitN)])
                if let j = units.firstIndex(where: { u in u.concepts.map { !$0.isDisjoint(with: hitKeys) } ?? false }) {
                    units[j].concepts?.formUnion(hitKeys); units[j].words += span; units[j].broad = units[j].broad || hitHead
                } else {
                    units.append(Unit(concepts: Set(hitKeys), words: span, broad: hitHead, label: labels[hitKeys[0]] ?? hitKeys[0]))
                }
                i += hitN; continue
            }
            if !stop.contains(toks[i]) && toks[i].count >= 2 { units.append(Unit(concepts: nil, words: [toks[i]], broad: false, label: toks[i])) }
            i += 1
        }
        return Parsed(units: units, time: time)
    }

    private func fieldHit(_ q: String, _ list: [String], fuzzy: Bool) -> Double {
        var best = 0.0
        for w in list {
            if w == q { return 1 }
            if q.count >= 3 && w.hasPrefix(q) { best = max(best, 0.9) }
            else if fuzzy && best < 0.85 && !vocab.contains(q) && Self.wordSim(q, w) > 0 { best = 0.85 }
        }
        return best
    }
    /// Mean over the unit's words, so "mizzou football" needs both words to score fully.
    private func textScore(_ words: [String], _ e: Event) -> Double {
        let f = e.search
        var total = 0.0, n = 0
        for w in words where !stop.contains(w) {
            n += 1
            total += max(fieldHit(w, f.title, fuzzy: true), fieldHit(w, f.venue, fuzzy: true) * 0.85,
                         fieldHit(w, f.org, fuzzy: false) * 0.7, fieldHit(w, f.desc, fuzzy: false) * 0.4,
                         f.cats.contains(w) ? 0.8 : 0)
        }
        return n > 0 ? total / Double(n) : 0
    }
    private func conceptScore(_ concepts: Set<String>, _ e: Event) -> Double {
        var best = 0.0
        for k in concepts {
            if e.tags.contains(k) { best = 1 }
            else if best < 0.5 && e.tags.contains(k + "~") { best = 0.5 }
            if let cat = conceptCategory[k], e.categories.contains(cat) { best = 1 }
        }
        return best
    }
    /// 0...~1 relevance, 0 if the event doesn't answer enough of the query.
    /// loose: accept events that answer any part (used when nothing answers all of it).
    func relevance(_ p: Parsed, _ e: Event, loose: Bool = false) -> Double {
        guard !p.units.isEmpty else { return 1 }
        var sum = 0.0, hits = 0
        for u in p.units {
            var s: Double
            if let cs = u.concepts {
                // "tech": every tech-tagged event counts fully, a stray "Tennessee Tech" title less.
                // "volleyball": the word itself first, other sports after.
                let c = conceptScore(cs, e), t = textScore(u.words, e)
                s = u.broad ? max(c, t * (c > 0 ? 1 : 0.6)) + (c > 0 && t >= 0.85 ? 0.15 : 0) : max(c * 0.55, t)
            } else {
                s = textScore(u.words, e)
            }
            if s >= 0.3 { hits += 1 } else { s = 0 }
            sum += s
        }
        let need = loose ? 1 : p.units.count <= 2 ? p.units.count : p.units.count - 1
        return hits >= need ? sum / Double(p.units.count) : 0
    }

    /// Ranked search: best first, the loosely related tail dropped when strong matches exist, and repeats
    /// of the same title + venue collapsed to the soonest. Applies time words ("tonight", "this weekend").
    func search(_ q: String, in list: [Event], now: Date = Date(), going: (Event) -> Int = { _ in 0 }) -> (hits: [Hit], parsed: Parsed) {
        let p = parse(q)
        var out: [Hit] = []
        for pass in 0..<2 where out.isEmpty {
            for e in list {
                let r = relevance(p, e, loose: pass == 1)
                if r > 0 { out.append(Hit(event: e, rel: r, rank: searchRank(r, e, now: now, going: going(e)))) }
            }
            if p.units.count < 2 { break }
        }
        let top = out.map(\.rel).max() ?? 0
        if top >= 0.85 { out = out.filter { $0.rel >= 0.6 * top } }
        out.sort { $0.rank > $1.rank }
        var seen = Set<String>()
        out = out.filter { seen.insert(Self.norm($0.event.title) + "|" + Self.norm($0.event.venue)).inserted }
        if let t = p.time {
            let cal = Calendar.current
            out = out.filter { h in
                switch t {
                case "today": return TimeWindow.today.contains(h.event, now: now)
                case "tomorrow": return cal.isDateInTomorrow(h.event.startDate)
                default: return TimeWindow.weekend.contains(h.event, now: now)
                }
            }
        }
        return (out, p)
    }

    // MARK: ranking

    /// Without a query: quality + taste + popularity (going count).
    func baseRank(_ e: Event, going: Int = 0) -> Double {
        Double(e.score ?? 40) * 0.6 + TasteProfile.shared.personal(e) + Double(min(going, 5)) * 2
    }
    func searchRank(_ rel: Double, _ e: Event, now: Date, going: Int = 0) -> Double {
        let days = e.startDate.timeIntervalSince(now) / 86_400
        let soon: Double = days < 2 ? 10 : days < 7 ? 6 : days < 30 ? 2 : 0
        return rel * 60 + Double(e.score ?? 40) * 0.25 + TasteProfile.shared.personal(e) + soon + Double(min(going, 5))
    }
    /// Day by day; inside a day, happening-now first, then the best-ranked.
    func rankWithinDays(_ list: [Event], going: (Event) -> Int = { _ in 0 }) -> [Event] {
        let cal = Calendar.current, now = Date()
        return list.map { e in (e: e, d: cal.startOfDay(for: e.startDate), live: e.startDate <= now && e.effectiveEnd >= now, r: baseRank(e, going: going(e))) }
            .sorted { a, b in
                if a.d != b.d { return a.d < b.d }
                if a.live != b.live { return a.live }
                if a.r != b.r { return a.r > b.r }
                return a.e.startDate < b.e.startDate
            }
            .map(\.e)
    }
}

/// What this person likes, learned on this device only from saves (3), Going / I'm here / Went (4) and
/// opened events (1), plus profile interests. Mirrors the taste part of docs/search.js.
@MainActor
final class TasteProfile {
    static let shared = TasteProfile()
    private static let key = "taste.v1"
    private var weights: [String: Double]

    private init() { weights = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Double] ?? [:] }

    var hasTaste: Bool { !weights.isEmpty }

    private func features(_ e: Event) -> [String] {
        let stop = SmartSearch.shared.stop
        var out = e.categories.map { "c:" + $0 }
        out += e.tags.filter { !$0.hasSuffix("~") && !["downtown", "campus", "free"].contains($0) }.map { "t:" + $0 }
        if let v = e.venue { out.append("v:" + SmartSearch.norm(v)) }
        out += e.search.title.filter { $0.count >= 4 && !stop.contains($0) && Int($0) == nil }.map { "w:" + $0 }
        return out
    }

    func learn(_ e: Event, _ weight: Double) {
        guard weight != 0 else { return }
        for f in features(e) {
            let v = max(0, (weights[f] ?? 0) + weight)
            weights[f] = v > 0 ? v : nil
        }
        save()
    }
    func seed(_ categories: [String]) {
        for c in categories where weights["c:" + c] == nil { weights["c:" + c] = 2 }
        save()
    }
    func reset() { weights = [:]; save() }

    /// 0...18 boost for how well the event fits what this person saves, attends and opens.
    func personal(_ e: Event) -> Double {
        guard !weights.isEmpty else { return 0 }
        var raw = 0.0
        for f in features(e) {
            guard let w = weights[f] else { continue }
            raw += w * (f.hasPrefix("v:") ? 1.4 : f.hasPrefix("t:") ? 1 : f.hasPrefix("c:") ? 0.8 : 0.35)
        }
        return 18 * (1 - exp(-raw / 10))
    }

    private func save() {
        if weights.count > 400 {
            for k in weights.sorted(by: { $0.value < $1.value }).prefix(weights.count - 400).map(\.key) { weights[k] = nil }
        }
        UserDefaults.standard.set(weights, forKey: Self.key)
    }
}
