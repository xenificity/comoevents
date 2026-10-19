import SwiftUI
import UIKit
import EventKit
import EventKitUI

/// A square card rendered to an image for sharing (Messages, Instagram stories, AirDrop).
struct ShareCard: View {
    let event: Event
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [event.kind.color, event.kind.color.opacity(0.6), Theme.ink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: event.kind.symbol)
                .font(.system(size: 260, weight: .bold))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 160, y: -140)
            // Scrim so white text stays readable on light category colours (campus yellow, etc.).
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.85)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(event.timeText).font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink).padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.yellow, in: Capsule())
                    Text(Event.dayFormatter.string(from: event.startDate)).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
                Text(event.title).font(.system(size: 54, weight: .heavy)).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.6)
                if let v = event.venue { Label(v, systemImage: "mappin").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.9)) }
                HStack {
                    Image(systemName: "map.fill").foregroundStyle(Theme.yellow)
                    Text("CoMo Events · Columbia, MO").font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 10)
            }
            .padding(56)
            .padding(.trailing, 230)   // keep text clear of the QR code
        }
        .overlay(alignment: .bottomTrailing) { installBadge }
        .frame(width: 1080, height: 1080)
    }

    /// "Get the app" QR in the corner, so every shared card is also an invite.
    private var installBadge: some View {
        VStack(spacing: 8) {
            if let qr = AppLinks.qrImage(for: AppLinks.install(campaign: "share"), size: 170) {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 170, height: 170)
            }
            Text("Get the app").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.yellow, lineWidth: 6))
        .padding(48)
    }
}

@MainActor
func renderShareCard(for event: Event) -> UIImage? {
    let r = ImageRenderer(content: ShareCard(event: event))
    r.scale = 1
    return r.uiImage
}

/// UIActivityViewController wrapper: share image + text together.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Apple's own "new event" sheet, prefilled. Needs only write access, asked on first use.
struct CalendarEditSheet: UIViewControllerRepresentable {
    let event: Event
    @Environment(\.dismiss) private var dismiss
    static let store = EKEventStore()

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = Self.store
        let ek = EKEvent(eventStore: Self.store)
        ek.title = event.title
        ek.startDate = event.startDate
        ek.endDate = event.endDate ?? event.startDate.addingTimeInterval(2 * 3600)
        ek.isAllDay = event.allDay
        ek.location = event.placeText.isEmpty ? nil : event.placeText
        ek.notes = [event.description, event.url].compactMap { $0 }.joined(separator: "\n\n")
        if let u = event.url, let url = URL(string: u) { ek.url = url }
        ek.calendar = Self.store.defaultCalendarForNewEvents
        vc.event = ek
        vc.editViewDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}

enum CalendarAccess {
    /// iOS 17: write-only access is enough for the edit sheet. Returns true when we may present it.
    static func requestWriteAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await CalendarEditSheet.store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            return (try? await CalendarEditSheet.store.requestAccess(to: .event)) ?? false
        }
    }
}
