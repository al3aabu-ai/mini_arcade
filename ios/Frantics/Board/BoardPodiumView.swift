import SwiftUI

struct BoardPodiumView: View {
    let room: RoomState
    @State private var risen = false

    private var ranked: [PlayerState] {
        (room.podium?.ranking ?? []).compactMap { room.player($0) }
    }

    var body: some View {
        ZStack {
            ConfettiRain()

            VStack(spacing: 18) {
                Text("🏆 FINAL PODIUM 🏆")
                    .font(Theme.title(46))
                    .foregroundStyle(Theme.yellow)
                    .neonGlow(Theme.yellow)
                    .padding(.top, 28)

                if let winner = ranked.first {
                    Text("\(winner.avatar) \(winner.name) WINS!")
                        .font(Theme.title(34))
                        .foregroundStyle(.white)
                }

                Spacer()

                podiumBlocks

                if ranked.count > 3 {
                    HStack(spacing: 22) {
                        ForEach(ranked.dropFirst(3)) { player in
                            Text("#\(rank(of: player))  \(player.avatar) \(player.name) · \(player.score)")
                                .font(Theme.body(18))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .padding(.bottom, 4)
                }

                Text("Replay votes: \(room.podium?.replayVotes.count ?? 0)/\(room.players.count) — vote on your phones 🔁")
                    .font(Theme.body(20))
                    .foregroundStyle(Theme.cyan.opacity(0.85))
                    .padding(.bottom, 26)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.3)) {
                risen = true
            }
        }
    }

    private func rank(of player: PlayerState) -> Int {
        (ranked.firstIndex(of: player) ?? 0) + 1
    }

    private var podiumBlocks: some View {
        let top3 = Array(ranked.prefix(3))
        // Visual order: silver, gold, bronze.
        let arrangement: [(player: PlayerState, place: Int)] = {
            var slots: [(PlayerState, Int)] = []
            if top3.count > 1 { slots.append((top3[1], 2)) }
            if top3.count > 0 { slots.append((top3[0], 1)) }
            if top3.count > 2 { slots.append((top3[2], 3)) }
            return slots
        }()
        let heights: [Int: CGFloat] = [1: 240, 2: 170, 3: 120]
        let colors: [Int: Color] = [1: Theme.yellow, 2: Color(hex: "#C0C8D8"), 3: Color(hex: "#CD7F32")]

        return HStack(alignment: .bottom, spacing: 18) {
            ForEach(arrangement, id: \.player.id) { slot in
                VStack(spacing: 10) {
                    if slot.place == 1 {
                        Text("👑").font(.system(size: 44))
                    }
                    AvatarChip(player: slot.player, size: slot.place == 1 ? 110 : 84)
                    Text("\(slot.player.score)")
                        .font(Theme.title(28))
                        .foregroundStyle(Theme.yellow)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [colors[slot.place]!.opacity(0.85), colors[slot.place]!.opacity(0.3)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 150, height: risen ? heights[slot.place]! : 8)
                        .overlay(
                            Text("\(slot.place)")
                                .font(Theme.title(54))
                                .foregroundStyle(Theme.bg.opacity(0.7))
                        )
                }
            }
        }
    }
}

/// Cheap and cheerful emoji confetti — no particle assets needed.
struct ConfettiRain: View {
    private struct Bit: Identifiable {
        let id: Int
        let emoji: String
        let x: CGFloat
        let delay: Double
        let duration: Double
        let size: CGFloat
    }

    private let bits: [Bit] = (0..<26).map { i in
        Bit(
            id: i,
            emoji: ["🎉", "🎊", "✨", "⭐️", "💛", "💜"].randomElement()!,
            x: CGFloat.random(in: 0.02...0.98),
            delay: Double.random(in: 0...2.4),
            duration: Double.random(in: 2.6...4.6),
            size: CGFloat.random(in: 22...42)
        )
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ForEach(bits) { bit in
                    let progress = ((t + bit.delay).truncatingRemainder(dividingBy: bit.duration)) / bit.duration
                    Text(bit.emoji)
                        .font(.system(size: bit.size))
                        .position(
                            x: geo.size.width * bit.x + sin(t * 2 + Double(bit.id)) * 18,
                            y: geo.size.height * progress - 40
                        )
                        .opacity(progress < 0.06 ? progress / 0.06 : 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
