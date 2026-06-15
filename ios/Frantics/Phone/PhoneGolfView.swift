import SwiftUI

/// Guerilla Golf controller — turn-based. On your turn the screen becomes a
/// slingshot touchpad (drag back, release to fire, aim streamed ~30/s).
/// Off-turn you see who's shooting; once you sink you spectate.
struct PhoneGolfView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var lastAimSent = Date.distantPast

    private let maxPull: CGFloat = 280
    private let aimInterval: TimeInterval = 1.0 / 30.0

    private var golf: GolfState? { client.room?.golf }
    private var anviled: Bool { client.me?.modifier == "anvil" }
    private var goldenClub: Bool { client.me?.modifier == "golden_club" }
    private var myTurn: Bool { golf?.turnId == client.playerId }

    private var finishedPlace: Int? {
        if let order = golf?.results?.order, let idx = order.firstIndex(of: client.playerId) {
            return idx + 1
        }
        if let sunk = golf?.sunk, let idx = sunk.firstIndex(of: client.playerId) {
            return idx + 1
        }
        return nil
    }

    private var launch: (angle: Double, power: Double)? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        let dx = current.x - start.x
        let dy = current.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 8 else { return nil }
        // Slingshot: launch opposite the drag. Screen y points down, so the
        // launch vector in math coords (y up) is (-dx, dy).
        let angle = atan2(dy, -dx)
        let power = min(1, distance / maxPull)
        return (Double(angle), Double(power))
    }

    var body: some View {
        VStack(spacing: 0) {
            SecretTaskCard()
            header

            if finishedPlace != nil {
                Spacer()
            } else if myTurn {
                touchpad
            } else {
                waitingView
            }
        }
        .overlay {
            if let place = finishedPlace {
                sunkOverlay(place: place)
            }
        }
        .onChange(of: golf?.turnId) { _, _ in
            // New shooter: drop any half-finished drag.
            dragStart = nil
            dragCurrent = nil
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text(loc.tr("⛳️ GUERILLA GOLF"))
                    .font(Theme.title(20))
                    .foregroundStyle(.white)
                Spacer()
                if let golf {
                    CountdownLabel(endsAt: golf.endsAtDate, font: Theme.title(24))
                }
            }
            if anviled {
                Label(loc.tr("ANVILED — your shots are 30% weaker"), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.yellow))
            } else if goldenClub {
                Label(loc.tr("GOLDEN CLUB — your shots launch at DOUBLE power"), systemImage: "bolt.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.cyan))
            }
            if myTurn, let l = launch {
                Text(loc.tr("POWER %@%%", "\(Int(l.power * 100))"))
                    .font(Theme.body(15))
                    .foregroundStyle(l.power > 0.85 ? Theme.red : Theme.cyan)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: your shot

    private var touchpad: some View {
        VStack(spacing: 10) {
            Text(loc.tr("🎯 YOUR SHOT"))
                .font(Theme.title(24))
                .foregroundStyle(Theme.yellow)
                .neonGlow(Theme.yellow)
                .padding(.top, 6)

            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(Theme.cyan.opacity(0.25), lineWidth: 1.5)
                        )

                    if let start = dragStart, let current = dragCurrent {
                        slingshotOverlay(start: start, current: current)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "hand.draw.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.cyan.opacity(0.5))
                            Text(loc.tr("Drag back. Release to launch.\nOne shot — make it count."))
                                .font(Theme.body(15))
                                .foregroundStyle(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                            dragCurrent = value.location
                            streamAim()
                        }
                        .onEnded { _ in
                            release()
                        }
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding([.horizontal, .bottom], 16)
        }
    }

    // MARK: someone else's shot

    private var waitingView: some View {
        let shooter = client.room?.player(golf?.turnId)
        return VStack(spacing: 16) {
            Spacer()
            Text(shooter?.avatar ?? "⏳")
                .font(.system(size: 80))
            if let shooter {
                Text(loc.tr("%@ IS SHOOTING", shooter.name.uppercased()))
                    .font(Theme.title(24))
                    .foregroundStyle(Color(hex: shooter.color))
                    .multilineTextAlignment(.center)
            } else {
                // No active shooter = the board is still settling the last shot.
                // Controls stay locked until every ball stops. (Requirement 2)
                Text(loc.tr("⏳ BALLS STILL ROLLING…"))
                    .font(Theme.title(24))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Text(loc.tr("👀 Watch the TV — your turn is coming."))
                .font(Theme.body(15))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func slingshotOverlay(start: CGPoint, current: CGPoint) -> some View {
        ZStack {
            Path { p in
                p.move(to: start)
                p.addLine(to: current)
            }
            .stroke(
                Theme.pink.opacity(0.85),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 8])
            )

            Circle()
                .fill(Theme.cyan)
                .frame(width: 18, height: 18)
                .position(start)
                .neonGlow(Theme.cyan)

            if let l = launch {
                let len = 60 + 120 * l.power
                let end = CGPoint(
                    x: start.x + Foundation.cos(l.angle) * len,
                    y: start.y - Foundation.sin(l.angle) * len
                )
                Path { p in
                    p.move(to: start)
                    p.addLine(to: end)
                }
                .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Circle()
                    .fill(Theme.yellow)
                    .frame(width: 12, height: 12)
                    .position(end)
            }

            Circle()
                .fill(Theme.pink)
                .frame(width: 26, height: 26)
                .position(current)
                .neonGlow(Theme.pink)
        }
    }

    private func sunkOverlay(place: Int) -> some View {
        let medals = ["🥇", "🥈", "🥉"]
        return ZStack {
            Theme.bg.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(place <= 3 ? medals[place - 1] : "⛳️")
                    .font(.system(size: 80))
                Text(loc.tr("IN THE HOLE!"))
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.cyan)
                    .neonGlow(Theme.cyan)
                Text(loc.tr("You finished #%@ — enjoy the show", "\(place)"))
                    .font(Theme.body(18))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: input -> network

    private func streamAim() {
        guard myTurn, let l = launch else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAimSent) >= aimInterval else { return }
        lastAimSent = now
        client.sendAim(angle: l.angle, power: l.power)
    }

    private func release() {
        defer {
            dragStart = nil
            dragCurrent = nil
        }
        guard myTurn else { return }
        if let l = launch, l.power > 0.06 {
            Haptics.thump(intensity: l.power)
            client.fire(angle: l.angle, power: l.power)
        } else {
            client.sendAimClear()
        }
    }
}

/// Expandable "Secret Task" banner shown at the top of the golf & bomb
/// controllers. Reads the player's OWN private task (`client.me?.secretTask`);
/// it never exists for other players or on the TV. Tap to expand the details.
struct SecretTaskCard: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @State private var expanded = false
    /// On the podium we only want the success confirmation, never an active task.
    var completedOnly: Bool = false

    private var task: SecretTask? { client.me?.secretTask }

    var body: some View {
        if let task, !(completedOnly && !task.isCompleted) {
            VStack(spacing: 0) {
                if task.isCompleted {
                    // Post-game confirmation: "Task complete! +150 coins".
                    HStack(spacing: 8) {
                        Text("✅")
                        Text(loc.tr("Task complete! +%@ coins", "\(task.rewardCoins)"))
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.cyan)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.cyan.opacity(0.16))
                } else {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() }
                        Haptics.tick()
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Text("🤫")
                                Text(loc.tr("Secret Task"))
                                    .font(Theme.body(14))
                                    .foregroundStyle(Theme.yellow)
                                    .kerning(1)
                                Spacer()
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            if expanded {
                                Text(task.description(arabic: loc.isArabic))
                                    .font(Theme.body(15))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                Text(loc.tr("+%@ coins · kept secret", "\(task.rewardCoins)"))
                                    .font(Theme.body(12))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.panel.opacity(0.95))
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
