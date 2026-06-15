import SwiftUI

/// Bumper Sumo controller — a lightweight 2-D virtual joystick. Dragging the
/// thumb streams a normalized (x, y) vector to the host board (which runs the
/// physics). Deliberately NO 3D here: the board renders the arena on the TV;
/// the phone stays 2-D to save battery and avoid thermal buildup.
struct PhoneBumperView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @StateObject private var motion = BumperMotionController()

    @State private var thumb: CGSize = .zero
    @State private var lastSent = Date.distantPast

    private let baseRadius: CGFloat = 110
    private let sendInterval: TimeInterval = 1.0 / 25.0

    private var bumper: BumperState? { client.room?.bumper }
    private var alive: Bool { bumper?.alive.contains(client.playerId) ?? false }
    private var iWon: Bool { bumper?.winnerId == client.playerId }
    private var isMotion: Bool { bumper?.isMotion ?? false }
    private var spinningOut: Bool { client.me?.isSpinningOut ?? false }
    private var accent: Color { (bumper?.isIce ?? false) ? Theme.blue : Theme.orange }

    var body: some View {
        VStack(spacing: 0) {
            SecretTaskCard()
            header

            if let bumper {
                if bumper.winnerId != nil || !alive {
                    resultView(bumper)
                } else if isMotion {
                    tiltControl
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
        .onAppear {
            if isMotion {
                motion.onSample = { pitch, roll in client.updateMotionVector(pitch: pitch, roll: roll) }
                motion.start(streamHz: 30)           // 30Hz: smooth, light on battery/thermals
            }
        }
        .onDisappear { motion.stop() }
        .onChange(of: alive) { _, stillAlive in
            if !stillAlive { resetThumb(); motion.stop() } // splashed → stop driving
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.tr(isMotion ? "🧊 ICE SLAB" : "🤼 BUMPER ARENA"))
                    .font(Theme.title(24))
                    .foregroundStyle(.white)
                    .neonGlow(accent, radius: 8)
                if let bumper {
                    Text(loc.tr("%@ still in", "\(bumper.alive.count)"))
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
            if let bumper, bumper.winnerId == nil {
                CountdownLabel(endsAt: bumper.endsAtDate, font: Theme.title(34), color: accent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    // MARK: tilt (motion) control — a tray balance level, NO 3D on the phone

    private var tiltControl: some View {
        VStack(spacing: 20) {
            Spacer()
            if spinningOut {
                Text("🌀")
                    .font(.system(size: 92))
                    .rotationEffect(.degrees(spinningOut ? 360 : 0))
                    .animation(.linear(duration: 0.5).repeatForever(autoreverses: false), value: spinningOut)
                Text(loc.tr("SPINNING OUT!")).font(Theme.title(30)).foregroundStyle(Theme.red).neonGlow(Theme.red)
                Text(loc.tr("You over-tilted — hold steady!"))
                    .font(Theme.body(14)).foregroundStyle(.white.opacity(0.6))
            } else {
                Text(loc.tr("Hold your phone flat like a tray"))
                    .font(Theme.title(20)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                bubbleLevel
                Text(loc.tr("Tilt to slide · don't tip past the edge"))
                    .font(Theme.body(14)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if !motion.available {
                Text(loc.tr("Motion sensor unavailable on this device"))
                    .font(Theme.body(13)).foregroundStyle(Theme.yellow)
            }
            Button(loc.tr("Re-center")) { motion.recalibrate(); Haptics.tick() }
                .buttonStyle(NeonButtonStyle(color: Theme.panelLight))
                .padding(.horizontal, 70).padding(.bottom, 22)
        }
    }

    /// Bubble-level: the dot is your live tilt; the dashed ring is the 30° edge.
    private var bubbleLevel: some View {
        let r: CGFloat = 120
        let mag = (motion.roll * motion.roll + motion.pitch * motion.pitch).squareRoot()
        let danger = mag > 0.42
        return ZStack {
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: 2)
            Circle()
                .strokeBorder(Theme.red.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .frame(width: r, height: r) // radius 0.5·r ≈ sin(30°) over-tilt boundary
            Circle()
                .fill(danger ? Theme.red : accent)
                .frame(width: 54, height: 54)
                .neonGlow(danger ? Theme.red : accent, radius: 12)
                .offset(x: CGFloat(motion.roll) * r, y: CGFloat(motion.pitch) * r)
                .animation(.interactiveSpring(response: 0.15), value: motion.roll)
                .animation(.interactiveSpring(response: 0.15), value: motion.pitch)
        }
        .frame(width: r * 2, height: r * 2)
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
