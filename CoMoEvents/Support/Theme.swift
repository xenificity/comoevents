import SwiftUI

enum Theme {
    static let yellow = Color(red: 1.00, green: 0.84, blue: 0.00)
    static let gold = Color(red: 0.93, green: 0.68, blue: 0.00)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)

    /// Page background: a soft wash so glass has something to blur.
    static var page: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [yellow.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color.purple.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

/// Liquid Glass on iOS 26, frosted material on iOS 17/18.
struct GlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var interactive = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            return AnyView(content.glassEffect(glass, in: shape))
        } else {
            return AnyView(
                content
                    .background(tint?.opacity(0.35) ?? .clear, in: shape)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            )
        }
    }
}

extension View {
    func glass<S: Shape>(_ shape: S = Capsule(), tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

/// Category gradient used behind cards that have no image.
extension Category {
    var gradient: LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55), Theme.ink.opacity(0.9)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Yellow pill with black text: the brand's "time" badge.
struct TimePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.yellow, in: Capsule())
    }
}

struct NowBadge: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.white).frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.4 : 0.8)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text("LIVE").font(.caption2.weight(.heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.red, in: Capsule())
        .onAppear { pulse = true }
    }
}

/// Heart that bounces and buzzes when toggled.
struct HeartButton: View {
    @EnvironmentObject var store: EventStore
    let event: Event
    var size: CGFloat = 18
    var onLight = false
    var body: some View {
        let on = store.isFavorite(event)
        Button {
            withAnimation(.bouncy) { store.toggleFavorite(event) }
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? .red : (onLight ? .primary : .white))
                .symbolEffect(.bounce, value: on)
                .padding(8)
                .glass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: on)
        .accessibilityLabel(on ? "Remove from saved" : "Save")
    }
}

/// Top-right moon/sun button: switches the whole app between light and dark and remembers it.
/// The app is light by default (even when the iPhone is in dark mode); dark only after a tap.
struct AppearanceButton: View {
    @AppStorage("appearance") private var appearance = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            appearance = scheme == .dark ? "light" : "dark"
            Analytics.tap("theme-" + appearance)   // ticks too
        } label: {
            Image(systemName: scheme == .dark ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(scheme == .dark ? Theme.yellow : Theme.ink)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle(), interactive: true)
        .accessibilityLabel(scheme == .dark ? "Light mode" : "Dark mode")
    }
}

extension ColorScheme {
    /// The app-wide pick from AppearanceButton: light unless dark mode was turned on.
    static func from(appearance: String) -> ColorScheme? { appearance == "dark" ? .dark : .light }
}
