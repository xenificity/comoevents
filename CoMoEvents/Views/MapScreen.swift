import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var usage: UsageCounter

    @State private var window: TimeWindow = .today
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.9480, longitude: -92.3300),
                           latitudinalMeters: 5000, longitudinalMeters: 5000))
    @State private var selected: Hotspot?
    @State private var detail: Event?
    @State private var showList = false
    @State private var cameraDistance: Double = 9000
    @State private var categories: Set<Category> = []

    // Filtering ~1,000 events and clustering them is too much to redo on every redraw (every location
    // fix, pin tap or friend refresh redraws this screen), so the results are cached and rebuilt only
    // when an input changes. See `recompute()`.
    @State private var visible: [Event] = []
    @State private var hotspots: [Hotspot] = []
    @State private var heatRings: [HeatRing] = []
    @State private var nextUp: [Event] = []

    /// Cluster cell grows as the camera pulls back, so pins never pile up.
    private var cellDegrees: Double { max(0.0015, 0.0015 * cameraDistance / 1800) }
    /// Everything the cached lists depend on, in one value so a single onChange covers it.
    private var inputs: String {
        "\(window.rawValue)|\(categories.map(\.rawValue).sorted().joined())|\(store.audience?.rawValue ?? "")|\(store.events.count)|\(store.generatedAt?.timeIntervalSince1970 ?? 0)|\(String(format: "%.5f", cellDegrees))"
    }

    private func recompute() {
        let list = store.events(in: window, categories: categories, audience: store.audience)
        visible = list
        hotspots = Hotspot.buildWithStars(from: list, cellDegrees: cellDegrees)
        heatRings = HeatRing.build(hotspots)
        let now = Date()
        func live(_ e: Event) -> Bool { e.startDate <= now && e.effectiveEnd >= now }
        nextUp = Array(list.sorted { a, b in
            let la = live(a), lb = live(b)
            if la != lb { return la }
            return a.startDate < b.startDate
        }.prefix(12))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    UserAnnotation()
                    // Heat: soft, edgeless yellow-to-amber rings under busy spots; overlaps deepen the colour.
                    ForEach(heatRings) { r in
                        MapCircle(center: r.center, radius: r.radius)
                            .foregroundStyle(r.color)
                    }
                    ForEach(hotspots) { h in
                        Annotation(h.title, coordinate: h.coordinate, anchor: .center) {
                            HotspotPin(hotspot: h, highlighted: selected == h,
                                       friendsAt: friends.friends.isEmpty ? ([], []) : friends.friends(atAny: Set(h.events.map(\.id))))
                                .onTapGesture {
                                    SoundPlayer.tap(); withAnimation(.snappy) { selected = h }
                                }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    withAnimation(.snappy(duration: 0.35)) { cameraDistance = ctx.camera.distance }
                }
                .mapControls { MapUserLocationButton(); MapCompass() }
                .ignoresSafeArea(edges: .bottom)

                // Floating top controls
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        AudienceBar()
                        AppearanceButton()
                    }
                    HStack(spacing: 4) {
                        ForEach(TimeWindow.allCases) { w in
                            let on = window == w
                            Button {
                                SoundPlayer.tap(); withAnimation(.snappy(duration: 0.3)) { window = w }
                            } label: {
                                Text(w.rawValue)
                                    .font(.footnote.weight(.bold))
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .foregroundStyle(on ? Theme.ink : .primary)
                                    .background(on ? Theme.yellow : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .glass(Capsule())
                    .sensoryFeedback(.selection, trigger: window)

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.gold)
                        Text("\(visible.count) events").fontWeight(.semibold)
                        if !store.updatedText.isEmpty { Text("· \(store.updatedText)").foregroundStyle(.secondary) }
                        if usage.total > 0 { Text("· \(usage.total.formatted()) using").foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glass(Capsule())

                    CategoryLegend(selected: $categories)
                        .padding(.horizontal, -12)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !nextUp.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(window == .now ? "Happening now" : "Next up")
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .glass(Capsule(), tint: Theme.yellow)
                            Spacer()
                            Button { showList = true } label: {
                                Label("All \(visible.count)", systemImage: "list.bullet")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .glass(Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(nextUp) { e in
                                    Button {
                                        focus(on: e)
                                    } label: { MiniCard(event: e) }
                                    .buttonStyle(CardPressStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("CoMo Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { h in
                HotspotSheet(hotspot: h)
                    .presentationDetents([.fraction(0.42), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.42)))
            }
            .sheet(item: $detail) { e in
                NavigationStack { EventDetailView(event: e) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showList) {
                NavigationStack {
                    ZStack {
                        Theme.page
                        EventCardList(events: visible, emptyText: "Nothing in this window.")
                    }
                    .navigationTitle("\(window.rawValue) · \(visible.count)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showList = false } } }
                }
            }
            .onAppear {
                location.request()
                if store.events(in: .today).count < 3 { window = .week }
                recompute()
            }
            .onChange(of: inputs) { _, _ in recompute() }
        }
    }

    private func focus(on e: Event) {
        if let c = e.coordinate {
            withAnimation(.easeInOut(duration: 0.6)) {
                position = .camera(MapCamera(centerCoordinate: c, distance: 1400, heading: 0, pitch: 45))
            }
            selected = hotspots.first { $0.events.contains(e) }
        } else {
            detail = e
        }
    }
}

/// One translucent disc of the busy-area heat layer.
struct HeatRing: Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let color: Color

    /// Four stacked discs per hotspot with two or more events: wide and faint yellow outside,
    /// small and warmer amber in the middle, so the eye reads a gradient with no edge.
    static func build(_ hotspots: [Hotspot]) -> [HeatRing] {
        let amber = Color(red: 1.0, green: 0.62, blue: 0.0)
        let steps: [(Double, Color)] = [(1.0, Theme.yellow.opacity(0.10)), (0.74, Theme.yellow.opacity(0.12)),
                                        (0.5, Theme.gold.opacity(0.13)), (0.3, amber.opacity(0.15))]
        return hotspots.filter { $0.count >= 2 }.prefix(80).flatMap { h -> [HeatRing] in
            let base = min(200 + Double(h.count) * 26, 620)
            return steps.enumerated().map { i, s in
                HeatRing(id: "\(h.id)#\(i)", center: h.coordinate, radius: base * s.0, color: s.1)
            }
        }
    }
}

struct HotspotPin: View {
    let hotspot: Hotspot
    let highlighted: Bool
    var friendsAt: (here: [FriendsStore.Friend], going: [FriendsStore.Friend]) = ([], [])
    @State private var appeared = false
    private var size: CGFloat { hotspot.badge != nil ? min(32 + CGFloat(hotspot.count) * 0.6, 40) : min(24 + CGFloat(hotspot.count) * 0.6, 32) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Small, quiet disc with the category symbol; the heat layer underneath shows how busy an area is.
            ZStack {
                if let badge = hotspot.badge {
                    // Seasonal star (🎃): warm disc with a glow so these stand out as the season's top picks.
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.88), Color(red: 1, green: 0.77, blue: 0.42)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                        .overlay(Circle().stroke(highlighted ? Theme.yellow : Color(red: 1, green: 0.54, blue: 0), lineWidth: highlighted ? 3 : 2))
                        .shadow(color: Color.orange.opacity(0.45), radius: 6)
                    Text(badge).font(.system(size: size * 0.58))
                } else {
                    Circle()
                        .fill(hotspot.dominant.color.opacity(0.92))
                        .overlay(Circle().stroke(highlighted ? Theme.yellow : .white, lineWidth: highlighted ? 3 : 1.5))
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    Image(systemName: hotspot.dominant.symbol)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            // Friends at this spot: green = here now, yellow = going/saved
            let fr = friendsAt.here + friendsAt.going
            if !fr.isEmpty {
                HStack(spacing: -6) {
                    ForEach(Array(fr.prefix(3).enumerated()), id: \.offset) { i, f in
                        Text(f.initials.isEmpty ? "?" : String(f.initials.prefix(1)))
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(i < friendsAt.here.count ? .white : Theme.ink)
                            .frame(width: 15, height: 15)
                            .background(i < friendsAt.here.count ? Color.green : Theme.yellow, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                    if fr.count > 3 { Text("+\(fr.count - 3)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).padding(.leading, 8) }
                }
                .offset(x: 6, y: size - 6)
            }
            // Count badge
            if hotspot.count > 1 {
                Text(hotspot.count > 99 ? "99+" : "\(hotspot.count)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Theme.yellow, in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: 1))
                    .offset(x: 6, y: -4)
            }
        }
        .scaleEffect(highlighted ? 1.25 : (appeared ? 1 : 0.4))
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.3), value: highlighted)
        .onAppear { withAnimation(.bouncy(duration: 0.5)) { appeared = true } }
    }
}

/// Small legend so the symbols explain themselves.
struct CategoryLegend: View {
    @Binding var selected: Set<Category>
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Category.allCases) { c in
                    let on = selected.contains(c)
                    Button {
                        SoundPlayer.tap(); withAnimation(.snappy(duration: 0.25)) { if on { selected.remove(c) } else { selected.insert(c) } }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: c.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(c.color, in: Circle())
                            Text(c.label).font(.caption2.weight(.bold))
                        }
                        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
                        .foregroundStyle(.primary)
                        .glass(Capsule(), tint: on ? c.color.opacity(0.6) : nil, interactive: true)
                        .opacity(selected.isEmpty || on ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct HotspotSheet: View {
    let hotspot: Hotspot
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page
                EventList(events: hotspot.events, emptyText: "")
            }
            .navigationTitle(hotspot.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
