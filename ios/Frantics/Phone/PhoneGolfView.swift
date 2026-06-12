import SwiftUI

/// Guerilla Golf controller: a dark touchpad. Drag back like a slingshot,
/// release to fire. Aim updates stream to the host board (throttled ~30/s,
/// per the design doc's network budget).
struct PhoneGolfView: View {
    @EnvironmentObject var client: GameClient

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var lastAimSent = Date.distantPast

    private let maxPull: CGFloat = 280
    private let aimInterval: TimeInterval = 1.0 / 30.0

    private var golf: GolfState? { client.room?.golf }
    private var anviled: Bool { golf?.debuffs[client.playerId] == "anvil" }
    private var finishedPlace: Int? {
        guard let order = golf?.results?.order, let idx = order.firstIndex(of: client.playerId)
        else { return nil }
        return idx + 1
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
            header

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
                            Text("Drag back. Release to launch.\nWatch the TV — knock your friends off the map.")
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
            .padding(16)
        }
        .overlay {
            if let place = finishedPlace {
                sunkOverlay(place: place)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("⛳️ GUERILLA GOLF")
                    .font(Theme.title(20))
                    .foregroundStyle(.white)
                Spacer()
                if let golf {
                    CountdownLabel(endsAt: golf.endsAtDate, font: Theme.title(24))
                }
            }
            if anviled {
                Label("ANVILED — your shots are 30% weaker", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.yellow))
            }
            if let l = launch {
                Text("POWER \(Int(l.power * 100))%")
                    .font(Theme.body(15))
                    .foregroundStyle(l.power > 0.85 ? Theme.red : Theme.cyan)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func slingshotOverlay(start: CGPoint, current: CGPoint) -> some View {
        ZStack {
            // Rubber band from anchor to thumb.
            Path { p in
                p.move(to: start)
                p.addLine(to: current)
            }
            .stroke(
                Theme.pink.opacity(0.85),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 8])
            )

            // Anchor + projected launch direction.
            Circle()
                .fill(Theme.cyan)
                .frame(width: 18, height: 18)
                .position(start)
                .neonGlow(Theme.cyan)

            if let l = launch {
                let len = 60 + 120 * l.power
                let end = CGPoint(
                    x: start.x + cos(l.angle) * len,
                    y: start.y - sin(l.angle) * len
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
                Text("IN THE HOLE!")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.cyan)
                    .neonGlow(Theme.cyan)
                Text("You finished #\(place)")
                    .font(Theme.body(18))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: input -> network

    private func streamAim() {
        guard let l = launch else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAimSent) >= aimInterval else { return }
        lastAimSent = now
        client.sendAim(angle: l.angle, power: l.power)
    }

    private func release() {
        if let l = launch, l.power > 0.06 {
            Haptics.thump(intensity: l.power)
            client.fire(angle: l.angle, power: l.power)
        } else {
            client.sendAimClear()
        }
        dragStart = nil
        dragCurrent = nil
    }
}
