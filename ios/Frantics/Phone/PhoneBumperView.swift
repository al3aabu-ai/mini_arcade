import SwiftUI

/// Bumper Sumo controller — a lightweight 2-D virtual joystick. Dragging the
/// thumb streams a normalized (x, y) vector to the host board (which runs the
/// physics). Deliberately NO 3D here: the board renders the arena on the TV;
/// the phone stays 2-D to save battery and avoid thermal buildup.
struct PhoneBumperView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared

    @State private var thumb: CGSize = .zero
    @State private var lastSent = Date.distantPast

    private let baseRadius: CGFloat = 110
    private let sendInterval: TimeInterval = 1.0 / 25.0

    private var bumper: BumperState? { client.room?.bumper }
    private var alive: Bool { bumper?.alive.contains(client.playerId) ?? false }
    private var iWon: Bool { bumper?.winnerId == client.playerId }

    var body: some View {
        VStack(spacing: 0) {
            SecretTaskCard()
            header

            if let bumper {
                if bumper.winnerId != nil || !alive {
                    resultView(bumper)
                } else {
                    Spacer()
                    joystick
                    Text(loc.tr("Drag to shove — knock them in the water!"))
                        .font(Theme.body(14))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 18)
                    Spacer()
                }
            }
        }
        .onChange(of: alive) { _, stillAlive in
            if !stillAlive { resetThumb() } // splashed → stop driving
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.tr("🤼 BUMPER ARENA"))
                    .font(Theme.title(24))
                    .foregroundStyle(.white)
                    .neonGlow(Theme.orange, radius: 8)
                if let bumper {
                    Text(loc.tr("%@ still in", "\(bumper.alive.count)"))
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
            if let bumper, bumper.winnerId == nil {
                CountdownLabel(endsAt: bumper.endsAtDate, font: Theme.title(34), color: Theme.orange)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    // MARK: joystick

    private var joystick: some View {
        ZStack {
            Circle()
                .fill(Theme.panel)
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 2))
                .frame(width: baseRadius * 2, height: baseRadius * 2)

            Circle()
                .fill(
                    LinearGradient(colors: [Theme.orange, Theme.red],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 96, height: 96)
                .neonGlow(Theme.orange, radius: 14)
                .offset(thumb)
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let raw = CGSize(width: value.translation.width, height: value.translation.height)
                    let dist = sqrt(raw.width * raw.width + raw.height * raw.height)
                    // Clamp the thumb to the base radius.
                    if dist > baseRadius {
                        let s = baseRadius / dist
                        thumb = CGSize(width: raw.width * s, height: raw.height * s)
                    } else {
                        thumb = raw
                    }
                    stream()
                }
                .onEnded { _ in resetThumb() }
        )
    }

    private func stream() {
        let now = Date()
        guard now.timeIntervalSince(lastSent) >= sendInterval else { return }
        lastSent = now
        // Normalize to [-1, 1] in screen space; the board maps y→forward (−Z).
        client.updateJoystick(x: Double(thumb.width / baseRadius), y: Double(thumb.height / baseRadius))
    }

    private func resetThumb() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { thumb = .zero }
        client.updateJoystick(x: 0, y: 0) // full stop
        lastSent = Date()
    }

    // MARK: result / spectator

    @ViewBuilder
    private func resultView(_ bumper: BumperState) -> some View {
        Spacer()
        if iWon {
            Text("🏆").font(.system(size: 96))
            Text(loc.tr("LAST ONE STANDING!"))
                .font(Theme.title(34))
                .foregroundStyle(Theme.yellow)
                .neonGlow(Theme.yellow)
        } else if alive {
            Text("🛟").font(.system(size: 80))
            Text(loc.tr("You survived!"))
                .font(Theme.title(30))
                .foregroundStyle(Theme.cyan)
        } else {
            Text("💦").font(.system(size: 80))
            Text(loc.tr("Splashed! Spectating…"))
                .font(Theme.title(28))
                .foregroundStyle(.white.opacity(0.7))
        }
        Spacer()
    }
}
