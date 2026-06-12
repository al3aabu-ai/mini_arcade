import SwiftUI
import SceneKit

struct GolfPlayerInfo {
    let id: String
    let name: String
    let avatar: String
    let colorHex: String
    let anviled: Bool
}

/// Guerilla Golf on the TV — a juicy low-poly 3D island course.
/// Procedural textures (no asset files), PBR materials, HDR bloom, SSAO and
/// particle trails do the heavy lifting. The host device runs the physics
/// and reports the finish order; phones send the same `aim`/`fire` messages.
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

// MARK: - Procedural textures (drawn once, no asset files)

private enum Tex {
    /// Golf fairway: alternating mowing stripes + speckle so light has detail to catch.
    static func fairway() -> UIImage {
        draw(512) { ctx, size in
            let a = UIColor(red: 0.30, green: 0.80, blue: 0.42, alpha: 1)
            let b = UIColor(red: 0.24, green: 0.70, blue: 0.36, alpha: 1)
            let band = size.width / 8
            for i in 0..<8 {
                (i % 2 == 0 ? a : b).setFill()
                ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: size.height))
            }
            speckle(ctx, size, count: 1400, light: 0.05, dark: 0.07)
        }
    }

    /// Island cliffs: layered earth strata.
    static func cliff() -> UIImage {
        draw(512) { ctx, size in
            let strata: [UIColor] = [
                UIColor(red: 0.46, green: 0.31, blue: 0.20, alpha: 1),
                UIColor(red: 0.38, green: 0.25, blue: 0.16, alpha: 1),
                UIColor(red: 0.52, green: 0.36, blue: 0.24, alpha: 1),
                UIColor(red: 0.31, green: 0.20, blue: 0.13, alpha: 1),
            ]
            var y: CGFloat = 0
            var i = 0
            while y < size.height {
                let h = CGFloat.random(in: 36...86)
                strata[i % strata.count].setFill()
                ctx.fill(CGRect(x: 0, y: y, width: size.width, height: h))
                y += h
                i += 1
            }
            speckle(ctx, size, count: 1000, light: 0.04, dark: 0.10)
        }
    }

    /// Sand bunker grain.
    static func sand() -> UIImage {
        draw(256) { ctx, size in
            UIColor(red: 0.93, green: 0.83, blue: 0.58, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            speckle(ctx, size, count: 1200, light: 0.10, dark: 0.08)
        }
    }

    /// Candy stripes for the paddle and bumpers.
    static func candy(_ colorA: UIColor, _ colorB: UIColor) -> UIImage {
        draw(256) { ctx, size in
            colorA.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            colorB.setFill()
            let band = size.width / 6
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: .pi / 5)
            ctx.cgContext.translateBy(x: -size.width, y: -size.height)
            for i in stride(from: 0, to: 24, by: 2) {
                ctx.fill(CGRect(x: CGFloat(i) * band, y: -size.height, width: band, height: size.height * 4))
            }
            ctx.cgContext.restoreGState()
        }
    }

    /// Night-party sky: deep purple gradient + stars + warm horizon glow.
    /// Used both as the visible background and the PBR lighting environment.
    static func sky() -> UIImage {
        draw(1024, height: 512) { ctx, size in
            let colors = [
                UIColor(red: 0.04, green: 0.04, blue: 0.13, alpha: 1).cgColor,
                UIColor(red: 0.13, green: 0.06, blue: 0.32, alpha: 1).cgColor,
                UIColor(red: 0.38, green: 0.10, blue: 0.45, alpha: 1).cgColor,
                UIColor(red: 0.72, green: 0.18, blue: 0.50, alpha: 1).cgColor,
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 0.45, 0.78, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
            // Stars, denser near the top.
            for _ in 0..<240 {
                let y = CGFloat.random(in: 0...(size.height * 0.7))
                let x = CGFloat.random(in: 0...size.width)
                let r = CGFloat.random(in: 0.6...2.2)
                UIColor(white: 1, alpha: CGFloat.random(in: 0.25...0.95)).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
    }

    private static func speckle(_ ctx: UIGraphicsImageRendererContext, _ size: CGSize,
                                count: Int, light: CGFloat, dark: CGFloat) {
        for i in 0..<count {
            let isLight = i % 2 == 0
            UIColor(white: isLight ? 1 : 0, alpha: isLight ? light : dark).setFill()
            let r = CGFloat.random(in: 1.5...4)
            ctx.fill(CGRect(x: .random(in: 0...size.width), y: .random(in: 0...size.height),
                            width: r, height: r))
        }
    }

    private static func draw(_ width: CGFloat, height: CGFloat? = nil,
                             _ body: (UIGraphicsImageRendererContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: width, height: height ?? width)
        return UIGraphicsImageRenderer(size: size).image { ctx in body(ctx, size) }
    }
}

// MARK: - SceneKit world

final class GolfSceneController: NSObject, SCNSceneRendererDelegate {
    private struct Ball {
        let info: GolfPlayerInfo
        let node: SCNNode
        let tag: SCNNode
        let trail: SCNParticleSystem
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

    // MARK: materials

    private func pbr(_ contents: Any, roughness: CGFloat = 0.85,
                     metalness: CGFloat = 0.0, emissive: UIColor? = nil,
                     tile: (Float, Float)? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        if let emissive { m.emission.contents = emissive }
        if let tile {
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(tile.0, tile.1, 1)
        }
        return m
    }

    // MARK: world building

    private func buildWorld() {
        let skyImage = Tex.sky()
        scene.background.contents = skyImage
        scene.lightingEnvironment.contents = skyImage
        scene.lightingEnvironment.intensity = 1.3
        scene.fogColor = UIColor(red: 0.16, green: 0.07, blue: 0.30, alpha: 1)
        scene.fogStartDistance = 48
        scene.fogEndDistance = 110
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)

        // Camera with the juice turned on: HDR bloom, SSAO, gentle vignette.
        // The simulator compiles SceneKit shaders on the CPU (10s+ of blank
        // screen per variant), so the post-processing stack — which adds
        // several more shader variants — only ships on real hardware.
        let camera = SCNCamera()
        camera.fieldOfView = 52
        camera.zFar = 220
        #if !targetEnvironment(simulator)
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.85
        camera.bloomThreshold = 0.55
        camera.bloomBlurRadius = 14
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 1.4
        camera.vignettingPower = 0.7
        camera.vignettingIntensity = 0.55
        #endif
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 19, 29)
        let lookTarget = SCNNode()
        lookTarget.position = SCNVector3(0, 0, -4)
        scene.rootNode.addChildNode(lookTarget)
        let look = SCNLookAtConstraint(target: lookTarget)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)

        // Warm key light + cool purple fill = depth on every face.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1050
        sun.light?.color = UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowRadius = 9
        sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light?.shadowColor = UIColor(red: 0.05, green: 0.0, blue: 0.15, alpha: 0.55)
        sun.eulerAngles = SCNVector3(-Float.pi / 2.7, 0.55, 0)
        scene.rootNode.addChildNode(sun)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 260
        fill.light?.color = UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(fill)

        // Three fairway islands separated by void gaps (fall = respawn).
        addIsland(centerZ: 12)   // tee
        addIsland(centerZ: 0)    // middle
        addIsland(centerZ: -12)  // green

        // Neon edge trim along the long sides — pops hard with bloom.
        for z: Float in [12, 0, -12] {
            for (x, color) in [(Float(-6.9), Theme.cyan), (Float(6.9), Theme.pink)] {
                let trim = SCNNode(geometry: SCNBox(width: 0.18, height: 0.14, length: 9.9, chamferRadius: 0.05))
                trim.geometry?.materials = [pbr(UIColor(color), roughness: 0.3, emissive: UIColor(color))]
                trim.position = SCNVector3(x, 0.07, z)
                scene.rootNode.addChildNode(trim)
            }
        }

        // Side rails on the tee island only — everywhere else you can fall off.
        for x: Float in [-7.25, 7.25] {
            let rail = SCNNode(geometry: SCNBox(width: 0.4, height: 1.0, length: 10, chamferRadius: 0.1))
            rail.geometry?.materials = [pbr(UIColor(Theme.purple), roughness: 0.35,
                                            emissive: UIColor(Theme.purple).withAlphaComponent(0.65))]
            rail.position = SCNVector3(x, 0.5, 12)
            rail.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            rail.physicsBody?.restitution = 0.7
            scene.rootNode.addChildNode(rail)
        }

        // Candy-striped bumpers on the middle island.
        let bumperTex = Tex.candy(
            UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1),
            UIColor(Theme.orange)
        )
        for x: Float in [-3.6, 3.6] {
            let bumper = SCNNode(geometry: SCNCylinder(radius: 1.15, height: 1.6))
            bumper.geometry?.materials = [pbr(bumperTex, roughness: 0.4)]
            bumper.position = SCNVector3(x, 0.8, 0)
            bumper.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            bumper.physicsBody?.restitution = 1.15
            scene.rootNode.addChildNode(bumper)

            let halo = SCNNode(geometry: SCNTorus(ringRadius: 1.18, pipeRadius: 0.07))
            halo.geometry?.materials = [pbr(UIColor(Theme.orange), roughness: 0.3,
                                            emissive: UIColor(Theme.orange))]
            halo.position = SCNVector3(x, 1.62, 0)
            scene.rootNode.addChildNode(halo)
        }

        // Spinning candy paddle guarding the green.
        let paddle = SCNNode(geometry: SCNBox(width: 6.5, height: 0.9, length: 0.45, chamferRadius: 0.12))
        paddle.geometry?.materials = [pbr(Tex.candy(.white, UIColor(Theme.pink)), roughness: 0.35)]
        paddle.position = SCNVector3(0, 0.45, -8.6)
        paddle.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        paddle.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.9)))
        scene.rootNode.addChildNode(paddle)

        // Sand bunker near the hole (visual hazard flavor).
        let bunker = SCNNode(geometry: SCNCylinder(radius: 2.0, height: 0.06))
        bunker.geometry?.materials = [pbr(Tex.sand(), roughness: 0.95, tile: (2, 2))]
        bunker.position = SCNVector3(-2.6, 0.03, -11.2)
        scene.rootNode.addChildNode(bunker)

        buildHole()
        buildScenery()
    }

    private func addIsland(centerZ: Float) {
        let box = SCNBox(width: 14, height: 2.6, length: 10, chamferRadius: 0.15)
        let top = pbr(Tex.fairway(), roughness: 0.9, tile: (2, 1.4))
        let side = pbr(Tex.cliff(), roughness: 0.95, tile: (3, 1))
        let bottom = pbr(UIColor(red: 0.20, green: 0.12, blue: 0.09, alpha: 1))
        // SCNBox materials order: +z, +x, -z, -x, +y (top), -y (bottom)
        box.materials = [side, side, side, side, top, bottom]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, -1.3, centerZ)
        node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        node.physicsBody?.friction = 0.55
        node.physicsBody?.restitution = 0.25
        scene.rootNode.addChildNode(node)
    }

    private func buildHole() {
        // Dark cup inset into the green.
        let cup = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.08))
        cup.geometry?.materials = [pbr(UIColor(white: 0.02, alpha: 1), roughness: 1)]
        cup.position = SCNVector3(holeCenter.x, 0.05, holeCenter.z)
        scene.rootNode.addChildNode(cup)

        // Pulsing neon ring so the target reads from the couch.
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.85, pipeRadius: 0.08))
        ring.geometry?.materials = [pbr(UIColor(Theme.yellow), roughness: 0.3,
                                        emissive: UIColor(Theme.yellow))]
        ring.position = SCNVector3(holeCenter.x, 0.1, holeCenter.z)
        ring.runAction(.repeatForever(.sequence([
            .scale(to: 1.22, duration: 0.7),
            .scale(to: 0.95, duration: 0.7),
        ])))
        scene.rootNode.addChildNode(ring)

        // Beacon: a soft additive light column rising from the cup.
        let beamGeo = SCNCylinder(radius: 0.5, height: 8)
        let beamMat = SCNMaterial()
        beamMat.lightingModel = .constant
        beamMat.diffuse.contents = UIColor.clear
        beamMat.emission.contents = UIColor(Theme.yellow)
        beamMat.transparency = 0.22
        beamMat.blendMode = .add
        beamMat.writesToDepthBuffer = false
        beamMat.isDoubleSided = true
        beamGeo.materials = [beamMat]
        let beam = SCNNode(geometry: beamGeo)
        beam.position = SCNVector3(holeCenter.x, 4, holeCenter.z)
        beam.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 0.55, duration: 1.1),
            .fadeOpacity(to: 1.0, duration: 1.1),
        ])))
        scene.rootNode.addChildNode(beam)

        // Flag: pole + red pennant.
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 2.6))
        pole.geometry?.materials = [pbr(UIColor.white, roughness: 0.4,
                                        emissive: UIColor(white: 0.7, alpha: 1))]
        pole.position = SCNVector3(holeCenter.x, 1.3, holeCenter.z)
        scene.rootNode.addChildNode(pole)

        let pennant = SCNNode(geometry: SCNPyramid(width: 0.1, height: 1.0, length: 0.55))
        pennant.geometry?.materials = [pbr(UIColor(Theme.red), roughness: 0.5,
                                           emissive: UIColor(Theme.red).withAlphaComponent(0.7))]
        pennant.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        pennant.position = SCNVector3(holeCenter.x + 0.5, 2.3, holeCenter.z)
        scene.rootNode.addChildNode(pennant)
    }

    /// Set dressing: party palms, floating rocks, drifting clouds.
    private func buildScenery() {
        let palmSpots: [(Float, Float)] = [(-6.1, 8.2), (6.1, 15.6), (-6.1, -15.5), (5.9, -9.0)]
        for (i, spot) in palmSpots.enumerated() {
            addPalm(at: SCNVector3(spot.0, 0, spot.1), tint: i % 2 == 0 ? Theme.cyan : Theme.pink)
        }

        // Low-poly rocks floating in the void around the course.
        for _ in 0..<7 {
            let r = CGFloat.random(in: 0.5...1.3)
            let rock = SCNSphere(radius: r)
            rock.segmentCount = 5 // faceted = low-poly look
            let node = SCNNode(geometry: rock)
            node.geometry?.materials = [pbr(UIColor(red: 0.36, green: 0.30, blue: 0.52, alpha: 1), roughness: 0.9)]
            node.position = SCNVector3(
                Float.random(in: -16 ... 16),
                Float.random(in: -7 ... -3),
                Float.random(in: -22 ... 16)
            )
            node.eulerAngles = SCNVector3(Float.random(in: 0...3), Float.random(in: 0...3), 0)
            let bob = SCNAction.sequence([
                .moveBy(x: 0, y: CGFloat.random(in: 0.3...0.8), z: 0, duration: Double.random(in: 2.5...4.5)),
                .moveBy(x: 0, y: CGFloat.random(in: -0.8 ... -0.3), z: 0, duration: Double.random(in: 2.5...4.5)),
            ])
            node.runAction(.repeatForever(bob))
            node.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.random(in: 1...3), z: 0, duration: 12)))
            scene.rootNode.addChildNode(node)
        }

        // Puffy clouds drifting far behind the green.
        for i in 0..<3 {
            let cloud = SCNNode()
            for j in 0..<3 {
                let puffGeo = SCNSphere(radius: CGFloat.random(in: 1.1...1.9))
                puffGeo.segmentCount = 8
                let puff = SCNNode(geometry: puffGeo)
                puff.geometry?.materials = [pbr(UIColor(red: 0.92, green: 0.88, blue: 1.0, alpha: 1), roughness: 1)]
                puff.position = SCNVector3(Float(j) * 1.7 - 1.7, Float.random(in: -0.3...0.3), 0)
                cloud.addChildNode(puff)
            }
            cloud.position = SCNVector3(Float(i) * 14 - 14, Float.random(in: 7...11), -30)
            cloud.opacity = 0.9
            let drift = SCNAction.sequence([
                .moveBy(x: 5, y: 0, z: 0, duration: Double.random(in: 16...26)),
                .moveBy(x: -5, y: 0, z: 0, duration: Double.random(in: 16...26)),
            ])
            cloud.runAction(.repeatForever(drift))
            scene.rootNode.addChildNode(cloud)
        }
    }

    private func addPalm(at position: SCNVector3, tint: Color) {
        let palm = SCNNode()
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.16, height: 2.4))
        trunk.geometry?.materials = [pbr(Tex.cliff(), roughness: 0.95, tile: (1, 2))]
        trunk.position = SCNVector3(0, 1.2, 0)
        trunk.eulerAngles = SCNVector3(0, 0, 0.12)
        trunk.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        palm.addChildNode(trunk)

        // Stylized canopy: three stacked faceted cones in party colors.
        let greens = [
            UIColor(red: 0.16, green: 0.62, blue: 0.34, alpha: 1),
            UIColor(red: 0.20, green: 0.72, blue: 0.40, alpha: 1),
            UIColor(tint).withAlphaComponent(1.0),
        ]
        for (i, color) in greens.enumerated() {
            let cone = SCNCone(topRadius: 0.02, bottomRadius: CGFloat(1.3 - Double(i) * 0.32), height: 0.85)
            let layer = SCNNode(geometry: cone)
            layer.geometry?.materials = [pbr(color, roughness: 0.8,
                                             emissive: i == 2 ? UIColor(tint).withAlphaComponent(0.35) : nil)]
            layer.position = SCNVector3(0.18, 2.4 + Float(i) * 0.55, 0)
            palm.addChildNode(layer)
        }
        palm.position = position
        // A gentle sway sells the breeze.
        palm.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0, z: 0.05, duration: 1.8),
            .rotateBy(x: 0, y: 0, z: -0.05, duration: 1.8),
        ])))
        scene.rootNode.addChildNode(palm)
    }

    // MARK: balls

    /// Renders the player's emoji on a colored disc — used as the ball texture.
    private func ballTexture(avatar: String, colorHex: String) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(Color(hex: colorHex)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // A lighter band gives the sphere a beach-ball read as it rolls.
            UIColor(white: 1, alpha: 0.22).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 52))
            let font = UIFont.systemFont(ofSize: 150)
            let text = NSAttributedString(string: avatar, attributes: [.font: font])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                  y: (size.height - textSize.height) / 2))
        }
    }

    private func spawnBalls() {
        let count = players.count
        for (index, info) in players.enumerated() {
            let tee = SCNVector3(Float(index) * 1.1 - Float(count - 1) * 0.55, 0.8, 15)
            let color = UIColor(Color(hex: info.colorHex))

            let sphere = SCNSphere(radius: 0.42)
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = ballTexture(avatar: info.avatar, colorHex: info.colorHex)
            m.roughness.contents = 0.35
            m.emission.contents = color.withAlphaComponent(0.18)
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

            // Color trail — only emits while the ball is moving (see update loop).
            let trail = SCNParticleSystem()
            trail.birthRate = 0
            trail.particleLifeSpan = 0.55
            trail.particleSize = 0.14
            trail.particleSizeVariation = 0.06
            trail.particleColor = color
            trail.particleVelocity = 0
            trail.spreadingAngle = 180
            trail.blendMode = .additive
            trail.emitterShape = SCNSphere(radius: 0.18)
            node.addParticleSystem(trail)

            // Floating name tag (kept upright separately from the rolling ball).
            // Heights alternate so tags don't overlap while balls sit on the tee.
            let tagHeight: Float = index % 2 == 0 ? 0.95 : 1.65
            let text = SCNText(string: info.name, extrusionDepth: 0.06)
            text.font = UIFont.systemFont(ofSize: 0.42, weight: .heavy)
            text.flatness = 0.25
            let tagMat = SCNMaterial()
            tagMat.lightingModel = .constant
            tagMat.diffuse.contents = UIColor.white
            tagMat.emission.contents = UIColor(white: 0.95, alpha: 1)
            text.materials = [tagMat]
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

            balls[info.id] = Ball(info: info, node: node, tag: tag, trail: trail,
                                  tee: tee, tagHeight: tagHeight)
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
        let color = UIColor(Color(hex: ball.info.colorHex))
        let arrowBody = SCNNode(geometry: SCNCylinder(radius: 0.1, height: length))
        arrowBody.geometry?.materials = [pbr(color, roughness: 0.3, emissive: color)]
        arrowBody.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // lie along +z
        arrowBody.position = SCNVector3(0, 0, Float(length) / 2)

        let tip = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.26, height: 0.55))
        tip.geometry?.materials = [pbr(color, roughness: 0.3, emissive: color)]
        tip.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        tip.position = SCNVector3(0, 0, Float(length) + 0.25)

        let holder = SCNNode()
        holder.addChildNode(arrowBody)
        holder.addChildNode(tip)
        holder.position = SCNVector3(ball.node.presentation.position.x, 0.25,
                                     ball.node.presentation.position.z)
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

            // Keep the name tag floating above the rolling ball; trail only
            // burns while the ball is actually flying.
            ball.tag.position = SCNVector3(p.x, p.y + ball.tagHeight, p.z)
            ball.trail.birthRate = speed > 2.5 ? 110 : 0

            // Sink: near the cup, on the green, slow enough.
            let horizontalDist = sqrt(pow(p.x - holeCenter.x, 2) + pow(p.z - holeCenter.z, 2))
            if horizontalDist < 0.7, p.y < 1.4, speed < 5.5 {
                ball.sunk = true
                balls[id] = ball
                finishOrder.append(id)
                celebrate(color: UIColor(Color(hex: ball.info.colorHex)))
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

    private func celebrate(color: UIColor) {
        for c in [UIColor(Theme.yellow), color] {
            let sparks = SCNParticleSystem()
            sparks.birthRate = 420
            sparks.emissionDuration = 0.4
            sparks.particleLifeSpan = 1.1
            sparks.particleVelocity = 7
            sparks.particleVelocityVariation = 3.5
            sparks.spreadingAngle = 80
            sparks.particleSize = 0.13
            sparks.particleColor = c
            sparks.blendMode = .additive
            sparks.emitterShape = SCNSphere(radius: 0.3)
            let emitter = SCNNode()
            emitter.position = SCNVector3(holeCenter.x, 0.6, holeCenter.z)
            emitter.addParticleSystem(sparks)
            scene.rootNode.addChildNode(emitter)
            emitter.runAction(.sequence([.wait(duration: 2.0), .removeFromParentNode()]))
        }
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
