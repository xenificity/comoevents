import SwiftUI

/// Big image card used in Upcoming and Saved.
struct EventCard: View {
    @EnvironmentObject var store: EventStore
    let event: Event

    var body: some View {
        Color.clear
            .frame(height: 190)
            .overlay { backdrop }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TimePill(text: event.timeText)
                    if event.isHappeningNow { NowBadge() }
                    if let p = event.price {
                        Text(p).font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4).glass(Capsule())
                    }
                    Spacer()
                    HeartButton(event: event)
                }
                Spacer()
                Label(event.kind.label, systemImage: event.kind.symbol)
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.yellow)
                Text(event.title)
                    .font(.title3.weight(.bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.85)
                if let v = event.venue ?? event.address {
                    Label(v, systemImage: "mappin").font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
            }
            .padding(14)
            }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.8))
        .shadow(color: event.kind.color.opacity(0.25), radius: 14, y: 8)
    }

    @ViewBuilder private var backdrop: some View {
        if let url = event.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    event.kind.gradient
                }
            }
        } else {
            ZStack {
                event.kind.gradient
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 110, weight: .bold))
                    .foregroundStyle(.white.opacity(0.12))
                    .offset(x: 90, y: -20)
            }
        }
    }
}

/// Small horizontal card for the map's "Next up" strip.
struct MiniCard: View {
    let event: Event
    var body: some View {
        HStack(spacing: 10) {
            Thumb(event: event).frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TimePill(text: event.timeText)
                    if event.isHappeningNow { NowBadge() }
                }
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let v = event.venue { Text(v).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 270, height: 92)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    }
}

/// Compact row for the hotspot sheet.
struct EventRow: View {
    @EnvironmentObject var store: EventStore
    let event: Event

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Thumb(event: event).frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TimePill(text: event.timeText)
                    if event.isHappeningNow { NowBadge() }
                    if let p = event.price { Text(p).font(.caption).foregroundStyle(.secondary) }
                }
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let v = event.venue ?? event.address {
                    Text(v).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.bouncy) { store.toggleFavorite(event) }
            } label: {
                Image(systemName: store.isFavorite(event) ? "heart.fill" : "heart")
                    .foregroundStyle(store.isFavorite(event) ? .red : .secondary)
                    .symbolEffect(.bounce, value: store.isFavorite(event))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: store.isFavorite(event))
        }
        .padding(.vertical, 4)
    }
}

/// Square thumbnail: event image if any, else the category gradient with its symbol.
struct Thumb: View {
    let event: Event
    var body: some View {
        Color.clear.overlay {
            if let url = event.imageUrl.flatMap(URL.init) {
                AsyncImage(url: url) { p in
                    if let img = p.image { img.resizable().scaledToFill() } else { event.kind.gradient }
                }
            } else {
                ZStack {
                    event.kind.gradient
                    Image(systemName: event.kind.symbol).foregroundStyle(.white).font(.title3)
                }
            }
        }
        .clipped()
    }
}
