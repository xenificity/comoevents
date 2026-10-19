import SwiftUI

/// "Who's it for" chips: Everyone / Singles / Couples / Groups / Family.
struct AudienceBar: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                chip(nil, "Everyone", "sparkles")
                ForEach(Audience.allCases) { a in chip(a, a.label, a.symbol) }
            }
            .padding(4)
        }
        .glass(Capsule())
        .sensoryFeedback(.selection, trigger: store.audience)
    }

    private func chip(_ a: Audience?, _ label: String, _ symbol: String) -> some View {
        let on = store.audience == a
        return Button {
            withAnimation(.snappy(duration: 0.3)) { store.audience = a }
        } label: {
            Label(label, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(on ? Theme.ink : .primary)
                .background(on ? Theme.yellow : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
