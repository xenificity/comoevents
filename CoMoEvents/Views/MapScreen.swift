import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var friends: FriendsStore

    @State private var window: TimeWindow = .today
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.9480, longitude: -92.3300),
                           latitudinalMeters: 5000, longitudinalMeters: 5000))
    @State private var selected: Hotspot?
    @State private var detail: Event?
    @State private var showList = false
    @State private var cameraDistance: Double = 9000
    @State private var categories: Set<Category> = []

    private var visible: [Event] { store.events(in: window, categories: categories, audience: store.audience) }
    /// Cluster cell grows as the camera pulls back, so pins never pile up.
    private var cellDegrees: Double { max(0.0015, 0.0015 * cameraDistance / 1800) }
    private var hotspots: [Hotspot] { Hotspot.build(from: visible, cellDegrees: cellDegrees) }
    private var nextUp: [Event] {
        Array(visible.sorted { a, b in
            if a.isHappeningNow != b.isHappeningNow { return a.isHappeningNow }
            return a.startDate < b.startDate
        }.prefix(12))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(hotspots) { h in
                        if h.isBusy {
                            MapCircle(center: h.coordinate, radius: h.haloRadius)
                                .foregroundStyle(h.dominant.color.opacity(0.16))
                                .stroke(h.dominant.color.opacity(0.4), lineWidth: 1.5)
                        }
                        Annotation(h.title, coordinate: h.coordinate, anchor: .center) {
                            HotspotPin(hotspot: h, highlighted: selected == h,
                                       friendsAt: friends.friends(atAny: Set(h.events.map(\.id))))
                                .onTapGesture {
                                    withAnimation(.snappy) { selected = h }
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
                    AudienceBar()
                    HStack(spacing: 4) {
                        ForEach(TimeWindow.allCases) { w in
                            let on = window == w
                            Button {
                                withAnimation(.snappy(duration: 0.3)) { window = w }
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
            }
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

struct HotspotPin: View {
    let hotspot: Hotspot
    let highlighted: Bool
    var friendsAt: (here: [FriendsStore.Friend], going: [FriendsStore.Friend]) = ([], [])
    @State private var appeared = false
    private var size: CGFloat { min(38 + CGFloat(hotspot.count) * 1.5, 56) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Glow
            Circle()
                .fill(hotspot.dominant.color.opacity(0.35))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: 8)
                .offset(x: -(size * 0.25), y: size * 0.25)
            // Glass orb with the category symbol: always the symbol, so the map reads at a glance
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [hotspot.dominant.color.opacity(0.75), hotspot.dominant.color],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(highlighted ? Theme.yellow : .white, lineWidth: highlighted ? 4 : 2.5))
                    .overlay(
                        Circle().trim(from: 0.55, to: 0.95)
                            .stroke(.white.opacity(0.55), lineWidth: 3)
                            .frame(width: size * 0.7, height: size * 0.7)
                            .rotationEffect(.degrees(-20))
                    )
                    .shadow(color: hotspot.dominant.color.opacity(0.6), radius: 8, y: 3)
                Image(systemName: hotspot.dominant.symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
            .frame(width: size, height: size)
            // Friends at this spot: green = here now, yellow = going/saved
            let fr = friendsAt.here + friendsAt.going
            if !fr.isEmpty {
                HStack(spacing: -6) {
                    ForEach(Array(fr.prefix(3).enumerated()), id: \.offset) { i, f in
                        Text(f.initials.isEmpty ? "?" : String(f.initials.prefix(1)))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(i < friendsAt.here.count ? .white : Theme.ink)
                            .frame(width: 20, height: 20)
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
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.yellow, in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                    .offset(x: 8, y: -6)
            }
        }
        .scaleEffect(highlighted ? 1.18 : (appeared ? 1 : 0.4))
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
                        withAnimation(.snappy(duration: 0.25)) { if on { selected.remove(c) } else { selected.insert(c) } }
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
