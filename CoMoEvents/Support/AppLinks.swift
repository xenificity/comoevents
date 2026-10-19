import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Install links used everywhere the app promotes itself (share cards, invites).
///
/// Every link goes through the website's /get/ page, which sends people to the App Store once
/// CoMo Events is live there and to the public TestFlight beta until then. That way printed QR
/// codes and links already shared never go stale, and the `c` parameter becomes the App Store
/// campaign token (`ct`) so App Analytics can tell channels apart. See Marketing/campaign-links.md.
enum AppLinks {
    static let website = URL(string: "https://xenificity.github.io/comoevents/")!

    static func install(campaign: String) -> URL {
        URL(string: "https://xenificity.github.io/comoevents/get/?c=\(campaign)")!
    }

    /// Short human-readable form for text that people may retype.
    static let displayInstall = "xenificity.github.io/comoevents"

    /// Crisp QR code for a URL, black on white, at the requested point size.
    static func qrImage(for url: URL, size: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(size / output.extent.width))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Text for the "Invite friends" share sheet.
    static func inviteText(friendCode: String?) -> String {
        var s = "I use CoMo Events to see everything happening in Columbia on one map: Mizzou, downtown, music, parties, markets. It is free, no ads."
        if let code = friendCode, !code.isEmpty { s += " Add me with my friend code \(code)." }
        s += "\nGet it: \(install(campaign: "invite").absoluteString)"
        return s
    }
}
