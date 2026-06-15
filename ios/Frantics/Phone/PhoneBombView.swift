import SwiftUI

/// The Billionaire's Bomb controller. Hold to get rich, tilt + tap PASS to
/// shove the bomb at a neighbor before it blows.
struct PhoneBombView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @StateObject private var tilt = TiltManager()
    @State private var chosenDirection = "right"
    @State private var pulse = false

    private var bomb: BombState? { client.room?.bomb }
    private var holding: Bool { bomb?.holderId == client.playerId && bomb?.stage == "ticking" }
    private var eliminated: Bool { bomb?.eliminated.contains(client.playerId) ?? false }
    private var myEarnings: Int { bomb?.earnings[client.playerId] ?? 0 }

    private var effectiveDirection: String { tilt.direction ?? chosenDirection }

    var body: some View {
        VStack(spacing: 18) {
            SecretTaskCard()
            if let bomb {
                if eliminated {
                    spectator
                } else if bomb.stage == "done" {
                    survived(bomb)
                } else if holding {
                    holdingView(bomb)
                } else {
                    watching(bomb)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .onChange(of: holding) { _, isHolding in
            if isHolding { Haptics.failure() }
            pulse = isHolding
        }
    }

    // MARK: holding the bomb

    @ViewBuilder
    private func holdingView(_ bomb: BombState) -> some View {
        let jammedUntil = bomb.jamUntilDate
        VStack(spacing: 4) {
            Text(loc.tr("YOU HAVE THE BOMB"))
                .font(Theme.title(24))
                .foregroundStyle(Theme.red)
                .neonGlow(Theme.red)
            Text(loc.tr("💵 +$%@  ·  greed ×%@", "\(myEarnings)", String(format: "%.2f", bomb.multiplier)))
                .font(Theme.body(16))
                .foregroundStyle(Theme.yellow)
                .contentTransition(.numericText())
        }

        Text("💣")
            .font(.system(size: 110))
            .scaleEffect(pulse ? 1.12 : 0.95)
            .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: pulse)
            .onReceive(Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()) { _ in
                if holding { Haptics.thump(intensity: min(1, 0.4 + bomb.multiplier / 8)) }
            }

        directionPicker

        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let jamLeft = jammedUntil.map { max(0, $0.timeIntervalSince(context.date)) } ?? 0
            Button {
                Haptics.thump()
                client.passBomb(direction: effectiveDirection)
            } label: {
                if jamLeft > 0 {
                    Text(loc.tr("🧈 JAMMED %@s", String(format: "%.1f", jamLeft)))
                } else {
                    Text(loc.tr("PASS %@", effectiveDirection == "left" ? "◀️" : "▶️"))
                }
            }
            .buttonStyle(NeonButtonStyle(color: jamLeft > 0 ? Theme.panelLight : Theme.red))
            .disabled(jamLeft > 0)
        }

        Text(loc.tr("Hold it to milk the pot. Pass before it pops."))
            .font(Theme.body(13))
            .foregroundStyle(.white.opacity(0.45))
    }

    private var directionPicker: some View {
        HStack(spacing: 14) {
            directionButton("left", label: loc.tr("◀️ LEFT"))
            // Live tilt needle
            ZStack {
                Capsule().fill(Theme.panel).frame(height: 10)
                GeometryReader { geo in
                    Circle()
                        .fill(Theme.cyan)
                        .frame(width: 16, height: 16)
                        .position(
                            x: geo.size.width / 2 + CGFloat(tilt.tilt) * (geo.size.width / 2 - 10),
                            y: geo.size.height / 2
                        )
                }
            }
            .frame(width: 90, height: 18)
            directionButton("right", label: loc.tr("RIGHT ▶️"))
        }
    }

    private func directionButton(_ dir: String, label: String) -> some View {
        Button {
            chosenDirection = dir
            Haptics.tick()
        } label: {
            Text(label)
                .font(Theme.body(15))
                .foregroundStyle(effectiveDirection == dir ? Theme.bg : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(effectiveDirection == dir ? Theme.cyan : Theme.panel)
                )
        }
    }

    // MARK: not holding

    @ViewBuilder
    private func watching(_ bomb: BombState) -> some View {
        let holder = client.room?.player(bomb.holderId)
        if bomb.stage == "exploded" {
            let victim = client.room?.player(bomb.lastExplodedId)
            Text("💥").font(.system(size: 100))
            Text(loc.tr("%@ EXPLODED", victim?.name ?? loc.tr("Someone")))
                .font(Theme.title(26))
                .foregroundStyle(Theme.orange)
        } else {
            Text("🧨").font(.system(size: 64))
            Text(loc.tr("%@ %@ is holding the bomb", holder?.name ?? "…", holder?.avatar ?? ""))
                .font(Theme.title(20))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(loc.tr("Your stash this game: $%@", "\(myEarnings)"))
                .font(Theme.body(16))
                .foregroundStyle(Theme.yellow)
                .contentTransition(.numericText())
            Text(loc.tr("Stay calm. It might come your way."))
                .font(Theme.body(13))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var spectator: some View {
        VStack(spacing: 12) {
            Text("💀").font(.system(size: 90)).grayscale(1)
            Text(loc.tr("YOU BLEW UP"))
                .font(Theme.title(28))
                .foregroundStyle(.white.opacity(0.5))
            Text(loc.tr("Your unbanked cash burned with you.\nEnjoy the show from the afterlife."))
                .font(Theme.body(14))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25))
    }

    @ViewBuilder
    private func survived(_ bomb: BombState) -> some View {
        let survived = bomb.survivors?.contains(client.playerId) ?? false
        Text(survived ? "🏆" : "💸").font(.system(size: 90))
        Text(loc.tr(survived ? "YOU SURVIVED" : "ROUND OVER"))
            .font(Theme.title(28))
            .foregroundStyle(survived ? Theme.cyan : .white.opacity(0.6))
        if survived {
            Text(loc.tr("Banked $%@ + $250 survivor bonus", "\(myEarnings)"))
                .font(Theme.body(16))
                .foregroundStyle(Theme.yellow)
        }
    }
}
