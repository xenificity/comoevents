import Foundation

/// First line of defence for guideline 1.2: rejects posts and names containing slurs or explicit terms.
/// Deliberately simple and conservative; a human moderator still approves every post.
enum ContentFilter {
    private static let blocked: [String] = [
        "fuck", "fucking", "motherfucker", "shit", "bullshit", "asshole", "bitch", "bitches", "cunt", "dick", "dicks", "cock", "pussy",
        "whore", "slut", "faggot", "fag", "dyke", "tranny", "retard", "retarded", "nigger", "nigga", "chink", "spic", "kike", "wetback",
        "towelhead", "raghead", "porn", "porno", "xxx", "nude", "nudes", "escort", "escorts", "onlyfans", "hookup", "blowjob", "handjob",
        "rape", "molest", "kill yourself", "kys", "heroin", "meth", "cocaine", "fentanyl",
    ]
    private static let patterns: [NSRegularExpression] = blocked.compactMap {
        try? NSRegularExpression(pattern: "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: $0) + "(?![a-z0-9])", options: [.caseInsensitive])
    }

    /// Returns the first offending term, or nil when the text is acceptable.
    static func offendingTerm(in text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "3", with: "e").replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "$", with: "s").replacingOccurrences(of: "@", with: "a")
        let range = NSRange(normalized.startIndex..., in: normalized)
        for (i, p) in patterns.enumerated() where p.firstMatch(in: normalized, range: range) != nil {
            return blocked[i]
        }
        return nil
    }

    static func isClean(_ text: String) -> Bool { offendingTerm(in: text) == nil }

    /// Display-safe version of a user-chosen name.
    static func safeName(_ name: String, fallback: String = "A CoMo Events user") -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || !isClean(t) ? fallback : t
    }
}
