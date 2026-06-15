import SwiftUI
import SceneKit

/// Bumper Sumo on the TV: a circular floating stone slab over water. Each player
/// is a heavy bumper sphere; the host board applies continuous force from the
/// streamed joystick vectors and reports anyone shoved into the water. The phone
/// controllers stay 2-D — all the 3D lives here.
struct BoardBumperView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @State private var controller: BumperSceneController?

    private var bumper: BumperState? { client.room?.bumper }

    var body: some View {
        ZStack {
            if let controller {
                SceneView(
                    scene: controller.scene,
                    pointOfView: controller.cameraNode,
                    options: [],
                    preferredFramesPerSecond: GolfSceneController.targetFPS, // shared thermal cap
                    antialiasingMode: .multisampling2X,
                    delegate: controller
                )
                .ignoresSafeArea()
            }
            hud
        }
        .onAppear {
            build()
            controller?.scene.isPaused = false
        }
        .onDisappear {
            client.onJoystick = nil
            controller?.scene.isPaused = true
        }
    }

    private func build() {
        guard controller == nil, let room = client.room else { return }
        let infos = room.players.map {
            GolfPlayerInfo(id: $0.id, name: $0.name, avatar: $0.avatar, colorHex: $0.color, modifier: $0.modifier)
        }
        let c = BumperSceneController(players: infos) { playerId, byPlayerId in
            client.reportBumperKnockout(playerId: playerId, byPlayerId: byPlayerId)
        }
        client.onJoystick = { [weak c] id, x, y in c?.setJoystick(playerId: id, x: x, y: y) }
        controller = c
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                Text(loc.tr("🤼 BUMPER ARENA"))
                    .font(Theme.title(34))
                    .foregroundStyle(.white)
                    .neonGlow(Theme.orange, radius: 12)
                Spacer()
                if let bumper, bumper.winnerId == nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        CountdownLabel(endsAt: bumper.endsAtDate, font: Theme.title(46), color: Theme.orange)
                        Text(loc.tr("%@ still on the slab", "\(bumper.alive.count)"))
                            .font(Theme.body(16))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 22)

            Spacer()

            if let bumper, let winner = client.room?.player(bumper.winnerId) {
                Text(loc.tr("%@ %@ WINS!", winner.avatar, winner.name))
                    .font(Theme.title(48))
                    .foregroundStyle(Theme.yellow)
                    .neonGlow(Theme.yellow)
                    .padding(.bottom, 60)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: bumper?.winnerId)
    }
}

/// Drives the bumper arena scene: spawns the slab + bumpers, applies joystick
/// force every frame, and detects knockouts (a bumper falling into the water).
final class BumperSceneController: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private static let slabRadius: Float = 9.0
    private static let fallY: Float = -3.0          // below this a bumper has splashed
    private static let bumperCategory = 1 << 5      // (mirrors golf's ball bit, separate scene)

    private let players: [GolfPlayerInfo]
    private let onKnockout: (String, String?) -> Void
    private let playerIds: Set<String>

    // Render-thread state.
    private var bumpers: [String: SCNNode] = [:]
    private var joystick: [String: SCNVector3] = [:]
    private var lastHitBy: [String: String] = [:]
    private var eliminated: Set<String> = []
    /// Auction modifier per player: nitro shoves harder, flat tire shoves weaker.
    private var forceScale: [String: Float] = [:]

    private let pendingLock = NSLock()
    private var pending: [(BumperSceneController) -> Void] = []

    init(players: [GolfPlayerInfo], onKnockout: @escaping (String, String?) -> Void) {
        self.players = players
        self.onKnockout = onKnockout
        self.playerIds = Set(players.map(\.id))
        super.init()
        buildWorld()
        spawnBumpers()
    }

    // MARK: thread-safe input

    private func enqueue(_ block: @escaping (BumperSceneController) -> Void) {
        pendingLock.lock(); pending.append(block); pendingLock.unlock()
    }

    /// Joystick vector from a phone (screen space): x = right, y = down.
    func setJoystick(playerId: String, x: Double, y: Double) {
        // Map to the floor plane: screen-down (+y) → toward the camera (+Z),
        // screen-up (−y) → away (−Z); x → world X.
        enqueue { s in s.joystick[playerId] = SCNVector3(Float(x), 0, Float(y)) }
    }

    // MARK: world

    private func buildWorld() {
        scene.background.contents = UIColor(red: 0.04, green: 0.10, blue: 0.22, alpha: 1)
        scene.physicsWorld.gravity = SCNVector3(0, -16, 0) // a touch heavy so falls read fast
        scene.physicsWorld.contactDelegate = self

        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zFar = 200
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 18, 18)
        let look = SCNLookAtConstraint(target: nodeAtOrigin())
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)

        // Warm key light + cool ambient (no shadows — thermal baseline).
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.castsShadow = false
        sun.eulerAngles = SCNVector3(-Float.pi / 3, 0.5, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 360
        ambient.light?.color = UIColor(red: 0.5, green: 0.6, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Water plane below the slab.
        let water = SCNFloor()
        water.reflectivity = 0.08
        let waterMat = SCNMaterial()
        waterMat.lightingModel = .physicallyBased
        waterMat.diffuse.contents = UIColor(red: 0.08, green: 0.32, blue: 0.55, alpha: 1)
        waterMat.roughness.contents = 0.2
        water.materials = [waterMat]
        let waterNode = SCNNode(geometry: water)
        waterNode.position = SCNVector3(0, -5, 0)
        scene.rootNode.addChildNode(waterNode)

        // The floating circular stone slab, centred at origin (top at y = 0).
        let slab = SCNCylinder(radius: CGFloat(Self.slabRadius), height: 2.4)
        let stone = SCNMaterial()
        stone.lightingModel = .physicallyBased
        stone.diffuse.contents = UIColor(red: 0.46, green: 0.45, blue: 0.5, alpha: 1)
        stone.roughness.contents = 0.85
        slab.materials = [stone]
        let slabNode = SCNNode(geometry: slab)
        slabNode.position = SCNVector3(0, -1.2, 0)
        let slabBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: slab, options: nil))
        slabBody.friction = 0.6
        slabBody.collisionBitMask = -1
        slabNode.physicsBody = slabBody
        scene.rootNode.addChildNode(slabNode)
    }

    private func nodeAtOrigin() -> SCNNode {
        let n = SCNNode()
        n.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(n)
        return n
    }

    private func spawnBumpers() {
        let count = max(1, players.count)
        let ring: Float = 4.6
        for (i, info) in players.enumerated() {
            let angle = Float(i) / Float(count) * 2 * .pi
            let pos = SCNVector3(cosf(angle) * ring, 1.2, sinf(angle) * ring)

            let sphere = SCNSphere(radius: 0.95)
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.diffuse.contents = UIColor(Color(hex: info.colorHex))
            mat.roughness.contents = 0.35
            mat.metalness.contents = 0.1
            sphere.materials = [mat]

            let node = SCNNode(geometry: sphere)
            node.name = info.id
            node.position = pos

            // Auction modifiers: Nitro = +40% mass & shove force; Flat Tire = half force.
            let isNitro = info.modifier == "nitro"
            let isFlat = info.modifier == "flat_tire"
            forceScale[info.id] = isNitro ? 1.4 : isFlat ? 0.5 : 1.0

            let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: sphere, options: nil))
            body.mass = isNitro ? 5.6 : 4    // heavier = more impact when it connects
            body.restitution = 0.75          // bouncy bumpers
            body.friction = 0.4
            body.damping = 0.7               // so they coast to a stop when released
            body.angularDamping = 0.6
            body.categoryBitMask = Self.bumperCategory
            body.collisionBitMask = -1        // collide with slab + each other
            body.contactTestBitMask = Self.bumperCategory // report bumper↔bumper (for "who shoved whom")
            node.physicsBody = body
            scene.rootNode.addChildNode(node)
            bumpers[info.id] = node

            // Floating emoji label that always faces the camera.
            let plane = SCNPlane(width: 1.1, height: 1.1)
            let label = SCNMaterial()
            label.diffuse.contents = emojiImage(info.avatar)
            label.isDoubleSided = true
            label.lightingModel = .constant
            plane.materials = [label]
            let labelNode = SCNNode(geometry: plane)
            labelNode.position = SCNVector3(0, 1.5, 0)
            labelNode.constraints = [SCNBillboardConstraint()]
            node.addChildNode(labelNode)
        }
    }

    private func emojiImage(_ emoji: String, size: CGFloat = 128) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let font = UIFont.systemFont(ofSize: size * 0.72)
            let s = NSAttributedString(string: emoji, attributes: [.font: font])
            let sz = s.size()
            s.draw(at: CGPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2))
        }
    }

    // MARK: render loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        pendingLock.lock()
        let commands = pending; pending.removeAll()
        pendingLock.unlock()
        for command in commands { command(self) }

        let force: Float = 34
        for (id, node) in bumpers where !eliminated.contains(id) {
            // Continuous thrust from the latest joystick vector, scaled by any
            // active modifier (nitro ×1.4 / flat tire ×0.5).
            if let dir = joystick[id], (dir.x != 0 || dir.z != 0) {
                let f = force * (forceScale[id] ?? 1.0)
                node.physicsBody?.applyForce(SCNVector3(dir.x * f, 0, dir.z * f), asImpulse: false)
            }
            // Knockout: shoved off the slab and falling into the water.
            let p = node.presentation.position
            if p.y < Self.fallY {
                knockOut(id: id, node: node)
            }
        }
    }

    private func knockOut(id: String, node: SCNNode) {
        guard !eliminated.contains(id) else { return }
        eliminated.insert(id)
        bumpers.removeValue(forKey: id)
        let by = lastHitBy[id]
        splash(at: node.presentation.position)
        node.physicsBody = nil
        node.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
        DispatchQueue.main.async { [onKnockout] in onKnockout(id, by) }
    }

    private func splash(at point: SCNVector3) {
        let sprayed = SCNParticleSystem()
        sprayed.birthRate = 380
        sprayed.emissionDuration = 0.08
        sprayed.particleLifeSpan = 0.6
        sprayed.particleVelocity = 7
        sprayed.particleVelocityVariation = 3
        sprayed.spreadingAngle = 80
        sprayed.particleSize = 0.16
        sprayed.particleColor = UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1)
        sprayed.blendMode = .additive
        sprayed.emitterShape = SCNSphere(radius: 0.3)
        let emitter = SCNNode()
        emitter.position = SCNVector3(point.x, -1.5, point.z)
        emitter.addParticleSystem(sprayed)
        scene.rootNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 1.2), .removeFromParentNode()]))
    }

    // MARK: contacts (physics thread → enqueue mutations)

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        guard let a = contact.nodeA.name, playerIds.contains(a),
              let b = contact.nodeB.name, playerIds.contains(b) else { return }
        // Record the most recent shover for each, so a later knockout can credit
        // "The Aggressor". Mutated on the render thread via enqueue.
        enqueue { s in
            s.lastHitBy[a] = b
            s.lastHitBy[b] = a
        }
    }
}
