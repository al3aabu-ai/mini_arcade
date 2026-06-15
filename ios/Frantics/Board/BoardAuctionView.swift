import SwiftUI

/// The Dirty Auction on the TV: item card, countdown, who's locked in,
/// then the dramatic reveal — anvil crushing included.
struct BoardAuctionView: View {
    @ObservedObject private var loc = Localization.shared
    let room: RoomState
    @State private var crushDrop = false

    private var auction: AuctionState? { room.auction }

    var body: some View {
        VStack(spacing: 24) {
            if let auction {
                Text(loc.tr("💰 THE DIRTY AUCTION 💰"))
                    .font(Theme.title(40))
                    .foregroundStyle(Theme.pink)
                    .neonGlow(Theme.pink)
                    .padding(.top, 30)

                itemCard(auction)

                switch auction.stage {
                case "bidding": bidding(auction)
                case "targeting": targeting(auction)
                default: reveal(auction)
                }

                Spacer()

                scoreStrip
            }
        }
        .onChange(of: auction?.stage) { _, stage in
            crushDrop = false
            if stage == "reveal" {
                withAnimation(.interpolatingSpring(stiffness: 220, damping: 12).delay(0.25)) {
                    crushDrop = true
                }
            }
        }
    }

    private func itemCard(_ auction: AuctionState) -> some View {
        HStack(spacing: 22) {
            Text(auction.item.emoji)
                .font(.system(size: 84))
                .neonGlow(Theme.yellow, radius: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.tr(auction.item.name))
                    .font(Theme.title(38))
                    .foregroundStyle(.white)
                Text(loc.tr(auction.item.blurb))
                    .font(Theme.body(20))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.yellow.opacity(0.5), lineWidth: 2)
                )
        )
    }

    @ViewBuilder
    private func bidding(_ auction: AuctionState) -> some View {
        CountdownLabel(endsAt: auction.endsAtDate, font: Theme.title(72))
        Text(loc.tr("Bid in secret on your phones…"))
            .font(Theme.body(22))
            .foregroundStyle(.white.opacity(0.55))
        HStack(spacing: 26) {
            ForEach(room.players) { player in
                VStack(spacing: 8) {
                    AvatarChip(player: player, size: 84)
                    Text(loc.tr(auction.lockedIn.contains(player.id) ? "🔒 LOCKED" : "thinking…"))
                        .font(Theme.body(15))
                        .foregroundStyle(
                            auction.lockedIn.contains(player.id) ? Theme.cyan : .white.opacity(0.35)
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func targeting(_ auction: AuctionState) -> some View {
        let winner = room.player(auction.winnerId)
        VStack(spacing: 14) {
            // The winning bid is a coin amount, so we DON'T show it on the TV —
            // players see what they paid on their own phones. Big screen = drama only.
            Text(loc.tr("SOLD to %@ %@!", winner?.name ?? "?", winner?.avatar ?? ""))
                .font(Theme.title(34))
                .foregroundStyle(Theme.yellow)
                .neonGlow(Theme.yellow)
            Text(loc.tr("They're choosing a victim right now…"))
                .font(Theme.body(22))
                .foregroundStyle(.white.opacity(0.6))
            Text("😈")
                .font(.system(size: 70))
        }
    }

    @ViewBuilder
    private func reveal(_ auction: AuctionState) -> some View {
        if let target = room.player(auction.targetId) {
            let winner = room.player(auction.winnerId)
            VStack(spacing: 10) {
                // The sabotage item slams down onto the victim's avatar.
                Text(auction.item.emoji)
                    .font(.system(size: 90))
                    .offset(y: crushDrop ? 36 : -200)
                    .opacity(crushDrop ? 1 : 0.4)
                AvatarChip(player: target, size: 120)
                    .scaleEffect(y: crushDrop ? 0.55 : 1, anchor: .bottom)
                    .animation(.interpolatingSpring(stiffness: 300, damping: 10).delay(0.3), value: crushDrop)
                Text(loc.tr("%@ sabotaged %@!", winner?.name ?? "?", target.name))
                    .font(Theme.title(34))
                    .foregroundStyle(Theme.red)
                    .neonGlow(Theme.red)
                    .padding(.top, 8)
            }
        } else {
            VStack(spacing: 12) {
                Text("🦗").font(.system(size: 80))
                Text(loc.tr("NO SALE — everyone kept their coins"))
                    .font(Theme.title(30))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // Trophy standings strip. We show trophies (public) — never coin wallets,
    // which are private to each phone and must never appear on the TV.
    private var scoreStrip: some View {
        HStack(spacing: 30) {
            ForEach(room.players) { player in
                HStack(spacing: 8) {
                    Text(player.avatar).font(.system(size: 26))
                    Text("\(player.trophies)🏆")
                        .font(Theme.body(22))
                        .foregroundStyle(Theme.yellow)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 36)
        .background(Capsule().fill(Theme.panel))
        .padding(.bottom, 24)
        .animation(.snappy, value: room.players)
    }
}
