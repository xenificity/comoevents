import SwiftUI
import MapKit

struct EventDetailView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.openURL) private var openURL
    let event: Event

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let img = event.imageUrl.flatMap(URL.init) {
                    AsyncImage(url: img) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(event.kind.color.opacity(0.15))
                        }
                    }
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(event.kind.label, systemImage: event.kind.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(event.kind.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(event.kind.color)
                        if event.isHappeningNow {
                            Text("Happening now").font(.caption.weight(.bold)).foregroundStyle(.red)
                        }
                    }
                    Text(event.title).font(.title2.bold())
                    if let o = event.organizer, !o.isEmpty { Text(o).font(.subheadline).foregroundStyle(.secondary) }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(event.whenText, systemImage: "clock")
                    if !event.placeText.isEmpty { Label(event.placeText, systemImage: "mappin.and.ellipse") }
                    if let p = event.price { Label(p, systemImage: "tag") }
                }
                .font(.subheadline)

                // Actions
                HStack(spacing: 10) {
                    if let link = event.primaryLink {
                        Button {
                            openURL(link)
                        } label: {
                            Label(event.ticketUrl != nil ? "Tickets / Register" : "More info", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button {
                        store.toggleFavorite(event)
                    } label: {
                        Image(systemName: store.isFavorite(event) ? "heart.fill" : "heart")
                            .frame(width: 24)
                    }
                    .buttonStyle(.bordered)
                    .tint(store.isFavorite(event) ? .red : .accentColor)
                }
                HStack(spacing: 10) {
                    if let tel = event.telURL {
                        Button { openURL(tel) } label: { Label("Call", systemImage: "phone").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                    if event.coordinate != nil || event.address != nil {
                        Button { openDirections() } label: { Label("Directions", systemImage: "car").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                    if event.ticketUrl != nil, let info = event.infoLink, info != event.primaryLink {
                        Button { openURL(info) } label: { Label("Details", systemImage: "info.circle").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                }

                if let c = event.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 900, longitudinalMeters: 900)),
                        interactionModes: []) {
                        Marker(event.venue ?? event.title, coordinate: c).tint(event.kind.color)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if let d = event.description, !d.isEmpty {
                    Text(d).font(.body)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Source: \(event.sourceName)").font(.caption).foregroundStyle(.secondary)
                    if let also = event.alsoOn, !also.isEmpty {
                        Text("Also listed on \(also.count) other site\(also.count == 1 ? "" : "s").").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openDirections() {
        let item: MKMapItem
        if let c = event.coordinate {
            item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        } else if let a = event.address, let url = URL(string: "maps://?daddr=\(a.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? a)") {
            openURL(url); return
        } else { return }
        item.name = event.venue ?? event.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
