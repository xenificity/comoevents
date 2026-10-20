import SwiftUI
import VisionKit
import AVFoundation

/// Camera scanner for QR codes. Result: a URL string (or raw text). Needs a real device.
struct QRScanView: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (String) -> Void
    @State private var denied = false

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable && !denied {
                    Scanner { text in onResult(text); dismiss() }
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Camera not available",
                                           systemImage: "qrcode.viewfinder",
                                           description: Text(denied ? "Allow camera access for CoMo Events in Settings." : "QR scanning needs a real iPhone with a camera. You can paste a link instead."))
                }
            }
            .navigationTitle("Scan a QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
            }
            .overlay(alignment: .bottom) {
                Text("Point at a poster or ticket QR code").font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8).glass(Capsule()).padding(.bottom, 24)
            }
        }
    }

    struct Scanner: UIViewControllerRepresentable {
        let onText: (String) -> Void
        func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }
        func makeUIViewController(context: Context) -> DataScannerViewController {
            let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                               qualityLevel: .balanced, recognizesMultipleItems: false,
                                               isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
            vc.delegate = context.coordinator
            try? vc.startScanning()
            return vc
        }
        func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
        static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onText: (String) -> Void
            var fired = false
            init(onText: @escaping (String) -> Void) { self.onText = onText }
            func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
                guard !fired else { return }
                for item in addedItems {
                    if case .barcode(let b) = item, let s = b.payloadStringValue {
                        fired = true; scanner.stopScanning(); onText(s); return
                    }
                }
            }
        }
    }
}

/// Reads a web page's title and any JSON-LD Event so a scanned link can prefill the post form.
enum LinkPrefill {
    struct Result { var title = ""; var start: Date?; var end: Date?; var venue = ""; var address = ""; var details = ""; var link = "" }

    static func fetch(_ urlString: String) async -> Result {
        var r = Result(); r.link = urlString
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme ?? "") else { return r }
        var req = URLRequest(url: url); req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (iPhone) CoMoEvents", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req), let html = String(data: data, encoding: .utf8) else { return r }
        if let m = html.range(of: #"<title[^>]*>([^<]{1,160})"#, options: .regularExpression) {
            r.title = String(html[m]).replacingOccurrences(of: #"<title[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // JSON-LD Event block
        let pattern = #"<script[^>]*application/ld\+json[^>]*>([\s\S]*?)</script>"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let rg = Range(m.range(at: 1), in: html), let d = html[rg].data(using: .utf8) else { continue }
                func walk(_ x: Any) -> [String: Any]? {
                    if let dict = x as? [String: Any] {
                        if let t = dict["@type"] as? String, t.hasSuffix("Event") { return dict }
                        for v in dict.values { if let f = walk(v) { return f } }
                    } else if let arr = x as? [Any] { for v in arr { if let f = walk(v) { return f } } }
                    return nil
                }
                if let obj = try? JSONSerialization.jsonObject(with: d), let ev = walk(obj) {
                    if let n = ev["name"] as? String { r.title = n }
                    if let s = ev["startDate"] as? String { r.start = Event.parse(s) ?? ISO8601DateFormatter().date(from: s + "T00:00:00Z") }
                    if let e = ev["endDate"] as? String { r.end = Event.parse(e) }
                    if let desc = ev["description"] as? String { r.details = String(desc.prefix(500)) }
                    if let loc = ev["location"] as? [String: Any] {
                        r.venue = loc["name"] as? String ?? ""
                        if let a = loc["address"] as? [String: Any] { r.address = [a["streetAddress"], a["addressLocality"]].compactMap { $0 as? String }.joined(separator: ", ") }
                        else if let a = loc["address"] as? String { r.address = a }
                    }
                    break
                }
            }
        }
        return r
    }
}
