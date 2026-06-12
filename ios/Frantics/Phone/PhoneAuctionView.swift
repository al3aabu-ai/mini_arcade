import SwiftUI

/// The Dirty Auction, from a player's seat: secretly bid points, and if you
/// win, pick your victim.
struct PhoneAuctionView: View {
    @EnvironmentObject var client: GameClient
    @State private var bid: Double = 0
    @State private var locked = false

    private var auction: AuctionState? { client.room?.auction }
    private var iWon: Bool { auction?.winnerId == client.playerId }

    var body: some View {
        VStack(spacing: 20) {
            if let auction {
                switch auction.stage {
                case "bidding":
                    bidding(auction)
                case "targeting":
                    if iWon {
                        targetPicker(auction)
                    } else {
                        waitingForWinner(auction)
                    }
                default:
                    reveal(auction)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: auction?.round) { _, _ in
            bid = 0
            locked = false
        }
    }

    // MARK: bidding

    @ViewBuilder
    private func bidding(_ auction: AuctionState) -> some View {
        let maxBid = Double(max(0, client.me?.score ?? 0))

        VStack(spacing: 6) {
            Text("THE DIRTY AUCTION")
                .font(Theme.body(13))
                .foregroundStyle(Theme.pink)
                .kerning(2)
            HStack(spacing: 12) {
                Text(auction.item.emoji).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(auction.item.name)
                        .font(Theme.title(20))
                        .foregroundStyle(.white)
                    Text(auction.item.blurb)
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .card()
        }

        CountdownLabel(endsAt: auction.endsAtDate)

        if locked {
            VStack(spacing: 10) {
                Text("🤐").font(.system(size: 54))
                Text("Bid locked in. Tell no one.")
                    .font(Theme.body(17))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(auction.lockedIn.count)/\(client.room?.players.count ?? 0) bids in")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.cyan)
            }
        } else {
            VStack(spacing: 14) {
                Text("\(Int(bid))")
                    .font(Theme.title(58))
                    .foregroundStyle(Theme.yellow)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(bid))
                Slider(value: $bid, in: 0...max(1, maxBid), step: 10)
                    .tint(Theme.yellow)
                    .disabled(maxBid <= 0)
                HStack {
                    Text("0").font(Theme.body(13)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("all in: \(Int(maxBid))")
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .card()

            Button(bid > 0 ? "LOCK IN SECRET BID  🤫" : "BID NOTHING  🙅") {
                locked = true
                Haptics.thump()
                client.submitBid(Int(bid))
            }
            .buttonStyle(NeonButtonStyle(color: bid > 0 ? Theme.yellow : Theme.panelLight,
                                         textColor: bid > 0 ? Theme.bg : .white))
        }
    }

    // MARK: targeting

    @ViewBuilder
    private func targetPicker(_ auction: AuctionState) -> some View {
        Text("YOU WON \(auction.item.emoji)")
            .font(Theme.title(28))
            .foregroundStyle(Theme.yellow)
            .neonGlow(Theme.yellow)
        Text("for \(auction.winningBid ?? 0) points. Now… who suffers?")
            .font(Theme.body(16))
            .foregroundStyle(.white.opacity(0.7))
        CountdownLabel(endsAt: auction.endsAtDate, font: Theme.title(30))

        let victims = (client.room?.players ?? []).filter { $0.id != client.playerId }
        VStack(spacing: 10) {
            ForEach(victims) { victim in
                Button {
                    Haptics.thump()
                    client.chooseTarget(victim.id)
                } label: {
                    HStack {
                        Text(victim.avatar).font(.system(size: 28))
                        Text(victim.name)
                            .font(Theme.title(20))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("🎯")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: victim.color).opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: victim.color).opacity(0.7), lineWidth: 1.5)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func waitingForWinner(_ auction: AuctionState) -> some View {
        let winner = client.room?.player(auction.winnerId)
        Text(winner?.avatar ?? "😈").font(.system(size: 64))
        Text("\(winner?.name ?? "Someone") won the \(auction.item.name)")
            .font(Theme.title(22))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
        Text("…and is choosing a victim. Look innocent.")
            .font(Theme.body(15))
            .foregroundStyle(.white.opacity(0.55))
    }

    // MARK: reveal

    @ViewBuilder
    private func reveal(_ auction: AuctionState) -> some View {
        if let targetId = auction.targetId {
            let target = client.room?.player(targetId)
            let winner = client.room?.player(auction.winnerId)
            Text(auction.item.emoji).font(.system(size: 80))
            if targetId == client.playerId {
                Text("IT'S YOU.")
                    .font(Theme.title(36))
                    .foregroundStyle(Theme.red)
                    .neonGlow(Theme.red)
                Text("\(winner?.name ?? "A rival") hit you with \(auction.item.name)")
                    .font(Theme.body(16))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text("\(target?.name ?? "Someone") got crushed")
                    .font(Theme.title(26))
                    .foregroundStyle(.white)
                Text("courtesy of \(winner?.name ?? "a rival")")
                    .font(Theme.body(15))
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            Text("🦗").font(.system(size: 70))
            Text("No bids. The item rusts away.")
                .font(Theme.title(20))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
