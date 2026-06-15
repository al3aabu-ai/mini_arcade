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
    @ObservedObject private var loc = Localization.shared
    @State private var controller: GolfSceneController?
    /// Which map the current controller was built for — rebuild when it changes.
    @State private var builtMap: String?
    @State private var finished: [PlayerState] = []

    private var golf: GolfState? { client.room?.golf }

    /// HUD title per round's map.
    private var mapTitleKey: String {
        switch golf?.map {
        case "tiki": return "🌴 TIKI JUNGLE"
        case "runway": return "🛫 TIKI RUNWAY"
        default: return "⛳️ GUERILLA GOLF"
        }
    }

    var body: some View {
        ZStack {
            if let controller {
                SceneView(
                    scene: controller.scene,
                    pointOfView: controller.cameraNode,
                    // options: [] deliberately omits `.rendersContinuously`, so the
                    // renderer is ON-DEMAND: it only redraws when the scene is dirty
                    // (a moving ball, a running action) instead of forcing a heavy
                    // continuous redraw every vsync. Big thermal/idle win.
                    options: [],
                    // Cap the frame rate — ProMotion (120Hz) hardware would otherwise
                    // max out and overheat. 60 is smooth; set GolfSceneController
                    // .targetFPS = 30 to baseline thermals.
                    preferredFramesPerSecond: GolfSceneController.targetFPS,
                    // Halve the MSAA resolve cost of the .multisampling4X default;
                    // edges stay smooth without cooking the GPU.
                    antialiasingMode: .multisampling2X,
                    delegate: controller
                )
                .ignoresSafeArea()
            }
            hud
        }
        .onAppear {
            rebuildIfNeeded()
            controller?.scene.isPaused = false // resume actions/physics when visible
        }
        .onChange(of: golf?.map) { _, _ in rebuildIfNeeded() } // Round 1 → Round 2 swaps the map
        .onDisappear {
            client.onAim = nil
            client.onAimClear = nil
            client.onFire = nil
            // Freeze the whole scene when the board leaves the screen (between
            // rounds, podium, lobby, or the host closing the preview). Pausing
            // halts every looping obstacle action, the physics step, AND the
            // render loop at once — the scene stops cooking the GPU while idle.
            controller?.scene.isPaused = true
        }
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.tr(mapTitleKey))
                        .font(Theme.title(30))
                        .foregroundStyle(.white)
                        .neonGlow(Theme.cyan, radius: 10)
                    Text(loc.tr("ROUND %@/3", "\(golf?.round ?? 1)"))
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let golf {
                        CountdownLabel(endsAt: golf.endsAtDate, font: Theme.title(42))
                    }
                    Text(loc.tr("FEWEST STROKES WINS"))
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.yellow.opacity(0.85))
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)

            turnBanner
            strokeLeaderboard

            Spacer()
        }
    }

    /// Live standings: every player by fewest strokes (lowest = leading).
    @ViewBuilder
    private var strokeLeaderboard: some View {
        if let golf, let room = client.room {
            let ranked = room.players.sorted {
                (golf.strokes[$0.id] ?? 0) < (golf.strokes[$1.id] ?? 0)
            }
            HStack(spacing: 10) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 5) {
                        Text(index == 0 ? "🏆" : "\(index + 1)")
                        Text(player.avatar)
                        Text("\(golf.strokes[player.id] ?? 0)")
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.yellow)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.panel.opacity(0.9)))
                }
            }
            .font(Theme.body(15))
            .foregroundStyle(.white)
            .padding(.top, 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: golf.strokes)
        }
    }

    @ViewBuilder
    private var turnBanner: some View {
        if let golf = client.room?.golf,
           let shooter = client.room?.player(golf.turnId) {
            HStack(spacing: 10) {
                Text(shooter.avatar).font(.system(size: 30))
                Text(loc.tr("%@'S SHOT", shooter.name.uppercased()))
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

    /// Build the scene for the current golf map. Rebuilds from scratch when the
    /// map changes (Round 1 Guerilla → Round 2 Tiki) so Round 2 spawns cleanly.
    private func rebuildIfNeeded() {
        guard let room = client.room, let golf = room.golf else { return }
        if controller != nil, builtMap == golf.map { return } // already built for this map

        // Tear down the previous round's controller/input routing.
        client.onAim = nil
        client.onAimClear = nil
        client.onFire = nil
        finished = []

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
            // THERMAL BASELINE: HDR/bloom/SSAO are force-disabled everywhere.
            // The post-processing passes (glow + screen-space ambient occlusion)
            // cook the mobile GPU; with useHDR=false the camera keeps SceneKit's
            // defaults (wantsHDR=false, bloom 0, SSAO 0) so none of them run. This
            // also keeps the AirPlay-crash-prone HDR path off. To restore the rich
            // look later, revert to `!client.boardDisplayConnected`.
            useHDR: false,
            map: golf.map,
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
            },
            onRegisterCoins: { coins in
                client.registerCoins(coins)
            },
            onCollectCoin: { coinId, playerId in
                client.collectCoin(coinId: coinId, playerId: playerId)
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
        builtMap = golf.map
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

/// A self-contained golf course module the controller can drop into the scene
/// and query for spawn/hole positions and hazard regions. Both Tiki maps
/// (Jungle = R2, Runway = R3) conform, so the controller stays course-agnostic.
protocol GolfHazardCourse {
    var root: SCNNode { get }
    var teePosition: SCNVector3 { get }
    var holeCenter: SCNVector3 { get }
    func isOverWater(_ p: SCNVector3) -> Bool
    func isOverSand(_ p: SCNVector3) -> Bool
    /// World positions where the controller should drop spinning collectible
    /// coins — placed strategically along the course's pathways.
    var coinPositions: [SCNVector3] { get }
}

extension GolfHazardCourse {
    var coinPositions: [SCNVector3] { [] } // courses opt in by overriding
}

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

    /// Thermal cap — the SceneView renders at most this many FPS. Dropped to 30
    /// for a rock-solid low-power baseline (was 60); raise back to 60 once we've
    /// confirmed the heat buildup is under control. Without the cap, ProMotion
    /// hardware pushes 120Hz and needlessly cooks the GPU.
    static let targetFPS = 30

    private let players: [GolfPlayerInfo]
    private let endsAt: Date
    private let useHDR: Bool
    /// "guerilla" (R1), "tiki" (R2), or "runway" (R3) — which course to build.
    private let courseMap: String
    /// Backing module for the Tiki maps; provides tee, hole, and hazard regions.
    private var hazardCourse: GolfHazardCourse?
    private let onSank: (String) -> Void
    private let onProgress: (String?, [String]) -> Void
    private let onFinished: ([String]) -> Void
    /// Coin callbacks: register the placed layout with the server, and report a
    /// pickup (coinId, collecting playerId) so the server credits the wallet.
    private let onRegisterCoins: ([GolfCoinSpawn]) -> Void
    private let onCollectCoin: (String, String) -> Void
    /// Live coin nodes by id (render-thread-only, like `balls`).
    private var coins: [String: SCNNode] = [:]

    // Render-thread state. Only touched inside renderer(_:updateAtTime:).
    private var balls: [String: Ball] = [:]
    private var aimNodes: [String: SCNNode] = [:]
    private var turnSpotlight: SCNNode?
    /// Camera follow: the look-at target node + the trailing offset from the ball.
    /// Elevated + behind for a clean third-person frame; the look offset drops to
    /// fairway level AHEAD of the ball (toward the −Z hole) so the cam pitches
    /// DOWN the path — the runway width, side water, and obstacles read clearly.
    private var lookTargetNode: SCNNode?
    private var cameraFollowOffset = SCNVector3(0, 14, 20)
    private var cameraLookOffset = SCNVector3(0, 0, -11)
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
    /// Cup location. Set per map in buildWorld (Guerilla default below; Tiki uses
    /// its own course hole).
    private var holeCenter = SCNVector3(2.6, 0, -13)

    /// Below this Y a ball has fallen off the platform — the ONLY condition that
    /// resets a ball to the tee. A ball resting safely on the fairway (y≈0.4) is
    /// never reset. (Requirement 1)
    private let outOfBoundsY: Float = -9
    /// Speed (m/s) below which a ball counts as fully stopped. Near zero so the
    /// turn only advances once the physics world is genuinely at rest, not merely
    /// rolling slowly. (Requirements 2 & 3)
    private let restSpeed: Float = 0.08

    // NEW: ball-on-ball collision support.
    /// Physics category bit unique to balls, so we can ask SceneKit to report
    /// ball↔ball contacts (for feedback) without losing the solver's collision.
    /// FIX: must NOT reuse SceneKit's reserved bits — 1<<0 is
    /// `SCNPhysicsCollisionCategoryDefault` and 1<<1 is
    /// `SCNPhysicsCollisionCategoryStatic` (what the ground/walls/bumpers use).
    /// Tagging dynamic balls with 1<<1 made the solver treat ball↔ground as a
    /// static/static pair and skip it, so balls fell through the floor. Use a
    /// private high bit instead.
    private static let ballCategory = 1 << 5
    /// Coins live on their own bit so they can be a contact-only trigger that the
    /// ball passes THROUGH (the ball's collisionBitMask excludes this bit).
    private static let coinCategory = 1 << 6
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
        map: String = "guerilla",
        onSank: @escaping (String) -> Void,
        onProgress: @escaping (String?, [String]) -> Void,
        onFinished: @escaping ([String]) -> Void,
        onRegisterCoins: @escaping ([GolfCoinSpawn]) -> Void = { _ in },
        onCollectCoin: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.players = players
        self.endsAt = endsAt
        self.useHDR = useHDR
        self.courseMap = map
        self.onSank = onSank
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.onRegisterCoins = onRegisterCoins
        self.onCollectCoin = onCollectCoin
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

    // MARK: coins

    /// Drop spinning gold coins at the course's strategic positions, then tell
    /// the server about them so it owns coin existence + crediting. Called by the
    /// Tiki/Runway builders (Guerilla ships no coins).
    private func spawnCoins(at positions: [SCNVector3]) {
        guard !positions.isEmpty else { return }
        var spawns: [GolfCoinSpawn] = []
        for (i, pos) in positions.enumerated() {
            let id = "coin-\(i)"
            let node = makeCoinNode(id: id, at: pos)
            scene.rootNode.addChildNode(node)
            coins[id] = node
            spawns.append(GolfCoinSpawn(id: id, x: Double(pos.x), y: Double(pos.y), z: Double(pos.z)))
        }
        DispatchQueue.main.async { [onRegisterCoins] in onRegisterCoins(spawns) }
    }

    /// A low-poly gold coin: a thin upright box that slowly spins on its Y axis,
    /// with a STATIC contact-only trigger body (the ball passes through it).
    private func makeCoinNode(id: String, at position: SCNVector3) -> SCNNode {
        let box = SCNBox(width: 0.62, height: 0.62, length: 0.12, chamferRadius: 0.06)
        let gold = SCNMaterial()
        gold.lightingModel = .physicallyBased
        gold.diffuse.contents = UIColor(Theme.yellow)
        gold.metalness.contents = 0.95
        gold.roughness.contents = 0.25
        gold.emission.contents = UIColor(red: 0.45, green: 0.36, blue: 0.0, alpha: 1)
        box.materials = [gold]

        let node = SCNNode(geometry: box)
        node.name = id
        node.position = position

        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: box, options: nil))
        body.isAffectedByGravity = false
        body.categoryBitMask = Self.coinCategory
        body.collisionBitMask = 0                    // never push anything (pure trigger)
        body.contactTestBitMask = Self.ballCategory  // fire didBegin when a ball touches it
        node.physicsBody = body

        node.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 2.0)))
        return node
    }

    // MARK: world building

    private func buildWorld() {
        if courseMap == "tiki" { buildTikiWorld(); return }     // Round 2 course
        if courseMap == "runway" { buildRunwayWorld(); return } // Round 3 course (final)
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
        lookTargetNode = lookTarget
        cameraFollowOffset = SCNVector3(0, 14, 18)

        // Warm key light + cool purple fill.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1250
        sun.light?.color = UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1)
        // THERMAL BASELINE: real-time shadow casting OFF. A 2048² shadow map was
        // re-rendering every frame as the props/gates moved — a major GPU cost.
        // The baked-AO vignette over the fairway still grounds the scene. Flip
        // castsShadow back to true (and keep the tuned map/radius below) to
        // restore dynamic shadows once thermals are confirmed acceptable.
        sun.light?.castsShadow = false
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

    /// Round 2: assemble the Tiki Jungle Adventure course and frame the camera.
    /// The course module owns its own geometry, lights, hole, and hazards.
    private func buildTikiWorld() {
        let course = TikiJungleCourse()
        hazardCourse = course
        holeCenter = course.holeCenter
        installCourseEnvironment(background: UIColor(red: 0.55, green: 0.83, blue: 0.6, alpha: 1),
                                 cameraPos: SCNVector3(0, 30, 30), lookAt: SCNVector3(0, 0, -2),
                                 followOffset: SCNVector3(0, 14, 19))
        scene.rootNode.addChildNode(course.root)
        spawnCoins(at: course.coinPositions)
    }

    /// Round 3: assemble the long, straight Tiki Runway gauntlet.
    private func buildRunwayWorld() {
        let course = TikiRunwayCourse()
        hazardCourse = course
        holeCenter = course.holeCenter
        // The runway is long and narrow — pull the camera back and higher to frame
        // the whole lane from the tee to the finish.
        installCourseEnvironment(background: UIColor(red: 0.20, green: 0.42, blue: 0.62, alpha: 1),
                                 cameraPos: SCNVector3(0, 40, 34), lookAt: SCNVector3(0, 0, -4),
                                 followOffset: SCNVector3(0, 14, 22))
        scene.rootNode.addChildNode(course.root)
        spawnCoins(at: course.coinPositions)
    }

    /// Shared sky/gravity/contacts/camera setup for the Tiki course modules.
    private func installCourseEnvironment(background: UIColor, cameraPos: SCNVector3, lookAt: SCNVector3,
                                          followOffset: SCNVector3 = SCNVector3(0, 14, 20)) {
        scene.background.contents = background
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        scene.physicsWorld.contactDelegate = self
        scene.fogColor = UIColor(red: 0.5, green: 0.72, blue: 0.62, alpha: 1)
        scene.fogStartDistance = 80
        scene.fogEndDistance = 180

        let camera = SCNCamera()
        camera.fieldOfView = 52
        camera.zFar = 360
        #if !targetEnvironment(simulator)
        if useHDR {
            camera.wantsHDR = true
            camera.bloomIntensity = 0.6
            camera.bloomThreshold = 0.6
        }
        #endif
        cameraNode.camera = camera
        cameraNode.position = cameraPos
        let lookTarget = SCNNode()
        lookTarget.position = lookAt
        scene.rootNode.addChildNode(lookTarget)
        let look = SCNLookAtConstraint(target: lookTarget)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)
        lookTargetNode = lookTarget
        cameraFollowOffset = followOffset
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
            // Spread the field across the active map's tee, so Round 2 spawns
            // cleanly at the Tiki tee instead of the Guerilla pad.
            let teeBase = hazardCourse?.teePosition ?? SCNVector3(0, 0.8, 15)
            let tee = SCNVector3(teeBase.x + Float(index) * 1.1 - Float(count - 1) * 0.55,
                                 teeBase.y, teeBase.z)
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
            // collisionBitMask = all bits, so the ball physically collides with
            // EVERY layer — the static floor/walls/bumpers (category 1<<1), the
            // kinematic paddle (1<<0), and other balls (ballCategory). This is
            // what keeps the ball ON the floor.
            // contactTestBitMask = ballCategory only, so the contact delegate
            // fires for ball↔ball alone (the floor no longer spams it).
            body.categoryBitMask = Self.ballCategory
            // Collide with every layer EXCEPT coins — coins are contact-only
            // triggers the ball rolls straight through (no deflection).
            body.collisionBitMask = ~Self.coinCategory
            body.contactTestBitMask = Self.ballCategory
            // Never let the body sleep. A sleeping body caches a stale transform
            // and, on the wake-up impulse, re-solves its matrices a frame behind —
            // the harsh launch snap/rubber-band. Staying active keeps its transform
            // continuously synced so the shot launches clean. (Root-cause fix)
            body.allowsResting = false
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
              let ball = balls[playerId], !ball.sunk, !ball.respawning,
              let body = ball.node.physicsBody else { return }

        // Clean launch sequence in strict order. No resetTransform() here — that
        // hard re-anchor is what snapped/rubber-banded the ball; the body is kept
        // awake (allowsResting = false) so its transform is already current and
        // needs no forced sync. (Requirements 1 & 2)
        //
        // a) kill all motion so the shot launches from a true zero state
        body.clearAllForces()
        body.velocity = SCNVector3Zero
        body.angularVelocity = SCNVector4Zero
        // b) confirm the model node sits exactly at the live ball position. These
        //    are already equal (locked at settle + never-sleeping body), so this
        //    is a no-op in value — it cannot pull the ball toward the old tee.
        ball.node.position = ball.node.presentation.position

        let p = min(1.0, max(0.0, power))
        let factor: Float = ball.info.anviled ? 0.7 : 1.0 // the Heavy Anvil at work
        let dir = groundDirection(angle) // already flat (y = 0)
        let horizontal = Float(5.0 + 14.0 * p) * factor

        // c) apply the launch impulse — STRICTLY HORIZONTAL. The Y-component is
        //    locked to 0 so the ball never lifts/jumps off the slab; it stays flush
        //    and glued to the fairway. (Also zero any residual vertical velocity so
        //    the shot starts perfectly on-plane.) No squash SCNAction: animating the
        //    physics node fought the solver and yanked the ball mid-launch.
        body.velocity = SCNVector3(body.velocity.x, 0, body.velocity.z)
        body.applyForce(
            SCNVector3(dir.x * horizontal, 0, dir.z * horizontal),
            asImpulse: true
        )

        let now = CACurrentMediaTime()
        shotPhase = .settling
        settleMinTime = now + 1.3
        settleMaxTime = now + 6.5 // safety cap; stricter rest check needs a touch longer
        // Immediately lock every phone's controls for the duration of the shot.
        reportProgress()
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
        // While the table is settling we report NO active turn, so every phone
        // locks its shooting controls until the world is fully at rest. The next
        // shooter is only announced once advanceTurn flips back to .waitingForShot.
        // (Requirements 2 & 3)
        let turn = (shotPhase == .settling) ? nil : currentTurnId
        let sunk = sunkOrder
        DispatchQueue.main.async { [onProgress] in
            onProgress(turn, sunk)
        }
    }

    /// True only when EVERY active ball has come to a complete stop (velocity ≈ 0).
    private func allBallsSettled() -> Bool {
        for ball in balls.values where !ball.sunk && !ball.respawning {
            let v = ball.node.physicsBody?.velocity ?? SCNVector3Zero
            if sqrt(v.x * v.x + v.y * v.y + v.z * v.z) > restSpeed { return false }
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
            let resting = ball.node.presentation.position
            ball.restingPosition = resting

            // CRUCIAL FIX (turn-activation teleport): during the physics
            // simulation SceneKit only moves the PRESENTATION node — the model
            // node still holds the spawn/tee position it was created at. The ball
            // *looks* settled, but the next SCNAction on it (the launch squash) or
            // any transform refresh snaps it back to that stale tee the instant
            // the player shoots again. Write the simulated rest position back onto
            // the model node and re-anchor the body so the lie is the single
            // source of truth and never reverts to spawn.
            ball.node.position = resting
            // Lock the lie in: kill any residual motion so the ball can't creep
            // off its resting spot after the turn advances. (Requirements 1 & 3)
            ball.node.physicsBody?.velocity = SCNVector3Zero
            ball.node.physicsBody?.angularVelocity = SCNVector4Zero
            ball.node.physicsBody?.resetTransform()
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
            ball.trail.birthRate = 0 // launch/roll particle splash disabled (per design)

            // Tiki hazards. Sand drastically increases linear damping while the
            // ball is inside the bunker; restore the default once it rolls out.
            if let hz = hazardCourse {
                ball.node.physicsBody?.damping = hz.isOverSand(p) ? 0.85 : 0.16
            }

            let horizontalDist = sqrt(pow(p.x - holeCenter.x, 2) + pow(p.z - holeCenter.z, 2))
            if horizontalDist < 0.8, p.y < 1.4, speed < 5.5 {
                ball.sunk = true
                balls[id] = ball
                sunkOrder.append(id)
                // Sink celebration particle splash removed (per design).
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

            // Reset-to-tee paths: the ball dropped off the platform, OR (Tiki) it
            // landed in the hippo water pool. A ball resting safely on the fairway
            // never enters this branch.
            let inWater = hazardCourse?.isOverWater(p) ?? false
            if (p.y < outOfBoundsY || inWater), !ball.respawning {
                ball.respawning = true
                balls[id] = ball
                ball.node.runAction(.sequence([
                    .fadeOpacity(to: 0, duration: 0.1),
                    .wait(duration: 0.8),
                    .run { [weak self] node in
                        guard let self, var b = self.balls[id] else { return }
                        // CHANGED (Objective 1 update): an out-of-world ball
                        // resets ALL the way back to its original tee — not its
                        // last resting lie — no matter how far it had progressed.
                        // 1) Fully reset physics so it doesn't keep falling on
                        //    respawn (clear forces + zero linear & angular vel).
                        node.physicsBody?.clearAllForces()
                        node.physicsBody?.velocity = SCNVector3Zero
                        node.physicsBody?.angularVelocity = SCNVector4Zero
                        // 2) Teleport to the original spawn. The tee (y≈0.8) sits
                        //    safely above the fairway surface, so it drops onto
                        //    the collider rather than clipping through it.
                        node.position = b.tee
                        node.physicsBody?.resetTransform()
                        // 3) Re-sync the saved lie to the tee so the player's next
                        //    stroke registers from the start, not the old position.
                        b.restingPosition = b.tee
                        b.respawning = false
                        self.balls[id] = b
                    },
                    .fadeOpacity(to: 1, duration: 0.2),
                ]))
            }
        }

        updateFollowCamera()

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

    /// Smoothly trail the active shooter's ball: lerp the camera toward
    /// ball + offset and the look-target toward the ball, every frame, so the
    /// player always sees where the shot is going without any hard cuts.
    private func updateFollowCamera() {
        guard let look = lookTargetNode,
              let id = currentTurnId, let ball = balls[id], !ball.sunk else { return }
        let bp = ball.node.presentation.position
        let desiredCam = SCNVector3(bp.x + cameraFollowOffset.x,
                                    bp.y + cameraFollowOffset.y,
                                    bp.z + cameraFollowOffset.z)
        let lookAt = SCNVector3(bp.x + cameraLookOffset.x, bp.y + cameraLookOffset.y, bp.z + cameraLookOffset.z)
        cameraNode.position = mix(cameraNode.position, desiredCam, 0.06)
        look.position = mix(look.position, lookAt, 0.1)
    }

    private func mix(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
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
        let nameA = contact.nodeA.name
        let nameB = contact.nodeB.name

        // Coin pickup: one node is a coin ("coin-…"), the other an active ball.
        // The collecting player IS the ball's owner (node name == player id).
        if let coinId = nameA, coinId.hasPrefix("coin-"), let p = nameB, ballIds.contains(p) {
            enqueue { s in s.collectCoinLocally(coinId: coinId, by: p) }
            return
        }
        if let coinId = nameB, coinId.hasPrefix("coin-"), let p = nameA, ballIds.contains(p) {
            enqueue { s in s.collectCoinLocally(coinId: coinId, by: p) }
            return
        }

        // Ball-ball only — reject ball↔course/bumper contacts.
        guard let a = nameA, ballIds.contains(a),
              let b = nameB, ballIds.contains(b) else { return }
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

    /// Render-thread coin pickup: animate the coin out locally, then report it to
    /// the server (which removes it globally and credits the collector). The
    /// `coins` registry guard makes a burst of contacts collect a coin only once.
    private func collectCoinLocally(coinId: String, by playerId: String) {
        guard let node = coins.removeValue(forKey: coinId) else { return } // already grabbed
        node.physicsBody = nil
        let point = node.presentation.position
        node.runAction(.sequence([
            .group([
                .scale(to: 0.01, duration: 0.28),
                .moveBy(x: 0, y: 1.4, z: 0, duration: 0.28),
                .fadeOut(duration: 0.28),
            ]),
            .removeFromParentNode(),
        ]))
        spawnCollisionSpark(at: point, strength: 0.5) // a little golden pop
        DispatchQueue.main.async { [onCollectCoin] in onCollectCoin(coinId, playerId) }
    }
}
