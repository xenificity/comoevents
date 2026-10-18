import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var location: LocationManager

    @State private var window: TimeWindow = .today
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.9480, longitude: -92.3300),
                           latitudinalMeters: 5000, longitudinalMeters: 5000))
    @State private var selected: Hotspot?
    @State private var showList = false

    private var visible: [Event] { store.events(in: window) }
    private var hotspots: [Hotspot] { Hotspot.build(from: visible) }
    private var unplaced: Int { visible.filter { $0.coordinate == nil }.count }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(hotspots) { h in
                        if h.isBusy {
                            MapCircle(center: h.coordinate, radius: h.haloRadius)
                                .foregroundStyle(h.dominant.color.opacity(0.18))
                                .stroke(h.dominant.color.opacity(0.35), lineWidth: 1)
                        }
                        Annotation(h.title, coordinate: h.coordinate, anchor: .center) {
                            HotspotPin(hotspot: h, highlighted: selected == h)
                                .onTapGesture { selected = h }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    Picker("When", selection: $window) {
                        ForEach(TimeWindow.allCases) { w in Text(w.rawValue).tag(w) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    HStack(spacing: 6) {
                        Text("\(visible.count) events")
                        if unplaced > 0 { Text("· \(unplaced) without a pin").foregroundStyle(.secondary) }
                        if !store.updatedText.isEmpty { Text("· \(store.updatedText)").foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
                .padding(.top, 6)
            }
            .navigationTitle("CoMo Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showList = true } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("List these events")
                }
            }
            .sheet(item: $selected) { h in
                HotspotSheet(hotspot: h)
                    .presentationDetents([.fraction(0.4), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
            }
            .sheet(isPresented: $showList) {
                NavigationStack {
                    EventList(events: visible, emptyText: "Nothing in this window.")
                        .navigationTitle("\(window.rawValue) · \(visible.count)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showList = false } } }
                }
            }
            .onAppear { location.request() }
        }
    }
}

struct HotspotPin: View {
    let hotspot: Hotspot
    let highlighted: Bool
    private var size: CGFloat { min(30 + CGFloat(hotspot.count) * 3, 56) }

    var body: some View {
        ZStack {
            Circle()
                .fill(hotspot.dominant.color.gradient)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white, lineWidth: highlighted ? 3 : 2))
                .shadow(radius: 3, y: 1)
            if hotspot.count > 1 {
                Text("\(hotspot.count)")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: hotspot.dominant.symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(highlighted ? 1.15 : 1)
        .animation(.spring(duration: 0.25), value: highlighted)
    }
}

struct HotspotSheet: View {
    let hotspot: Hotspot
    var body: some View {
        NavigationStack {
            EventList(events: hotspot.events, emptyText: "")
                .navigationTitle(hotspot.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
