import SwiftUI
import SceneKit

struct GolfPlayerInfo {
    let id: String
    let name: String
    let avatar: String
    let colorHex: String
    let anviled: Bool
}

/// Guerilla Golf on the TV — one continuous low-poly fairway, played in
/// rounds: one player shoots at a time, rotation driven by this board and
/// mirrored to every phone through the server (`golf_progress`).
///
/// Crash safety: every input coming from the network thread is queued and
/// applied inside the SceneKit render callback, never mid-simulation. The
/// HDR post-processing stack only runs when the scene draws on the device's
/// own screen — AirPlay external displays get the standard pipeline.
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

            turnBanner

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

    @ViewBuilder
    private var turnBanner: some View {
        if let golf = client.room?.golf,
           let shooter = client.room?.player(golf.turnId) {
            HStack(spacing: 10) {
                Text(shooter.avatar).font(.system(size: 30))
                Text("\(shooter.name.uppercased())'S SHOT")
                    .font(Theme.title(26))
                    .foregroundStyle(Color(hex: shooter.color))
                    .neonGlow(Color(hex: shooter.color), radius: 10)
                Text("🎯")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.panel.opacity(0.92)))
            .padding(.top, 6)
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: golf.turnId)
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
            // The HDR stack is the prime suspect for the AirPlay crash, so it
            // stays off whenever the board is on the external display.
            useHDR: !client.boardDisplayConnected,
            onSank: { playerId in
                if let p = room.player(playerId) {
                    finished.append(p)
                }
            },
            onProgress: { turnId, sunk in
                client.golfProgress(turnId: turnId, sunk: sunk)
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
        sceneController.begin()
    }
}

// MARK: - Procedural textures (drawn once, no asset files)

private enum Tex {
    /// Golf fairway: clean alternating mowing stripes (noise-free — noise is
    /// what made the first pass read "cheap"), with a soft seam highlight.
    static func fairway() -> UIImage {
        draw(512) { ctx, size in
            let a = UIColor(red: 0.33, green: 0.82, blue: 0.45, alpha: 1)
            let b = UIColor(red: 0.26, green: 0.72, blue: 0.38, alpha: 1)
            let band = size.width / 8
            for i in 0..<8 {
                (i % 2 == 0 ? a : b).setFill()
                ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: size.height))
                // Subtle bright seam on each stripe edge sells the "mowed" look.
                UIColor(white: 1, alpha: 0.07).setFill()
                ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: 3, height: size.height))
            }
        }
    }

    /// Course flanks: layered earth strata.
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
            // Darken toward the bottom so the cliff face reads grounded.
            let shade = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.35).cgColor] as CFArray,
                locations: [0.4, 1]
            )!
            ctx.cgContext.drawLinearGradient(shade, start: .zero,
                                             end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    /// Sand bunker: clean tan with a soft inner-shadow rim.
    static func sand() -> UIImage {
        draw(256) { ctx, size in
            UIColor(red: 0.95, green: 0.86, blue: 0.62, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let rim = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(red: 0.45, green: 0.33, blue: 0.16, alpha: 0.35).cgColor] as CFArray,
                locations: [0.62, 1]
            )!
            ctx.cgContext.drawRadialGradient(
                rim,
                startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width / 2,
                options: []
            )
        }
    }

    /// Soft ambient-occlusion vignette laid over the fairway top — fakes the
    /// baked contact shadows that make stylized games look "finished".
    static func aoVignette() -> UIImage {
        draw(512) { ctx, size in
            let g = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.02).cgColor,
                         UIColor(white: 0, alpha: 0.30).cgColor] as CFArray,
                locations: [0, 0.62, 1]
            )!
            ctx.cgContext.drawRadialGradient(
                g,
                startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width * 0.72,
                options: [.drawsAfterEndLocation]
            )
        }
    }

    /// Night ocean for under the course: deep blue with soft wave bands.
    static func water() -> UIImage {
        draw(512) { ctx, size in
            let base = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 0.10, green: 0.16, blue: 0.42, alpha: 1).cgColor,
                         UIColor(red: 0.05, green: 0.07, blue: 0.24, alpha: 1).cgColor] as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(base, start: .zero,
                                             end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.10).setStroke()
            for row in 0..<9 {
                let path = UIBezierPath()
                let y = CGFloat(row) * size.height / 9 + 24
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x < size.width {
                    path.addQuadCurve(
                        to: CGPoint(x: x + 64, y: y),
                        controlPoint: CGPoint(x: x + 32, y: y + (row % 2 == 0 ? 10 : -10))
                    )
                    x += 64
                }
                path.lineWidth = 5
                path.stroke()
            }
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
            for _ in 0..<240 {
                let y = CGFloat.random(in: 0...(size.height * 0.7))
                let x = CGFloat.random(in: 0...size.width)
                let r = CGFloat.random(in: 0.6...2.2)
                UIColor(white: 1, alpha: CGFloat.random(in: 0.25...0.95)).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            // A soft moon with a glow halo.
            let moonCenter = CGPoint(x: size.width * 0.76, y: size.height * 0.18)
            let halo = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0.45).cgColor,
                         UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0).cgColor] as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawRadialGradient(halo, startCenter: moonCenter, startRadius: 4,
                                             endCenter: moonCenter, endRadius: 95, options: [])
            UIColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 0.95).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: moonCenter.x - 26, y: moonCenter.y - 26,
                                                 width: 52, height: 52))
        }
    }

    private static func draw(_ width: CGFloat, height: CGFloat? = nil,
                             _ body: (UIGraphicsImageRendererContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: width, height: height ?? width)
        return UIGraphicsImageRenderer(size: size).image { ctx in body(ctx, size) }
    }
}

// MARK: - SceneKit world

final class GolfSceneController: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
    private struct Ball {
        let info: GolfPlayerInfo
        let node: SCNNode
        let tag: SCNNode
        let trail: SCNParticleSystem
        let tee: SCNVector3
        let tagHeight: Float
        var sunk = false
        var respawning = false
        /// CHANGED: the ball's last *resting lie*. Initialized to the tee, then
        /// re-saved every time the whole table comes to rest. The next stroke is
        /// played from here, and an off-island ball respawns here — never back at
        /// the tee. This is the persistent per-ball state Objective 1 needs.
        var restingPosition: SCNVector3
    }

    private enum ShotPhase {
        case waitingForShot
        case settling
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let players: [GolfPlayerInfo]
    private let endsAt: Date
    private let useHDR: Bool
    private let onSank: (String) -> Void
    private let onProgress: (String?, [String]) -> Void
    private let onFinished: ([String]) -> Void

    // Render-thread state. Only touched inside renderer(_:updateAtTime:).
    private var balls: [String: Ball] = [:]
    private var aimNodes: [String: SCNNode] = [:]
    private var turnSpotlight: SCNNode?
    private var sunkOrder: [String] = []
    private var done = false
    private var turnQueue: [String] = []
    private var turnIndex = -1
    private var currentTurnId: String?
    private var shotPhase: ShotPhase = .waitingForShot
    private var turnDeadline: TimeInterval = 0
    private var settleMinTime: TimeInterval = 0
    private var settleMaxTime: TimeInterval = 0

    private let shotClock: TimeInterval = 14
    private let holeCenter = SCNVector3(2.6, 0, -13)

    // NEW: ball-on-ball collision support.
    /// Physics category bit unique to balls, so we can ask SceneKit to report
    /// ball↔ball contacts (for feedback) without losing the solver's collision.
    private static let ballCategory = 1 << 1
    /// Immutable set of ball ids, safe to read from the physics thread inside the
    /// contact delegate (the `balls` dictionary is render-thread-only).
    private let ballIds: Set<String>
    /// Throttles collision feedback — a single hit fires many micro-contacts.
    private var lastBallContactTime: TimeInterval = 0

    // Inputs arrive on the main/network thread; they are applied here, on the
    // render thread, at a safe point in the frame. (Mutating physics from
    // another thread mid-step is the classic SceneKit crash.)
    private let pendingLock = NSLock()
    private var pending: [(GolfSceneController) -> Void] = []

    init(
        players: [GolfPlayerInfo],
        endsAt: Date,
        useHDR: Bool,
        onSank: @escaping (String) -> Void,
        onProgress: @escaping (String?, [String]) -> Void,
        onFinished: @escaping ([String]) -> Void
    ) {
        self.players = players
        self.endsAt = endsAt
        self.useHDR = useHDR
        self.onSank = onSank
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.turnQueue = players.map(\.id)
        self.ballIds = Set(players.map(\.id)) // NEW: physics-thread-safe id lookup
        super.init()
        buildWorld()
        spawnBalls()
    }

    // MARK: thread-safe entry points (callable from any thread)

    private func enqueue(_ block: @escaping (GolfSceneController) -> Void) {
        pendingLock.lock()
        pending.append(block)
        pendingLock.unlock()
    }

    func begin() {
        enqueue { s in s.advanceTurn(now: CACurrentMediaTime()) }
    }

    func setAim(playerId: String, angle: Double, power: Double) {
        enqueue { s in s.applyAim(playerId: playerId, angle: angle, power: power) }
    }

    func clearAim(playerId: String) {
        enqueue { s in s.removeAim(playerId: playerId) }
    }

    func fire(playerId: String, angle: Double, power: Double) {
        enqueue { s in s.applyFire(playerId: playerId, angle: angle, power: power) }
    }

    // MARK: materials

    private func pbr(_ contents: Any, roughness: CGFloat = 0.85,
                     emissive: UIColor? = nil, tile: (Float, Float)? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
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
        scene.fogStartDistance = 52
        scene.fogEndDistance = 110
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        scene.physicsWorld.contactDelegate = self // NEW: ball-on-ball contact feedback

        let camera = SCNCamera()
        camera.fieldOfView = 52
        camera.zFar = 220
        #if !targetEnvironment(simulator)
        if useHDR {
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = false
            camera.bloomIntensity = 0.85
            camera.bloomThreshold = 0.55
            camera.bloomBlurRadius = 14
            camera.screenSpaceAmbientOcclusionIntensity = 1.1
            camera.screenSpaceAmbientOcclusionRadius = 1.4
            camera.vignettingPower = 0.7
            camera.vignettingIntensity = 0.55
        }
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

        // Warm key light + cool purple fill.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1250
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
        fill.light?.intensity = 310
        fill.light?.color = UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(fill)

        // ONE continuous flat fairway — a single floating slab, no gaps.
        // Fall off the open sides or the far end and you respawn at the tee.
        let slab = SCNBox(width: 15, height: 2.6, length: 36, chamferRadius: 0.45)
        let top = pbr(Tex.fairway(), roughness: 0.9, tile: (2.2, 5))
        let side = pbr(Tex.cliff(), roughness: 0.95, tile: (4, 1))
        let bottom = pbr(UIColor(red: 0.20, green: 0.12, blue: 0.09, alpha: 1))
        slab.materials = [side, side, side, side, top, bottom] // +z +x -z -x +y -y
        let ground = SCNNode(geometry: slab)
        ground.position = SCNVector3(0, -1.3, -1)
        ground.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        ground.physicsBody?.friction = 0.55
        ground.physicsBody?.restitution = 0.25
        scene.rootNode.addChildNode(ground)

        // Grass lip overhanging the cliff — the classic stylized-island read.
        let grassLip = SCNBox(width: 15.7, height: 0.26, length: 36.7, chamferRadius: 0.13)
        grassLip.materials = [pbr(UIColor(red: 0.22, green: 0.62, blue: 0.33, alpha: 1), roughness: 0.9)]
        let grassLipNode = SCNNode(geometry: grassLip)
        grassLipNode.position = SCNVector3(0, -0.17, -1)
        scene.rootNode.addChildNode(grassLipNode)

        // Baked-AO style vignette over the fairway: soft contact shadows at
        // the edges make the whole course look lit, not flat.
        let aoPlane = SCNPlane(width: 14.7, height: 35.7)
        let aoMat = SCNMaterial()
        aoMat.lightingModel = .constant
        aoMat.diffuse.contents = Tex.aoVignette()
        aoMat.writesToDepthBuffer = false
        aoPlane.materials = [aoMat]
        let ao = SCNNode(geometry: aoPlane)
        ao.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        ao.position = SCNVector3(0, 0.015, -1)
        scene.rootNode.addChildNode(ao)

        // Night ocean far below; the course floats over it.
        let sea = SCNPlane(width: 150, height: 150)
        let seaMat = SCNMaterial()
        seaMat.lightingModel = .constant
        seaMat.diffuse.contents = Tex.water()
        seaMat.transparency = 0.96
        sea.materials = [seaMat]
        let seaNode = SCNNode(geometry: sea)
        seaNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        seaNode.position = SCNVector3(0, -6.8, -8)
        seaNode.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.3, z: 0, duration: 3.2),
            .moveBy(x: 0, y: -0.3, z: 0, duration: 3.2),
        ])))
        scene.rootNode.addChildNode(seaNode)

        // Raised tee pad so the start reads as a place, not a random corner.
        let pad = SCNBox(width: 11, height: 0.06, length: 2.6, chamferRadius: 0.03)
        pad.materials = [pbr(UIColor(red: 0.40, green: 0.88, blue: 0.52, alpha: 1), roughness: 0.85)]
        let padNode = SCNNode(geometry: pad)
        padNode.position = SCNVector3(0, 0.03, 15)
        scene.rootNode.addChildNode(padNode)

        // Glowing disc that follows whoever's turn it is.
        let spotGeo = SCNCylinder(radius: 0.95, height: 0.02)
        let spotMat = SCNMaterial()
        spotMat.lightingModel = .constant
        spotMat.diffuse.contents = UIColor.clear
        spotMat.emission.contents = UIColor(Theme.yellow)
        spotMat.transparency = 0.4
        spotMat.blendMode = .add
        spotMat.writesToDepthBuffer = false
        spotGeo.materials = [spotMat]
        let spot = SCNNode(geometry: spotGeo)
        spot.isHidden = true
        scene.rootNode.addChildNode(spot)
        turnSpotlight = spot

        // Low lip behind the tee so weak shots don't dribble off the back.
        let lip = SCNNode(geometry: SCNBox(width: 15, height: 0.6, length: 0.5, chamferRadius: 0.1))
        lip.geometry?.materials = [pbr(UIColor(Theme.purple), roughness: 0.35,
                                       emissive: UIColor(Theme.purple).withAlphaComponent(0.6))]
        lip.position = SCNVector3(0, 0.3, 16.8)
        lip.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        lip.physicsBody?.restitution = 0.6
        scene.rootNode.addChildNode(lip)

        // Neon edge trim along both long sides.
        for (x, color) in [(Float(-7.35), Theme.cyan), (Float(7.35), Theme.pink)] {
            let trim = SCNNode(geometry: SCNBox(width: 0.18, height: 0.14, length: 35.8, chamferRadius: 0.05))
            trim.geometry?.materials = [pbr(UIColor(color), roughness: 0.3, emissive: UIColor(color))]
            trim.position = SCNVector3(x, 0.07, -1)
            scene.rootNode.addChildNode(trim)
        }

        // Candy-striped bumpers mid-course.
        let bumperTex = Tex.candy(
            UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1),
            UIColor(Theme.orange)
        )
        for x: Float in [-3.6, 3.6] {
            let bumper = SCNNode(geometry: SCNCylinder(radius: 1.15, height: 1.6))
            bumper.geometry?.materials = [pbr(bumperTex, roughness: 0.4)]
            bumper.position = SCNVector3(x, 0.8, -1)
            bumper.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            bumper.physicsBody?.restitution = 1.15
            scene.rootNode.addChildNode(bumper)

            let halo = SCNNode(geometry: SCNTorus(ringRadius: 1.18, pipeRadius: 0.07))
            halo.geometry?.materials = [pbr(UIColor(Theme.orange), roughness: 0.3,
                                            emissive: UIColor(Theme.orange))]
            halo.position = SCNVector3(x, 1.62, -1)
            scene.rootNode.addChildNode(halo)
        }

        // Spinning candy paddle guarding the green.
        let paddle = SCNNode(geometry: SCNBox(width: 6.5, height: 0.9, length: 0.45, chamferRadius: 0.12))
        paddle.geometry?.materials = [pbr(Tex.candy(.white, UIColor(Theme.pink)), roughness: 0.35)]
        paddle.position = SCNVector3(0, 0.45, -7.8)
        paddle.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        paddle.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.9)))
        scene.rootNode.addChildNode(paddle)

        // Sand bunker flavor near the green.
        let bunker = SCNNode(geometry: SCNCylinder(radius: 2.0, height: 0.06))
        bunker.geometry?.materials = [pbr(Tex.sand(), roughness: 0.95, tile: (2, 2))]
        bunker.position = SCNVector3(-2.6, 0.03, -10.5)
        scene.rootNode.addChildNode(bunker)

        buildHole()
        buildScenery()
    }

    private func buildHole() {
        let cup = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.08))
        cup.geometry?.materials = [pbr(UIColor(white: 0.02, alpha: 1), roughness: 1)]
        cup.position = SCNVector3(holeCenter.x, 0.05, holeCenter.z)
        scene.rootNode.addChildNode(cup)

        // Crisp white rim so the cup reads from across the room.
        let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.62, pipeRadius: 0.045))
        rim.geometry?.materials = [pbr(UIColor.white, roughness: 0.4,
                                       emissive: UIColor(white: 0.85, alpha: 1))]
        rim.position = SCNVector3(holeCenter.x, 0.09, holeCenter.z)
        scene.rootNode.addChildNode(rim)

        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.85, pipeRadius: 0.08))
        ring.geometry?.materials = [pbr(UIColor(Theme.yellow), roughness: 0.3,
                                        emissive: UIColor(Theme.yellow))]
        ring.position = SCNVector3(holeCenter.x, 0.1, holeCenter.z)
        ring.runAction(.repeatForever(.sequence([
            .scale(to: 1.22, duration: 0.7),
            .scale(to: 0.95, duration: 0.7),
        ])))
        scene.rootNode.addChildNode(ring)

        // Soft additive light column rising from the cup.
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
        // A lazy wave keeps the green feeling alive.
        pennant.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0.45, z: 0, duration: 0.9),
            .rotateBy(x: 0, y: -0.45, z: 0, duration: 0.9),
        ])))
        scene.rootNode.addChildNode(pennant)
    }

    /// Set dressing: party palms on the corners, floating rocks, clouds.
    private func buildScenery() {
        let palmSpots: [(Float, Float)] = [(-6.4, 15.8), (6.4, 15.8), (-6.4, -17.2), (6.2, -8.6)]
        for (i, spot) in palmSpots.enumerated() {
            addPalm(at: SCNVector3(spot.0, 0, spot.1), tint: i % 2 == 0 ? Theme.cyan : Theme.pink)
        }

        for _ in 0..<7 {
            let r = CGFloat.random(in: 0.5...1.3)
            let rock = SCNSphere(radius: r)
            rock.segmentCount = 5
            let node = SCNNode(geometry: rock)
            node.geometry?.materials = [pbr(UIColor(red: 0.36, green: 0.30, blue: 0.52, alpha: 1), roughness: 0.9)]
            node.position = SCNVector3(
                Float.random(in: -17 ... 17),
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
        palm.addChildNode(trunk)

        let greens = [
            UIColor(red: 0.16, green: 0.62, blue: 0.34, alpha: 1),
            UIColor(red: 0.20, green: 0.72, blue: 0.40, alpha: 1),
            UIColor(tint),
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
        // Canopy sway only — the trunk's physics stays put.
        trunk.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        scene.rootNode.addChildNode(palm)
    }

    // MARK: balls

    private func ballTexture(avatar: String, colorHex: String) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(Color(hex: colorHex)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
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
            body.mass = 1                 // equal masses → clean momentum exchange on a hit
            body.restitution = 0.7        // CHANGED 0.55→0.7: livelier, near-elastic ball-on-ball transfer
            body.friction = 0.5
            body.rollingFriction = 0.18
            body.damping = 0.16
            body.angularDamping = 0.4
            // NEW: make ball↔ball collisions explicit and observable.
            // collisionBitMask stays "all" so the solver still bounces balls off
            // each other (and the course); contactTestBitMask fires the delegate
            // so we can add a spark and re-save lies. node.name identifies balls.
            body.categoryBitMask = Self.ballCategory
            body.collisionBitMask = -1
            body.contactTestBitMask = Self.ballCategory
            node.name = info.id
            node.physicsBody = body
            scene.rootNode.addChildNode(node)

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
                                  tee: tee, tagHeight: tagHeight, restingPosition: tee)
        }
    }

    // MARK: input application (render thread only)

    private func groundDirection(_ angle: Double) -> SCNVector3 {
        SCNVector3(Float(cos(angle)), 0, Float(-sin(angle)))
    }

    private func applyAim(playerId: String, angle: Double, power: Double) {
        guard playerId == currentTurnId, let ball = balls[playerId], !ball.sunk else { return }
        removeAim(playerId: playerId)

        let dir = groundDirection(angle)
        let length = CGFloat(1.6 + 5.2 * power)
        let color = UIColor(Color(hex: ball.info.colorHex))
        let arrowBody = SCNNode(geometry: SCNCylinder(radius: 0.1, height: length))
        arrowBody.geometry?.materials = [pbr(color, roughness: 0.3, emissive: color)]
        arrowBody.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        arrowBody.position = SCNVector3(0, 0, Float(length) / 2)

        let tip = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.26, height: 0.55))
        tip.geometry?.materials = [pbr(color, roughness: 0.3, emissive: color)]
        tip.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        tip.position = SCNVector3(0, 0, Float(length) + 0.25)

        let holder = SCNNode()
        holder.addChildNode(arrowBody)
        holder.addChildNode(tip)
        let p = ball.node.presentation.position
        holder.position = SCNVector3(p.x, 0.25, p.z)
        holder.eulerAngles = SCNVector3(0, atan2(dir.x, dir.z), 0)
        scene.rootNode.addChildNode(holder)
        aimNodes[playerId] = holder
    }

    private func removeAim(playerId: String) {
        aimNodes[playerId]?.removeFromParentNode()
        aimNodes[playerId] = nil
    }

    private func applyFire(playerId: String, angle: Double, power: Double) {
        removeAim(playerId: playerId)
        guard playerId == currentTurnId, shotPhase == .waitingForShot,
              let ball = balls[playerId], !ball.sunk, !ball.respawning else { return }

        let p = min(1.0, max(0.0, power))
        let factor: Float = ball.info.anviled ? 0.7 : 1.0 // the Heavy Anvil at work
        let dir = groundDirection(angle)
        let horizontal = Float(5.0 + 14.0 * p) * factor
        let loft = Float(2.2 + 4.8 * p) * factor
        ball.node.physicsBody?.applyForce(
            SCNVector3(dir.x * horizontal, loft, dir.z * horizontal),
            asImpulse: true
        )
        // Squash-and-stretch pop on launch.
        ball.node.runAction(.sequence([
            .scale(to: 1.25, duration: 0.08),
            .scale(to: 1.0, duration: 0.2),
        ]))

        let now = CACurrentMediaTime()
        shotPhase = .settling
        settleMinTime = now + 1.3
        settleMaxTime = now + 5.0
    }

    // MARK: turn machine (render thread only)

    private func advanceTurn(now: TimeInterval) {
        guard !done else { return }
        let remaining = turnQueue.filter { !sunkOrder.contains($0) }
        guard !remaining.isEmpty else {
            finishGame()
            return
        }
        var idx = turnIndex
        repeat {
            idx = (idx + 1) % turnQueue.count
        } while sunkOrder.contains(turnQueue[idx])
        turnIndex = idx
        currentTurnId = turnQueue[idx]
        shotPhase = .waitingForShot
        turnDeadline = now + shotClock
        if let shooter = players.first(where: { $0.id == turnQueue[idx] }) {
            turnSpotlight?.geometry?.firstMaterial?.emission.contents =
                UIColor(Color(hex: shooter.colorHex))
        }
        reportProgress()
    }

    private func reportProgress() {
        let turn = currentTurnId
        let sunk = sunkOrder
        DispatchQueue.main.async { [onProgress] in
            onProgress(turn, sunk)
        }
    }

    private func allBallsSettled() -> Bool {
        for ball in balls.values where !ball.sunk && !ball.respawning {
            let v = ball.node.physicsBody?.velocity ?? SCNVector3Zero
            if sqrt(v.x * v.x + v.y * v.y + v.z * v.z) > 0.9 { return false }
        }
        return true
    }

    /// NEW: persist every live ball's current spot as its resting lie. Called
    /// once the whole table has stopped, so each player's *next* stroke — and any
    /// off-island respawn — starts from where their ball actually ended up. This
    /// captures balls that were shoved by someone else's shot too, satisfying the
    /// "both balls save their new resting positions" half of Objective 2.
    private func saveRestingPositions() {
        for (id, var ball) in balls where !ball.sunk && !ball.respawning {
            ball.restingPosition = ball.node.presentation.position
            balls[id] = ball
        }
    }

    // MARK: frame loop (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Apply queued network inputs at a safe point in the frame.
        pendingLock.lock()
        let commands = pending
        pending.removeAll()
        pendingLock.unlock()
        for command in commands { command(self) }

        guard !done else { return }
        let now = CACurrentMediaTime()

        for (id, var ball) in balls where !ball.sunk {
            let p = ball.node.presentation.position
            let v = ball.node.physicsBody?.velocity ?? SCNVector3Zero
            let speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

            ball.tag.position = SCNVector3(p.x, p.y + ball.tagHeight, p.z)
            ball.trail.birthRate = speed > 2.5 ? 110 : 0

            let horizontalDist = sqrt(pow(p.x - holeCenter.x, 2) + pow(p.z - holeCenter.z, 2))
            if horizontalDist < 0.7, p.y < 1.4, speed < 5.5 {
                ball.sunk = true
                balls[id] = ball
                sunkOrder.append(id)
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
                let sunkId = id
                DispatchQueue.main.async { [onSank] in onSank(sunkId) }
                reportProgress()
                continue
            }

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
                        // CHANGED: respawn at the saved resting lie, not the tee,
                        // so falling off only costs the stroke — the player keeps
                        // their progress up the fairway.
                        node.position = b.restingPosition
                        node.physicsBody?.resetTransform()
                        b.respawning = false
                        self.balls[id] = b
                    },
                    .fadeOpacity(to: 1, duration: 0.2),
                ]))
            }
        }

        // The glow disc tracks the active shooter's ball.
        if let spot = turnSpotlight {
            if let turnId = currentTurnId, let b = balls[turnId], !b.sunk {
                spot.isHidden = false
                let p = b.node.presentation.position
                spot.position = SCNVector3(p.x, 0.03, p.z)
            } else {
                spot.isHidden = true
            }
        }

        // Turn rotation.
        if currentTurnId != nil {
            switch shotPhase {
            case .waitingForShot:
                let shooterSank = currentTurnId.map { sunkOrder.contains($0) } ?? false
                if now > turnDeadline || shooterSank {
                    advanceTurn(now: now) // shot clock expired or shooter is done
                }
            case .settling:
                if now > settleMaxTime || (now > settleMinTime && allBallsSettled()) {
                    saveRestingPositions() // NEW: lock in where every ball ended up
                    advanceTurn(now: now)
                }
            }
        }

        if sunkOrder.count == balls.count || Date() >= endsAt {
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
        let order = sunkOrder
        DispatchQueue.main.async { [onFinished] in
            onFinished(order)
        }
    }

    // MARK: ball-on-ball collisions (physics thread)

    /// NEW. SceneKit's rigid-body solver already RESOLVES the collision: when two
    /// balls touch it applies an impulse along the contact normal n of
    ///     J = -(1 + e) · (v_rel · n) / (1/mₐ + 1/m_b)
    /// With equal masses (mₐ = m_b = 1) and restitution e ≈ 0.7, the balls
    /// exchange ~85% of the normal component of their relative velocity — i.e.
    /// the moving ball hands its momentum to the resting one, which takes off
    /// while the striker slows. We deliberately DON'T add our own impulse here:
    /// stacking a second impulse on top of the solver's makes hits explode. Our
    /// job in the delegate is only to (a) react with a spark and (b) let the
    /// table re-settle, after which `saveRestingPositions()` stores BOTH balls'
    /// new lies — so a knocked ball's next stroke also starts from where it stopped.
    ///
    /// Runs on SceneKit's physics thread, so it touches only immutable state
    /// (`ballIds`) and the value-typed contact, then hops to the render thread via
    /// `enqueue` for anything that mutates the scene.
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // Ball-ball only — reject ball↔course/bumper contacts.
        guard let a = contact.nodeA.name, ballIds.contains(a),
              let b = contact.nodeB.name, ballIds.contains(b) else { return }
        let now = CACurrentMediaTime()
        guard now - lastBallContactTime > 0.08 else { return } // collapse the contact burst
        lastBallContactTime = now

        let point = contact.contactPoint
        let strength = Float(min(1.0, max(0.0, contact.collisionImpulse / 6.0)))
        enqueue { s in s.spawnCollisionSpark(at: point, strength: strength) }
    }

    /// NEW: a quick spark where two balls clash — sells the impact on the TV.
    private func spawnCollisionSpark(at point: SCNVector3, strength: Float) {
        let sparks = SCNParticleSystem()
        sparks.birthRate = CGFloat(120 + 320 * strength)
        sparks.emissionDuration = 0.05
        sparks.particleLifeSpan = 0.4
        sparks.particleVelocity = CGFloat(3 + 6 * strength)
        sparks.particleVelocityVariation = 2.5
        sparks.spreadingAngle = 180
        sparks.particleSize = 0.1
        sparks.particleColor = UIColor(Theme.yellow)
        sparks.blendMode = .additive
        sparks.emitterShape = SCNSphere(radius: 0.1)
        let emitter = SCNNode()
        emitter.position = point
        emitter.addParticleSystem(sparks)
        scene.rootNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
    }
}
