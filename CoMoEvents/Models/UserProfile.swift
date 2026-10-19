import Foundation

/// What we keep about a person. Lives on the device always; mirrored to the user's private
/// iCloud database once they sign in with Apple, so it follows them to a new phone.
struct UserProfile: Codable, Equatable {
    var displayName: String = ""
    var interests: [String] = []          // Category raw values
    var audience: String? = nil           // Audience raw value ("singles", "couples", ...)
    var favorites: [String] = []          // Event ids
    var updatedAt: Date = .distantPast

    var interestSet: Set<Category> { Set(interests.compactMap(Category.init(rawValue:))) }
    var audiencePick: Audience? { audience.flatMap(Audience.init(rawValue:)) }
    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined().uppercased()
        return s.isEmpty ? "☺︎" : s
    }

    /// Newest wins per field group; favorites are unioned so nothing a person saved is lost.
    func merged(with other: UserProfile) -> UserProfile {
        var newer = updatedAt >= other.updatedAt ? self : other
        newer.favorites = Array(Set(favorites).union(other.favorites))
        if newer.displayName.isEmpty { newer.displayName = updatedAt >= other.updatedAt ? other.displayName : displayName }
        return newer
    }
}
