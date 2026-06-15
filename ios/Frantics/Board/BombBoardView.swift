import SwiftUI

/// The Billionaire's Bomb on the TV: players in a circle, the bomb hopping
/// between them, a pot that won't stop climbing, and the occasional 💥.
struct BombBoardView: View {
    @ObservedObject private var loc = Localization.shared
    let room: RoomState
    @State private var shake = false

    private var bomb: BombState? { room.bomb }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let bomb {
                    loot(bomb, in: geo.size)
                    circleOfFear(bomb, in: geo.size)
                    centerpiece(bomb)
                    if bomb.stage == "exploded" {
                        explosion(bomb)
                    }
                    if bomb.stage == "done" {
                        survivorsBanner(bomb)
                    }
                }

                VStack {
                    Text(loc.tr("💣 THE BILLIONAIRE'S BOMB"))
                        .font(Theme.title(34))
                        .foregroundStyle(Theme.orange)
                        .neonGlow(Theme.orange)
                        .padding(.top, 20)
                    Text(loc.tr("Hold it to earn. Pass it to survive. Last two standing bank everything."))
                        .font(Theme.body(17))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
            }
            .offset(x: shake ? -9 : 0)
        }
        .onChange(of: bomb?.stage) { _, stage in
            guard stage == "exploded" else { return }
            withAnimation(.linear(duration: 0.06).repeatCount(9, autoreverses: true)) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                shake = false
            }
        }
    }

    // MARK: loose loot

    /// Coins scattered around the arena. Pass the bomb to snatch one — the server
    /// removes it and banks +50 into the passer's private wallet, so they vanish
    /// here as they're grabbed. (x,y) are fractional screen coords.
    @ViewBuilder
    private func loot(_ bomb: BombState, in size: CGSize) -> some View {
        ForEach(bomb.spawnedCoins) { coin in
            Text("🪙")
                .font(.system(size: 46))
                .shadow(color: Theme.yellow.opacity(0.75), radius: 10)
                .position(x: size.width * CGFloat(coin.x), y: size.height * CGFloat(coin.y))
                .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: bomb.spawnedCoins)
    }

    // MARK: circle

    private struct Seat: Identifiable {
        let id: String
        let player: PlayerState
        let position: CGPoint
        let isHolder: Bool
        let earnings: Int
    }

    private func seats(_ bomb: BombState, in size: CGSize) -> [Seat] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 30)
        let radius = min(size.width, size.height) * 0.33
        let alive = room.players.filter { !bomb.eliminated.contains($0.id) }
        let count = Double(max(1, alive.count))
        return alive.enumerated().map { index, player in
            let angle = (Double(index) / count) * 2 * .pi - .pi / 2
            let x = center.x + CGFloat(Foundation.cos(angle)) * radius
            let y = center.y + CGFloat(Foundation.sin(angle)) * radius
            return Seat(
                id: player.id,
                player: player,
                position: CGPoint(x: x, y: y),
                isHolder: bomb.holderId == player.id,
                earnings: bomb.earnings[player.id] ?? 0
            )
        }
    }

    @ViewBuilder
    private func circleOfFear(_ bomb: BombState, in size: CGSize) -> some View {
        ForEach(seats(bomb, in: size)) { seat in
            SeatView(seat: seat)
                .position(seat.position)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: bomb.holderId)
        }

        // Ghosts of the eliminated drift at the bottom.
        let ghosts = room.players.filter { bomb.eliminated.contains($0.id) }
        HStack(spacing: 26) {
            ForEach(ghosts) { player in
                VStack(spacing: 2) {
                    Text("👻").font(.system(size: 30))
                    AvatarChip(player: player, size: 52, dimmed: true)
                }
            }
        }
        .position(x: size.width / 2, y: size.height - 70)
    }

    private struct SeatView: View {
        let seat: Seat

        var body: some View {
            VStack(spacing: 6) {
                AvatarChip(player: seat.player, size: seat.isHolder ? 104 : 84)
                    .scaleEffect(seat.isHolder ? 1.06 : 1)
                Text("$\(seat.earnings)")
                    .font(Theme.body(20))
                    .foregroundStyle(Theme.yellow)
                    .contentTransition(.numericText())
                if seat.isHolder {
                    Text("💣")
                        .font(.system(size: 46))
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: center

    @ViewBuilder
    private func centerpiece(_ bomb: BombState) -> some View {
        VStack(spacing: 8) {
            Text(loc.tr("PRIZE POOL"))
                .font(Theme.body(18))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(3)
            Text("$\(bomb.pot)")
                .font(Theme.title(74))
                .foregroundStyle(Theme.yellow)
                .neonGlow(Theme.yellow, radius: 18)
                .contentTransition(.numericText())
                .animation(.snappy, value: bomb.pot)

            if bomb.stage == "ticking", let holder = room.player(bomb.holderId) {
                HStack(spacing: 8) {
                    Text("🔥")
                    Text("\(holder.name) ×\(String(format: "%.2f", bomb.multiplier))")
                        .font(Theme.body(22))
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .offset(y: 30)
    }

    // MARK: drama

    @ViewBuilder
    private func explosion(_ bomb: BombState) -> some View {
        let victim = room.player(bomb.lastExplodedId)
        VStack(spacing: 10) {
            Text("💥")
                .font(.system(size: 160))
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            Text(loc.tr("%@ %@ IS OUT", victim?.avatar ?? "", victim?.name ?? loc.tr("Someone")))
                .font(Theme.title(40))
                .foregroundStyle(Theme.red)
                .neonGlow(Theme.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.red.opacity(0.12))
    }

    @ViewBuilder
    private func survivorsBanner(_ bomb: BombState) -> some View {
        let names = (bomb.survivors ?? [])
            .compactMap { room.player($0) }
            .map { "\($0.avatar) \($0.name)" }
            .joined(separator: "  &  ")
        VStack(spacing: 12) {
            Text(loc.tr("🏆 SURVIVORS 🏆"))
                .font(Theme.title(44))
                .foregroundStyle(Theme.cyan)
                .neonGlow(Theme.cyan)
            Text(names)
                .font(Theme.title(34))
                .foregroundStyle(.white)
            Text(loc.tr("Earnings banked · +$250 each"))
                .font(Theme.body(20))
                .foregroundStyle(Theme.yellow)
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 30).fill(Theme.bg.opacity(0.88)))
    }
}
