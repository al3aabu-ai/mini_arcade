import SwiftUI
import SceneKit

struct GolfPlayerInfo {
    let id: String
    let name: String
    let avatar: String
    let colorHex: String
    let anviled: Bool
}

/// Guerilla Golf on the TV — Frantics-PS4 style: a floating low-poly 3D
/// island with gaps, bumpers and a spinning paddle, rendered with SceneKit.
/// The host device is the physics authority and reports the finish order.
/// Phones still send the same `aim`/`fire` messages: the drag direction maps
/// onto the ground plane (drag up = launch toward the hole).
struct GolfBoardView: View {
    @EnvironmentObject var client: GameClient
    @State private var controller: GolfSceneController?
    @State private var finished: [PlayerState] = []

    var body: some View {
        ZStack {
            if let controller {
                SceneView(
                    scene: controller.scene,
                    pointOfView: controller.cameraNode,
                    options: [],
                    delegate: controller
                )
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
        guard controller == nil, let room = client.room, let golf = room.golf else { return }
        let infos = room.players.map { player in
            GolfPlayerInfo(
                id: player.id,
                name: player.name,
                avatar: player.avatar,
                colorHex: player.color,
                anviled: golf.debuffs[player.id] == "anvil"
            )
        }
        let sceneController = GolfSceneController(
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
        client.onAim = { [weak sceneController] id, angle, power in
            sceneController?.setAim(playerId: id, angle: angle, power: power)
        }
        client.onAimClear = { [weak sceneController] id in
            sceneController?.clearAim(playerId: id)
        }
        client.onFire = { [weak sceneController] id, angle, power in
            sceneController?.fire(playerId: id, angle: angle, power: power)
        }
        controller = sceneController
    }
}

// MARK: - SceneKit world

final class GolfSceneController: NSObject, SCNSceneRendererDelegate {
    private struct Ball {
        let info: GolfPlayerInfo
        let node: SCNNode
        let tag: SCNNode
        let tee: SCNVector3
        let tagHeight: Float
        var sunk = false
        var respawning = false
        var lastFire: TimeInterval = 0
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let players: [GolfPlayerInfo]
    private let endsAt: Date
    private let onSank: (String) -> Void
    private let onFinished: ([String]) -> Void

    private var balls: [String: Ball] = [:]
    private var aimNodes: [String: SCNNode] = [:]
    private var finishOrder: [String] = []
    private var done = false

    // Course coordinates: x = width, z = depth. Tee at +z, hole at -z.
    private let holeCenter = SCNVector3(2.6, 0, -13)

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
        super.init()
        buildWorld()
        spawnBalls()
    }

    // MARK: world building

    private func material(_ color: UIColor, emissive: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .blinn
        if let emissive { m.emission.contents = emissive }
        return m
    }

    private func buildWorld() {
        scene.background.contents = UIColor(red: 0.03, green: 0.03, blue: 0.1, alpha: 1)
        scene.fogColor = UIColor(red: 0.03, green: 0.03, blue: 0.1, alpha: 1)
        scene.fogStartDistance = 42
        scene.fogEndDistance = 90
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)

        // Camera: high angled party view, like the PS4 original.
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 52
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(0, 19, 29)
        let lookTarget = SCNNode()
        lookTarget.position = SCNVector3(0, 0, -4)
        scene.rootNode.addChildNode(lookTarget)
        let look = SCNLookAtConstraint(target: lookTarget)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)

        // Lights.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.light?.castsShadow = true
        sun.light?.shadowRadius = 6
        sun.light?.shadowColor = UIColor(white: 0, alpha: 0.45)
        sun.eulerAngles = SCNVector3(-Float.pi / 2.6, 0.5, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor(red: 0.65, green: 0.6, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Three fairway islands separated by void gaps (fall = respawn).
        let grass = UIColor(red: 0.23, green: 0.72, blue: 0.35, alpha: 1)
        let grassDark = UIColor(red: 0.16, green: 0.5, blue: 0.27, alpha: 1)
        addIsland(width: 14, length: 10, centerZ: 12, top: grass, side: grassDark)   // tee island
        addIsland(width: 14, length: 10, centerZ: 0, top: grass, side: grassDark)    // middle island
        addIsland(width: 14, length: 10, centerZ: -12, top: grass, side: grassDark)  // green island

        // Side rails on the tee island only — everywhere else you can fall off.
        for x: Float in [-7.2, 7.2] {
            let rail = SCNNode(geometry: SCNBox(width: 0.4, height: 1.0, length: 10, chamferRadius: 0.08))
            rail.geometry?.materials = [material(UIColor(Theme.purple), emissive: UIColor(Theme.purple).withAlphaComponent(0.6))]
            rail.position = SCNVector3(x, 0.5, 12)
            rail.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            rail.physicsBody?.restitution = 0.7
            scene.rootNode.addChildNode(rail)
        }

        // Bumpers on the middle island.
        for x: Float in [-3.6, 3.6] {
            let bumper = SCNNode(geometry: SCNCylinder(radius: 1.15, height: 1.6))
            bumper.geometry?.materials = [material(
                UIColor(red: 0.14, green: 0.14, blue: 0.3, alpha: 1),
                emissive: UIColor(Theme.orange).withAlphaComponent(0.85)
            )]
            bumper.position = SCNVector3(x, 0.8, 0)
            bumper.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            bumper.physicsBody?.restitution = 1.15
            scene.rootNode.addChildNode(bumper)
        }

        // Spinning paddle guarding the green.
        let paddle = SCNNode(geometry: SCNBox(width: 6.5, height: 0.9, length: 0.45, chamferRadius: 0.1))
        paddle.geometry?.materials = [material(UIColor(Theme.pink), emissive: UIColor(Theme.pink).withAlphaComponent(0.7))]
        paddle.position = SCNVector3(0, 0.45, -8.6)
        paddle.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        paddle.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.9)))
        scene.rootNode.addChildNode(paddle)

        buildHole()
    }

    private func addIsland(width: CGFloat, length: CGFloat, centerZ: Float, top: UIColor, side: UIColor) {
        let box = SCNBox(width: width, height: 2.4, length: length, chamferRadius: 0.12)
        let topM = material(top)
        let sideM = material(side)
        // SCNBox materials order: +z, +x, -z, -x, +y (top), -y (bottom)
        box.materials = [sideM, sideM, sideM, sideM, topM, sideM]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, -1.2, centerZ)
        node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        node.physicsBody?.friction = 0.55
        node.physicsBody?.restitution = 0.25
        scene.rootNode.addChildNode(node)
    }

    private func buildHole() {
        // Dark cup inset into the green.
        let cup = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.06))
        cup.geometry?.materials = [material(UIColor(white: 0.02, alpha: 1))]
        cup.position = SCNVector3(holeCenter.x, 0.04, holeCenter.z)
        scene.rootNode.addChildNode(cup)

        // Pulsing neon ring so the target reads from the couch.
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.85, pipeRadius: 0.07))
        ring.geometry?.materials = [material(UIColor(Theme.yellow), emissive: UIColor(Theme.yellow))]
        ring.position = SCNVector3(holeCenter.x, 0.1, holeCenter.z)
        ring.runAction(.repeatForever(.sequence([
            .scale(to: 1.22, duration: 0.7),
            .scale(to: 0.95, duration: 0.7),
        ])))
        scene.rootNode.addChildNode(ring)

        // Flag: pole + red pennant.
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 2.6))
        pole.geometry?.materials = [material(.white, emissive: UIColor(white: 0.8, alpha: 1))]
        pole.position = SCNVector3(holeCenter.x, 1.3, holeCenter.z)
        scene.rootNode.addChildNode(pole)

        let pennant = SCNNode(geometry: SCNPyramid(width: 0.1, height: 1.0, length: 0.55))
        pennant.geometry?.materials = [material(UIColor(Theme.red), emissive: UIColor(Theme.red).withAlphaComponent(0.8))]
        pennant.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        pennant.position = SCNVector3(holeCenter.x + 0.5, 2.3, holeCenter.z)
        scene.rootNode.addChildNode(pennant)
    }

    // MARK: balls

    /// Renders the player's emoji on a colored disc — used as the ball texture.
    private func ballTexture(avatar: String, colorHex: String) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(Color(hex: colorHex)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.systemFont(ofSize: 150)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let text = NSAttributedString(string: avatar, attributes: attrs)
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                  y: (size.height - textSize.height) / 2))
        }
    }

    private func spawnBalls() {
        let count = players.count
        for (index, info) in players.enumerated() {
            let tee = SCNVector3(Float(index) * 1.1 - Float(count - 1) * 0.55, 0.8, 15)

            let sphere = SCNSphere(radius: 0.42)
            let m = SCNMaterial()
            m.diffuse.contents = ballTexture(avatar: info.avatar, colorHex: info.colorHex)
            m.lightingModel = .blinn
            sphere.materials = [m]
            let node = SCNNode(geometry: sphere)
            node.position = tee

            let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: sphere))
            body.mass = 1
            body.restitution = 0.55
            body.friction = 0.5
            body.rollingFriction = 0.18
            body.damping = 0.16
            body.angularDamping = 0.4
            node.physicsBody = body
            scene.rootNode.addChildNode(node)

            // Floating name tag (kept upright separately from the rolling ball).
            // Heights alternate so tags don't overlap while balls sit on the tee.
            let tagHeight: Float = index % 2 == 0 ? 0.95 : 1.65
            let text = SCNText(string: info.name, extrusionDepth: 0.06)
            text.font = UIFont.systemFont(ofSize: 0.42, weight: .heavy)
            text.flatness = 0.25
            text.materials = [material(.white, emissive: UIColor(white: 0.9, alpha: 1))]
            let tag = SCNNode(geometry: text)
            let (minB, maxB) = tag.boundingBox
            tag.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, minB.y, 0)
            tag.constraints = [SCNBillboardConstraint()]
            tag.position = SCNVector3(tee.x, tee.y + tagHeight, tee.z)
            scene.rootNode.addChildNode(tag)

            if info.anviled {
                let anvilText = SCNText(string: "🪨", extrusionDepth: 0.05)
                anvilText.font = UIFont.systemFont(ofSize: 0.5)
                let anvil = SCNNode(geometry: anvilText)
                anvil.constraints = [SCNBillboardConstraint()]
                anvil.position = SCNVector3(0.4, 0.7, 0)
                tag.addChildNode(anvil)
            }

            balls[info.id] = Ball(info: info, node: node, tag: tag, tee: tee, tagHeight: tagHeight)
        }
    }

    // MARK: relayed input

    /// Phone drag angle -> ground plane: drag up means "toward the hole" (-z).
    private func groundDirection(_ angle: Double) -> SCNVector3 {
        SCNVector3(Float(cos(angle)), 0, Float(-sin(angle)))
    }

    func setAim(playerId: String, angle: Double, power: Double) {
        guard let ball = balls[playerId], !ball.sunk else { return }
        clearAim(playerId: playerId)

        let dir = groundDirection(angle)
        let length = CGFloat(1.6 + 5.2 * power)
        let arrowBody = SCNNode(geometry: SCNCylinder(radius: 0.1, height: length))
        let color = UIColor(Color(hex: ball.info.colorHex))
        arrowBody.geometry?.materials = [material(color, emissive: color)]
        arrowBody.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // lie along +z
        arrowBody.position = SCNVector3(0, 0, Float(length) / 2)

        let tip = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.26, height: 0.55))
        tip.geometry?.materials = [material(color, emissive: color)]
        tip.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        tip.position = SCNVector3(0, 0, Float(length) + 0.25)

        let holder = SCNNode()
        holder.addChildNode(arrowBody)
        holder.addChildNode(tip)
        holder.position = SCNVector3(ball.node.position.x, 0.25, ball.node.position.z)
        holder.eulerAngles = SCNVector3(0, atan2(dir.x, dir.z), 0)
        scene.rootNode.addChildNode(holder)
        aimNodes[playerId] = holder
    }

    func clearAim(playerId: String) {
        aimNodes[playerId]?.removeFromParentNode()
        aimNodes[playerId] = nil
    }

    func fire(playerId: String, angle: Double, power: Double) {
        clearAim(playerId: playerId)
        guard var ball = balls[playerId], !ball.sunk, !ball.respawning else { return }
        let now = CACurrentMediaTime()
        guard now - ball.lastFire > 0.45 else { return }
        ball.lastFire = now
        balls[playerId] = ball

        let p = min(1.0, max(0.0, power))
        let factor: Float = ball.info.anviled ? 0.7 : 1.0 // the Heavy Anvil at work
        let dir = groundDirection(angle)
        let horizontal = Float(5.0 + 14.0 * p) * factor
        let loft = Float(2.2 + 4.8 * p) * factor
        ball.node.physicsBody?.applyForce(
            SCNVector3(dir.x * horizontal, loft, dir.z * horizontal),
            asImpulse: true
        )
    }

    // MARK: frame loop (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard !done else { return }

        for (id, var ball) in balls where !ball.sunk {
            let p = ball.node.presentation.position
            let v = ball.node.physicsBody?.velocity ?? SCNVector3Zero
            let speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

            // Keep the name tag floating above the rolling ball.
            ball.tag.position = SCNVector3(p.x, p.y + ball.tagHeight, p.z)

            // Sink: near the cup, on the green, slow enough.
            let horizontalDist = sqrt(pow(p.x - holeCenter.x, 2) + pow(p.z - holeCenter.z, 2))
            if horizontalDist < 0.7, p.y < 1.4, speed < 5.5 {
                ball.sunk = true
                balls[id] = ball
                finishOrder.append(id)
                celebrate()
                ball.node.physicsBody = nil
                ball.tag.removeFromParentNode()
                ball.node.runAction(.sequence([
                    .group([
                        .move(to: SCNVector3(holeCenter.x, 0.1, holeCenter.z), duration: 0.18),
                        .scale(to: 0.08, duration: 0.3),
                    ]),
                    .fadeOut(duration: 0.12),
                ]))
                DispatchQueue.main.async { [onSank] in onSank(id) }
                continue
            }

            // Fell into the void -> respawn at the tee.
            if p.y < -9, !ball.respawning {
                ball.respawning = true
                balls[id] = ball
                ball.node.runAction(.sequence([
                    .fadeOpacity(to: 0, duration: 0.1),
                    .wait(duration: 0.8),
                    .run { [weak self] node in
                        guard let self, var b = self.balls[id] else { return }
                        node.physicsBody?.clearAllForces()
                        node.physicsBody?.velocity = SCNVector3Zero
                        node.physicsBody?.angularVelocity = SCNVector4Zero
                        node.position = b.tee
                        node.physicsBody?.resetTransform()
                        b.respawning = false
                        self.balls[id] = b
                    },
                    .fadeOpacity(to: 1, duration: 0.2),
                ]))
            }
        }

        if finishOrder.count == balls.count || Date() >= endsAt {
            finishGame()
        }
    }

    private func celebrate() {
        let sparks = SCNParticleSystem()
        sparks.birthRate = 350
        sparks.emissionDuration = 0.35
        sparks.particleLifeSpan = 0.9
        sparks.particleVelocity = 6
        sparks.particleVelocityVariation = 3
        sparks.spreadingAngle = 70
        sparks.particleSize = 0.12
        sparks.particleColor = UIColor(Theme.yellow)
        sparks.emitterShape = SCNSphere(radius: 0.3)
        let emitter = SCNNode()
        emitter.position = SCNVector3(holeCenter.x, 0.6, holeCenter.z)
        emitter.addParticleSystem(sparks)
        scene.rootNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 1.6), .removeFromParentNode()]))
    }

    private func finishGame() {
        guard !done else { return }
        done = true
        let order = finishOrder
        DispatchQueue.main.async { [onFinished] in
            onFinished(order)
        }
    }
}
