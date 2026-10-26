import Foundation
import Vision
import UIKit

/// Reads an event flyer photo on the iPhone (Vision text recognition, no network) and pulls out what the
/// Post an event form needs: the biggest text is the title; dates, times, addresses, links and prices are
/// detected; a known venue named on the flyer fills the place. Everything stays editable in the form.
enum FlyerScanner {
    struct Result {
        var title = "", venue = "", address = "", price = "", link = "", details = ""
        var start: Date?
        var end: Date?
        var foundAnything: Bool { !title.isEmpty || start != nil || !venue.isEmpty || !address.isEmpty }
    }

    struct Line { let text: String; let height: CGFloat; let top: CGFloat }

    static func read(_ image: UIImage) async -> Result {
        var lines = await recognize(image, level: .accurate)
        if lines.isEmpty { lines = await recognize(image, level: .fast) }   // accurate can fail without a Neural Engine (Simulator, old phones)
        #if DEBUG
        for l in lines { NSLog("FlyerScanner line h=%.3f top=%.3f %@", l.height, l.top, l.text) }
        #endif
        return parse(lines)
    }

    // MARK: text recognition

    private static func recognize(_ image: UIImage, level: VNRequestTextRecognitionLevel) async -> [Line] {
        let img = image.scaledDown(maxSide: 2400)
        guard let cg = img.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { print("FlyerScanner", level == .fast ? "fast" : "accurate", err.localizedDescription) }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = obs.compactMap { o -> Line? in
                    guard let c = o.topCandidates(1).first, c.confidence >= 0.3 else { return nil }   // low confidence = artwork read as letters
                    let t = c.string.trimmingCharacters(in: .whitespaces)
                    return t.isEmpty ? nil : Line(text: t, height: o.boundingBox.height, top: 1 - o.boundingBox.maxY)
                }
                cont.resume(returning: lines.sorted { $0.top < $1.top })
            }
            req.recognitionLevel = level
            req.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, orientation: .init(img.imageOrientation)).perform([req]) }
                catch { cont.resume(returning: []) }
            }
        }
    }

    // MARK: parsing

    static func parse(_ lines: [Line]) -> Result {
        var r = Result()
        let full = lines.map(\.text).joined(separator: "\n")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue
                                           | NSTextCheckingResult.CheckingType.address.rawValue
                                           | NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(full.startIndex..., in: full)
        var dateLines = Set<String>()
        for m in detector?.matches(in: full, range: range) ?? [] {
            switch m.resultType {
            case .date:
                if r.start == nil, let d = m.date {
                    r.start = futureDate(d)
                    if m.duration > 0 { r.end = r.start?.addingTimeInterval(m.duration) }
                    if let rr = Range(m.range, in: full) { dateLines.insert(String(full[rr]).lowercased()) }
                }
            case .address:
                if r.address.isEmpty, let rr = Range(m.range, in: full) { r.address = String(full[rr]).replacingOccurrences(of: "\n", with: ", ") }
            case .link:
                if r.link.isEmpty, let u = m.url, u.scheme?.hasPrefix("http") == true { r.link = u.absoluteString }
            default: break
            }
        }
        if r.start == nil, let (d, matched) = monthDay(in: full) { r.start = d; dateLines.insert(matched.lowercased()) }
        applyTimes(full, to: &r)

        // Title: the tallest line plus neighbours of similar size ("The Vendor" / "Village").
        // Title candidates: real words (not "The V"), not the date line, not an "at …" place line.
        func wordy(_ t: String) -> Bool {
            let words = t.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }
            return words.count >= 2 || words.contains { $0.count >= 5 }
        }
        let candidates = lines.filter { l in
            let low = l.text.lowercased()
            return l.text.count >= 3 && wordy(l.text) && low.range(of: #"^(at|@)\s"#, options: .regularExpression) == nil
                && !dateLines.contains(where: { low.contains($0) }) && !low.hasPrefix("www") && !low.contains("http")
        }
        if let biggest = candidates.max(by: { $0.height < $1.height }) {
            // Grow the title block up and down through neighbouring big lines ("The Vendor" above "Village").
            let sorted = candidates.sorted { $0.top < $1.top }
            var lo = sorted.firstIndex { $0.text == biggest.text && $0.top == biggest.top } ?? 0, hi = lo
            func joins(_ a: Line, _ b: Line) -> Bool {   // b directly below a
                b.height >= biggest.height * 0.45 && b.top - (a.top + a.height) < biggest.height * 0.6
            }
            while lo > 0, sorted[lo - 1].height >= biggest.height * 0.45, joins(sorted[lo - 1], sorted[lo]) { lo -= 1 }
            while hi + 1 < sorted.count, joins(sorted[hi], sorted[hi + 1]) { hi += 1 }
            r.title = sorted[lo...hi].map(\.text).joined(separator: " ").capitalizedIfShouting
        } else if let d = dateLines.first, let line = lines.first(where: { $0.text.lowercased().contains(d) }) {
            // "HALLOWEEN MARKET - OCTOBER 31ST" → "Halloween Market"
            let rest = line.text.lowercased().replacingOccurrences(of: d, with: "")
                .replacingOccurrences(of: #"[-–—|•·:,]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if wordy(rest) { r.title = rest.capitalized }
        }

        // Place: a known venue named anywhere, else an "at …" line.
        if let v = VenueLookup.mentioned(in: full) {
            r.venue = v.name
            if r.address.isEmpty, let a = v.address { r.address = a }
        } else if let atLine = lines.first(where: { $0.text.range(of: #"^(at|@)\s+\S"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
            r.venue = atLine.text.replacingOccurrences(of: #"^(at|@)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]).capitalizedIfShouting
        }

        if full.range(of: #"\bfree\b"#, options: [.regularExpression, .caseInsensitive]) != nil { r.price = "Free" }
        else if let p = full.range(of: #"\$\s?\d+(\.\d{2})?"#, options: .regularExpression) { r.price = String(full[p]).replacingOccurrences(of: " ", with: "") }

        let titleWords = Set(r.title.lowercased().split(separator: " "))
        r.details = lines.map(\.text).filter { !titleWords.isSuperset(of: Set($0.lowercased().split(separator: " "))) }
            .joined(separator: " ").prefix(800).description
        return r
    }

    /// "10am-2pm", "7:30 PM", "6 - 9 pm": put the times on the found day.
    private static func applyTimes(_ text: String, to r: inout Result) {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*(?:-|–|—|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)"#
        let single = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)"#
        guard let day = r.start else { return }
        let cal = Calendar.current
        func at(_ h: String, _ m: String?, _ ap: String?) -> Date? {
            guard var hour = Int(h), hour <= 12 else { return nil }
            let pm = (ap ?? "").lowercased().hasPrefix("p")
            if pm && hour < 12 { hour += 12 }
            if !pm && (ap ?? "").lowercased().hasPrefix("a") && hour == 12 { hour = 0 }
            return cal.date(bySettingHour: hour, minute: Int(m ?? "0") ?? 0, second: 0, of: day)
        }
        let ns = text as NSString
        if let m = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            let endAP = g(6)
            if let s = at(g(1)!, g(2), g(3) ?? endAP), let e = at(g(4)!, g(5), endAP) {
                r.start = s; r.end = e > s ? e : e.addingTimeInterval(12 * 3600)
            }
        } else if let m = try? NSRegularExpression(pattern: single, options: .caseInsensitive).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            if let s = at(g(1)!, g(2), g(3)) { r.start = s; r.end = nil }
        }
    }

    /// "OCTOBER 31ST", "Oct. 31", "Sat Nov 7th 2026", "10/31" — forgiving the usual OCR slips (I or l for 1, O for 0).
    private static func monthDay(in text: String) -> (Date, String)? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let ns = text as NSString
        let named = #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+([0-3OIl]?[0-9OIl])(?:st|nd|rd|th)?\b(?:,?\s*(20\d\d))?"#
        let numeric = #"\b(1[0-2]|0?[1-9])/([0-3]?[0-9])(?:/(20)?(\d\d))?\b"#
        func digits(_ s: String) -> Int? { Int(s.replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "o", with: "0").replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "l", with: "1")) }
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        if let m = try? NSRegularExpression(pattern: named).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
           let mi = months.firstIndex(of: String(ns.substring(with: m.range(at: 1)).lowercased().prefix(3))),
           let day = digits(ns.substring(with: m.range(at: 2))), (1...31).contains(day) {
            let year = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) ?? thisYear : thisYear
            if let d = cal.date(from: DateComponents(year: year, month: mi + 1, day: day, hour: 12)) { return (futureDate(d), ns.substring(with: m.range)) }
        }
        if let m = try? NSRegularExpression(pattern: numeric).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
           let mo = Int(ns.substring(with: m.range(at: 1))), let day = Int(ns.substring(with: m.range(at: 2))), (1...31).contains(day) {
            let year = m.range(at: 4).location != NSNotFound ? 2000 + (Int(ns.substring(with: m.range(at: 4))) ?? 0) : thisYear
            if let d = cal.date(from: DateComponents(year: year, month: mo, day: day, hour: 12)) { return (futureDate(d), ns.substring(with: m.range)) }
        }
        return nil
    }

    /// Flyers rarely print the year: a date that already passed this year means next year.
    private static func futureDate(_ d: Date) -> Date {
        d < Date().addingTimeInterval(-86_400) ? (Calendar.current.date(byAdding: .year, value: 1, to: d) ?? d) : d
    }
}

private extension String {
    /// "HALLOWEEN MARKET" → "Halloween Market"; mixed-case text is left alone.
    var capitalizedIfShouting: String { self == uppercased() && count > 3 ? capitalized : self }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up; case .down: self = .down; case .left: self = .left; case .right: self = .right
        case .upMirrored: self = .upMirrored; case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored; case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
