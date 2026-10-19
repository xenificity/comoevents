import SwiftUI
import MapKit

struct EventDetailView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var community: CommunityStore
    @Environment(\.openURL) private var openURL
    let event: Event
    @State private var shareItems: [Any]?
    @State private var showCalendar = false
    @State private var calendarDenied = false
    @State private var reportSheet = false
    @State private var reportMessage: String?
    @State private var confirmBlock = false
    @Environment(\.dismiss) private var dismissView

    var body: some View {
        ZStack {
            Theme.page
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 18) {
                        facts
                        if let c = event.coordinate {
                            Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 900, longitudinalMeters: 900)),
                                interactionModes: []) {
                                Marker(event.venue ?? event.title, coordinate: c).tint(event.kind.color)
                            }
                            .frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 0.8))
                            .onTapGesture { openDirections() }
                        }
                        if let d = event.description, !d.isEmpty {
                            Text(d).font(.body).lineSpacing(3)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        if !event.audiences.isEmpty {
                            HStack(spacing: 6) {
                                Text("Good for").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(event.audiences) { a in
                                    Label(a.label, systemImage: a.symbol).font(.caption.weight(.bold))
                                        .padding(.horizontal, 9).padding(.vertical, 5).glass(Capsule())
                                }
                            }
                        }
                        let going = friends.friendsGoing(to: event)
                        if !going.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill").foregroundStyle(Theme.gold)
                                Text(going.count == 1 ? "\(going[0].name) is going" : "\(going.map(\.name).joined(separator: ", ")) are going")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Theme.yellow.opacity(0.5))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source: \(event.sourceName)")
                            if let also = event.alsoOn, !also.isEmpty {
                                Text("Also listed on \(also.count) other site\(also.count == 1 ? "" : "s").")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { Task { await addToCalendar() } } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                    if event.isCommunity {
                        Button(role: .destructive) { reportSheet = true } label: { Label("Report this post", systemImage: "flag") }
                        if event.submitterID != nil {
                            Button(role: .destructive) { confirmBlock = true } label: { Label("Block this poster", systemImage: "hand.raised") }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).frame(width: 36, height: 36).glass(Circle(), interactive: true)
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ActivitySheet(items: items).presentationDetents([.medium, .large]) }
        }
        .sheet(isPresented: $showCalendar) { CalendarEditSheet(event: event).ignoresSafeArea() }
        .alert("Calendar access is off", isPresented: $calendarDenied) {
            Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Allow CoMo Events to add events in Settings › Privacy › Calendars.") }
        .confirmationDialog("Report this post", isPresented: $reportSheet, titleVisibility: .visible) {
            ForEach(["Spam or scam", "Wrong or misleading", "Inappropriate", "Not an event"], id: \.self) { reason in
                Button(reason) { Task { reportMessage = (await community.report(event, reason: reason)) ?? "Thanks. A moderator will take a look." } }
            }
        }
        .alert("Report", isPresented: Binding(get: { reportMessage != nil }, set: { if !$0 { reportMessage = nil } })) { Button("OK") {} } message: { Text(reportMessage ?? "") }
        .confirmationDialog("Block this poster?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block and hide their posts", role: .destructive) {
                community.block(submitterOf: event)
                store.communityEvents = community.approved
                Task { _ = await community.report(event, reason: "Blocked by a user") }
                dismissView()
            }
        } message: { Text("You won't see anything this person posts. A report is also sent to the moderator.") }
    }

    private func share() {
        var items: [Any] = []
        if let img = renderShareCard(for: event) { items.append(img) }
        items.append(event.shareText)
        if let u = event.url, let url = URL(string: u) { items.append(url) }
        shareItems = items
    }

    private func addToCalendar() async {
        if await CalendarAccess.requestWriteAccess() { showCalendar = true } else { calendarDenied = true }
    }

    // MARK: pieces

    private var hero: some View {
        Color.clear
            .frame(height: 340)
            .overlay {
                if let url = event.imageUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { p in
                        if let img = p.image { img.resizable().scaledToFill() } else { event.kind.gradient }
                    }
                } else {
                    ZStack {
                        event.kind.gradient
                        Image(systemName: event.kind.symbol).font(.system(size: 140, weight: .bold)).foregroundStyle(.white.opacity(0.15))
                    }
                }
            }
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(event.kind.label, systemImage: event.kind.symbol)
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.yellow, in: Capsule())
                    if event.isHappeningNow { NowBadge() }
                }
                Text(event.title).font(.title.bold()).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.8)
                if let o = event.organizer, !o.isEmpty { Text(o).font(.subheadline).foregroundStyle(.white.opacity(0.85)) }
            }
            .padding(16)
            }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            fact("clock.fill", event.whenText)
            if !event.placeText.isEmpty { fact("mappin.and.ellipse", event.placeText) }
            if let p = event.price { fact("tag.fill", p) }
            if let ph = event.phone { fact("phone.fill", ph) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.gold).frame(width: 22)
            Text(text).font(.subheadline.weight(.medium))
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let link = event.primaryLink {
                Button { openURL(link) } label: {
                    Label(event.ticketUrl != nil ? "Tickets / Register" : "More info", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.yellow, in: Capsule())
                }
                .buttonStyle(CardPressStyle())
            }
            roundButton("square.and.arrow.up") { share() }
            roundButton("calendar.badge.plus") { Task { await addToCalendar() } }
            if let tel = event.telURL {
                roundButton("phone.fill") { openURL(tel) }
            }
            if event.coordinate != nil || event.address != nil {
                roundButton("car.fill") { openDirections() }
            }
            HeartButton(event: event, size: 20, onLight: true)
                .frame(width: 46, height: 46)
        }
        .padding(12)
        .glass(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .glass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func openDirections() {
        if let c = event.coordinate {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
            item.name = event.venue ?? event.title
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        } else if let a = event.address,
                  let url = URL(string: "maps://?daddr=\(a.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? a)") {
            openURL(url)
        }
    }
}
