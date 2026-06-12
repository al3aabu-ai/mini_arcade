import SwiftUI
import SpriteKit

struct GolfPlayerInfo {
    let id: String
    let name: String
    let avatar: String
    let colorHex: String
    let anviled: Bool
}

/// TV view for Guerilla Golf: SpriteKit physics + a SwiftUI HUD.
/// The host device is the physics authority (per the design doc) and reports
/// the finish order back to the server when the round ends.
struct GolfBoardView: View {
    @EnvironmentObject var client: GameClient
    @State private var scene: GolfScene?
    @State private var finished: [PlayerState] = []

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }
            hud
        }
        .onAppear { setup() }
        .onDisappear {
            client.onAim = nil
            client.onAimClear = nil
            client.onFire = nil
        }
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                Text("⛳️ GUERILLA GOLF")
                    .font(Theme.title(30))
                    .foregroundStyle(.white)
                    .neonGlow(Theme.cyan, radius: 10)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let golf = client.room?.golf {
                        CountdownLabel(endsAt: golf.endsAtDate, font: Theme.title(42))
                    }
                    Text("1st 500 · 2nd 300 · 3rd 200")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.yellow.opacity(0.8))
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)

            HStack(spacing: 12) {
                ForEach(Array(finished.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 6) {
                        Text(index < 3 ? ["🥇", "🥈", "🥉"][index] : "🏁")
                        Text("\(player.avatar) \(player.name)")
                            .font(Theme.body(16))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.panel.opacity(0.9)))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: finished)

            Spacer()
        }
    }

    private func setup() {
        guard scene == nil, let room = client.room, let golf = room.golf else { return }
        let infos = room.players.map { player in
            GolfPlayerInfo(
                id: player.id,
                name: player.name,
                avatar: player.avatar,
                colorHex: player.color,
                anviled: golf.debuffs[player.id] == "anvil"
            )
        }
        let golfScene = GolfScene(
            players: infos,
            endsAt: golf.endsAtDate,
            onSank: { playerId in
                if let p = room.player(playerId) {
                    finished.append(p)
                }
            },
            onFinished: { order in
                client.golfFinished(order: order)
            }
        )
        client.onAim = { [weak golfScene] id, angle, power in
            golfScene?.setAim(playerId: id, angle: angle, power: power)
        }
        client.onAimClear = { [weak golfScene] id in
            golfScene?.clearAim(playerId: id)
        }
        client.onFire = { [weak golfScene] id, angle, power in
            golfScene?.fire(playerId: id, angle: angle, power: power)
        }
        scene = golfScene
    }
}

// MARK: - The physics scene

final class GolfScene: SKScene {
    private struct Ball {
        let info: GolfPlayerInfo
        let node: SKShapeNode
        let tee: CGPoint
        var sunk = false
        var respawning = false
        var lastFire: TimeInterval = 0
    }

    private let players: [GolfPlayerInfo]
    private let endsAt: Date
    private let onSank: (String) -> Void
    private let onFinished: ([String]) -> Void

    private var balls: [String: Ball] = [:]
    private var aimNodes: [String: SKShapeNode] = [:]
    private var finishOrder: [String] = []
    private var done = false

    private let holeCenter = CGPoint(x: 1415, y: 100)
    private let designSize = CGSize(width: 1600, height: 900)

    init(
        players: [GolfPlayerInfo],
        endsAt: Date,
        onSank: @escaping (String) -> Void,
        onFinished: @escaping ([String]) -> Void
    ) {
        self.players = players
        self.endsAt = endsAt
        self.onSank = onSank
        self.onFinished = onFinished
        super.init(size: designSize)
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.12, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        buildCourse()
        spawnBalls()
    }

    // MARK: course

    private func buildCourse() {
        let walls = CGMutablePath()
        walls.move(to: CGPoint(x: 0, y: -500))
        walls.addLine(to: CGPoint(x: 0, y: 900))
        walls.addLine(to: CGPoint(x: 1600, y: 900))
        walls.addLine(to: CGPoint(x: 1600, y: -500))
        addEdgeChain(walls)

        // Tee platform — everyone starts here.
        addPlatform(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 170),
            CGPoint(x: 360, y: 170), CGPoint(x: 360, y: 0),
        ], topColor: Theme.cyanUI)

        // Mid platform across the first pit.
        addPlatform(points: [
            CGPoint(x: 480, y: 0), CGPoint(x: 480, y: 210),
            CGPoint(x: 740, y: 210), CGPoint(x: 740, y: 0),
        ], topColor: Theme.purpleUI)

        // Bumpers that fling balls around.
        addBumper(at: CGPoint(x: 900, y: 330), radius: 52)
        addBumper(at: CGPoint(x: 1080, y: 180), radius: 44)

        // Spinning paddle of misery.
        let paddle = SKShapeNode(rectOf: CGSize(width: 170, height: 16), cornerRadius: 8)
        paddle.fillColor = Theme.pinkUI
        paddle.strokeColor = .clear
        paddle.position = CGPoint(x: 640, y: 470)
        paddle.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 170, height: 16))
        paddle.physicsBody?.isDynamic = false
        paddle.physicsBody?.restitution = 0.9
        paddle.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.6)))
        addChild(paddle)

        // Green: ramp up to a shelf with the cup sunk into it.
        let green = CGMutablePath()
        green.move(to: CGPoint(x: 1100, y: -500))
        green.addLine(to: CGPoint(x: 1100, y: 0))
        green.addLine(to: CGPoint(x: 1240, y: 130))
        green.addLine(to: CGPoint(x: 1380, y: 130))
        green.addLine(to: CGPoint(x: 1386, y: 76))
        green.addLine(to: CGPoint(x: 1444, y: 76))
        green.addLine(to: CGPoint(x: 1450, y: 130))
        green.addLine(to: CGPoint(x: 1600, y: 130))
        addEdgeChain(green)

        let greenShape = SKShapeNode(path: green)
        greenShape.strokeColor = Theme.limeUI
        greenShape.lineWidth = 4
        greenShape.glowWidth = 3
        addChild(greenShape)

        // Hole glow + flag.
        let glow = SKShapeNode(circleOfRadius: 30)
        glow.position = holeCenter
        glow.strokeColor = Theme.yellowUI
        glow.lineWidth = 3
        glow.glowWidth = 8
        glow.fillColor = UIColor(white: 0, alpha: 0.6)
        glow.run(.repeatForever(.sequence([
            .scale(to: 1.18, duration: 0.7),
            .scale(to: 0.94, duration: 0.7),
        ])))
        addChild(glow)

        let flag = SKLabelNode(text: "⛳️")
        flag.fontSize = 56
        flag.position = CGPoint(x: holeCenter.x, y: holeCenter.y + 64)
        addChild(flag)

        // Decorative pit warnings.
        for x in [420, 920] {
            let skull = SKLabelNode(text: "☠️")
            skull.fontSize = 34
            skull.alpha = 0.5
            skull.position = CGPoint(x: CGFloat(x), y: 30)
            addChild(skull)
        }
    }

    private func addEdgeChain(_ path: CGPath) {
        let node = SKNode()
        node.physicsBody = SKPhysicsBody(edgeChainFrom: path)
        node.physicsBody?.friction = 0.45
        node.physicsBody?.restitution = 0.25
        addChild(node)
    }

    private func addPlatform(points: [CGPoint], topColor: UIColor) {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = UIColor(red: 0.10, green: 0.10, blue: 0.24, alpha: 1)
        shape.strokeColor = topColor
        shape.lineWidth = 4
        shape.glowWidth = 2
        addChild(shape)

        let edges = CGMutablePath()
        edges.addLines(between: points)
        addEdgeChain(edges)
    }

    private func addBumper(at position: CGPoint, radius: CGFloat) {
        let bumper = SKShapeNode(circleOfRadius: radius)
        bumper.position = position
        bumper.fillColor = UIColor(red: 0.13, green: 0.13, blue: 0.3, alpha: 1)
        bumper.strokeColor = Theme.orangeUI
        bumper.lineWidth = 5
        bumper.glowWidth = 4
        bumper.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        bumper.physicsBody?.isDynamic = false
        bumper.physicsBody?.restitution = 0.95
        addChild(bumper)
    }

    // MARK: balls

    private func spawnBalls() {
        for (index, info) in players.enumerated() {
            let tee = CGPoint(x: 50 + CGFloat(index) * 43, y: 215)
            let node = SKShapeNode(circleOfRadius: 21)
            node.fillColor = UIColor(Color(hex: info.colorHex)).withAlphaComponent(0.9)
            node.strokeColor = .white
            node.lineWidth = 2
            node.position = tee

            let face = SKLabelNode(text: info.avatar)
            face.fontSize = 24
            face.verticalAlignmentMode = .center
            node.addChild(face)

            let tag = SKLabelNode(text: info.name)
            tag.fontSize = 14
            tag.fontName = "AvenirNext-Bold"
            tag.fontColor = .white
            tag.position = CGPoint(x: 0, y: -40)
            node.addChild(tag)

            if info.anviled {
                let anvil = SKLabelNode(text: "🪨")
                anvil.fontSize = 16
                anvil.position = CGPoint(x: 0, y: 26)
                node.addChild(anvil)
            }

            let body = SKPhysicsBody(circleOfRadius: 21)
            body.restitution = 0.55
            body.friction = 0.3
            body.linearDamping = 0.35
            body.allowsRotation = false // keeps the emoji face upright
            node.physicsBody = body

            addChild(node)
            balls[info.id] = Ball(info: info, node: node, tee: tee)
        }
    }

    // MARK: input from phones (relayed via the server)

    func setAim(playerId: String, angle: Double, power: Double) {
        guard let ball = balls[playerId], !ball.sunk else { return }
        let aim: SKShapeNode
        if let existing = aimNodes[playerId] {
            aim = existing
        } else {
            aim = SKShapeNode()
            aim.strokeColor = UIColor(Color(hex: ball.info.colorHex))
            aim.lineWidth = 5
            aim.glowWidth = 3
            aim.zPosition = 10
            addChild(aim)
            aimNodes[playerId] = aim
        }
        let length = 70 + 230 * CGFloat(power)
        let from = ball.node.position
        let to = CGPoint(
            x: from.x + cos(angle) * length,
            y: from.y + sin(angle) * length
        )
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        aim.path = path.copy(dashingWithPhase: 0, lengths: [14, 10])
    }

    func clearAim(playerId: String) {
        aimNodes[playerId]?.removeFromParent()
        aimNodes[playerId] = nil
    }

    func fire(playerId: String, angle: Double, power: Double) {
        clearAim(playerId: playerId)
        guard var ball = balls[playerId], !ball.sunk, !ball.respawning else { return }
        let now = CACurrentMediaTime()
        guard now - ball.lastFire > 0.45 else { return }
        ball.lastFire = now
        balls[playerId] = ball

        let factor: Double = ball.info.anviled ? 0.7 : 1.0 // the Heavy Anvil at work
        let speed = (420 + 1180 * min(1, max(0, power))) * factor
        ball.node.physicsBody?.velocity = CGVector(
            dx: cos(angle) * speed,
            dy: sin(angle) * speed
        )
        ball.node.run(.sequence([.scale(to: 1.25, duration: 0.07), .scale(to: 1.0, duration: 0.12)]))
    }

    // MARK: frame loop

    override func update(_ currentTime: TimeInterval) {
        guard !done else { return }

        for (id, var ball) in balls where !ball.sunk {
            let pos = ball.node.position
            let velocity = ball.node.physicsBody?.velocity ?? .zero
            let speed = hypot(velocity.dx, velocity.dy)

            // Sink: close to the cup and slow enough.
            if hypot(pos.x - holeCenter.x, pos.y - holeCenter.y) < 30, speed < 420 {
                ball.sunk = true
                balls[id] = ball
                finishOrder.append(id)
                celebrate(at: pos)
                ball.node.physicsBody = nil
                ball.node.run(.sequence([
                    .group([.move(to: holeCenter, duration: 0.18), .scale(to: 0.2, duration: 0.25)]),
                    .fadeOut(withDuration: 0.15),
                ]))
                onSank(id)
                continue
            }

            // Knocked off the map -> respawn at the tee.
            if pos.y < -140, !ball.respawning {
                ball.respawning = true
                balls[id] = ball
                ball.node.physicsBody?.velocity = .zero
                ball.node.run(.sequence([
                    .fadeAlpha(to: 0.0, duration: 0.1),
                    .wait(forDuration: 0.8),
                    .run { [weak self] in
                        guard let self, var b = self.balls[id] else { return }
                        b.node.position = b.tee
                        b.node.physicsBody?.velocity = .zero
                        b.respawning = false
                        self.balls[id] = b
                    },
                    .fadeAlpha(to: 1.0, duration: 0.2),
                ]))
            }
        }

        if finishOrder.count == balls.count || Date() >= endsAt {
            finishGame()
        }
    }

    private func celebrate(at position: CGPoint) {
        for _ in 0..<14 {
            let bit = SKLabelNode(text: ["🎉", "✨", "💛", "⭐️"].randomElement()!)
            bit.fontSize = 26
            bit.position = position
            addChild(bit)
            let dx = CGFloat.random(in: -160...160)
            let dy = CGFloat.random(in: 60...260)
            bit.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.7),
                    .fadeOut(withDuration: 0.7),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func finishGame() {
        guard !done else { return }
        done = true
        let order = finishOrder
        // Hop out of the render loop before touching the network layer.
        DispatchQueue.main.async { [onFinished] in
            onFinished(order)
        }
    }
}

// UIKit-side colors for SpriteKit nodes.
private extension Theme {
    static let cyanUI = UIColor(Theme.cyan)
    static let pinkUI = UIColor(Theme.pink)
    static let yellowUI = UIColor(Theme.yellow)
    static let purpleUI = UIColor(Theme.purple)
    static let orangeUI = UIColor(Theme.orange)
    static let limeUI = UIColor(Color(hex: "#8AC926"))
}
