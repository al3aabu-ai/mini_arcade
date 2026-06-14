import SwiftUI
import SceneKit

/// Tiki Runway — Hole 6 / Round 3, built from the "Tiki Runway" 2D blueprint.
///
/// A long, dead-straight lane on ONE thick seamless slab (top at y = 0, so the
/// ball can't clip or sink), walled by bamboo rails with open water on both
/// sides. From the tee the ball runs a gauntlet: flanking Start Mallets → the
/// Tiki Plank Wall (thread the centre gap) → the spinning Propeller → the
/// closing Tiki Gate → the finish green/hole. Moving parts are kinematic bodies
/// driven by looping SCNActions so they physically deflect the ball.
///
/// Conforms to `GolfHazardCourse`, so `GolfSceneController` drops it in and reads
/// `teePosition` / `holeCenter` / `isOverWater` exactly like the Jungle course.
final class TikiRunwayCourse: GolfHazardCourse {

    enum Category {            // collisionBitMask is always -1 (see body helpers)
        static let fairway = 1 << 3
        static let wall    = 1 << 4
        static let water   = 1 << 5
        static let blade   = 1 << 6
        static let gate    = 1 << 7
    }

    @MainActor static var title: String { Localization.shared.tr("Tiki Runway") }

    // Lane geometry: centred on x = 0, running +Z (tee) → -Z (finish).
    private let laneHalfWidth: Float = 3.6   // rails sit here
    private let waterEdge: Float = 3.7       // beyond this x = in the water

    let teePosition = SCNVector3(0, 1.0, 18)
    let holeCenter = SCNVector3(0, 0.2, -18)

    private(set) var waterHazards: [(center: SCNVector3, radius: Float)] = [] // unused; side check below

    let root = SCNNode()
    let fairwayNode = SCNNode()
    let railsNode = SCNNode()
    let malletsNode = SCNNode()
    let plankWallNode = SCNNode()
    let propellerNode = SCNNode()
    let gateNode = SCNNode()
    let sceneryNode = SCNNode()

    init() {
        root.name = "TikiRunwayCourse"
        for g in [fairwayNode, railsNode, malletsNode, plankWallNode, propellerNode, gateNode, sceneryNode] {
            root.addChildNode(g)
        }
        buildFairwayAndWater()
        buildRails()
        buildStartMallets()
        buildPlankWall()
        buildPropeller()
        buildGate()
        buildGreenAndHole()
        buildScenery()
        buildLighting()
    }

    // MARK: - Hazard queries

    /// Flying over a rail (or being knocked sideways) lands the ball in the water
    /// to either side of the lane → out of bounds, reset to the tee.
    func isOverWater(_ p: SCNVector3) -> Bool {
        abs(p.x) > waterEdge
    }

    /// No sand on the runway.
    func isOverSand(_ p: SCNVector3) -> Bool { false }

    // MARK: - Materials / bodies

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

    private func staticBody(_ category: Int, friction: CGFloat = 0.8, restitution: CGFloat = 0.4) -> SCNPhysicsBody {
        let b = SCNPhysicsBody(type: .static, shape: nil)
        b.friction = friction
        b.restitution = restitution
        b.categoryBitMask = category
        b.collisionBitMask = -1 // collide with the live ball whatever its category
        return b
    }

    private func kinematicBody(_ category: Int, shape: SCNGeometry, restitution: CGFloat = 1.1) -> SCNPhysicsBody {
        let b = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: shape))
        b.restitution = restitution
        b.categoryBitMask = category
        b.collisionBitMask = -1
        return b
    }

    // MARK: - 1. Seamless slab + side water

    private func buildFairwayAndWater() {
        // One thick slab — the lane, top flush at y = 0, 3 units deep. It STOPS at
        // z ≈ -14.5 (the green's near edge) so the funnel hole can be carved BELOW
        // grade past it (no slab beneath the funnel to push the ball back up).
        let slab = SCNBox(width: CGFloat(laneHalfWidth * 2 + 0.8), height: 3.0, length: 36.5, chamferRadius: 0.25)
        let top = pbr(RunwayTex.grass(), roughness: 0.95, tile: (2, 9))
        let side = pbr(UIColor(red: 0.46, green: 0.33, blue: 0.20, alpha: 1), roughness: 0.95)
        let bottom = pbr(UIColor(red: 0.22, green: 0.15, blue: 0.10, alpha: 1))
        slab.materials = [side, side, side, side, top, bottom]
        let node = SCNNode(geometry: slab)
        node.position = SCNVector3(0, -1.5, 3.75) // top at y = 0; spans z ≈ +22 … -14.5
        node.physicsBody = staticBody(Category.fairway, friction: 0.95, restitution: 0.2)
        fairwayNode.addChildNode(node)

        // Open water on both sides (decals — the isOverWater check does the reset).
        for sx in [Float(-1), 1] {
            let water = SCNBox(width: 26, height: 0.2, length: 60, chamferRadius: 0)
            let m = pbr(RunwayTex.water(), roughness: 0.2)
            m.transparency = 0.92
            water.materials = [m]
            let w = SCNNode(geometry: water)
            w.position = SCNVector3(sx * (laneHalfWidth + 13), -0.25, -2)
            w.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.05, z: 0, duration: 1.7),
                .moveBy(x: 0, y: -0.05, z: 0, duration: 1.7),
            ])))
            sceneryNode.addChildNode(w)
        }
    }

    // MARK: - 1b. Bamboo side rails

    private func buildRails() {
        for sx in [Float(-1), 1] {
            let rail = SCNBox(width: 0.32, height: 1.2, length: 44, chamferRadius: 0.12)
            rail.materials = [pbr(RunwayTex.bamboo(), roughness: 0.6, tile: (1, 22))]
            let r = SCNNode(geometry: rail)
            r.position = SCNVector3(sx * laneHalfWidth, 0.6, -2)
            r.physicsBody = staticBody(Category.wall, friction: 0.5, restitution: 0.5)
            railsNode.addChildNode(r)
            // Posts every few units.
            for z in stride(from: Float(19), through: -23, by: -4) {
                let post = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 1.7))
                post.geometry?.materials = [pbr(RunwayTex.bamboo(), roughness: 0.6, tile: (1, 2))]
                post.position = SCNVector3(sx * laneHalfWidth, 0.85, z)
                post.physicsBody = staticBody(Category.wall, friction: 0.5, restitution: 0.5)
                railsNode.addChildNode(post)
            }
        }

        // End fences sealing the previously-open zones: behind the tee (+Z) and
        // behind the green (−Z), so the boundary is fully closed (no rolling off
        // the ends into the water).
        addEndFence(z: 20)    // behind the start tee
        addEndFence(z: -21.5) // behind the finish green (just past the funnel's far rim)
    }

    /// A bamboo cross-fence running the lane's full width at one end.
    private func addEndFence(z: Float) {
        let fence = SCNBox(width: CGFloat(laneHalfWidth * 2 + 0.4), height: 1.2, length: 0.32, chamferRadius: 0.12)
        fence.materials = [pbr(RunwayTex.bamboo(), roughness: 0.6, tile: (8, 1))]
        let f = SCNNode(geometry: fence)
        f.position = SCNVector3(0, 0.6, z)
        f.physicsBody = staticBody(Category.wall, friction: 0.5, restitution: 0.5)
        railsNode.addChildNode(f)
        for sx in [Float(-1), 1] {
            let post = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 1.7))
            post.geometry?.materials = [pbr(RunwayTex.bamboo(), roughness: 0.6, tile: (1, 2))]
            post.position = SCNVector3(sx * laneHalfWidth, 0.85, z)
            post.physicsBody = staticBody(Category.wall, friction: 0.5, restitution: 0.5)
            railsNode.addChildNode(post)
        }
    }

    // MARK: - 2. Gauntlet obstacles

    /// Start Mallets — two oversized mallets flanking the tee that rock inward and
    /// back, staying clear of the centre launch line. Kinematic so a wide ball
    /// gets nudged back toward the lane.
    private func buildStartMallets() {
        for sx in [Float(-1), 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(sx * 2.9, 0.2, 14)
            malletsNode.addChildNode(pivot)

            let handle = SCNNode(geometry: SCNCylinder(radius: 0.14, height: 2.2))
            handle.geometry?.materials = [pbr(UIColor(red: 0.5, green: 0.34, blue: 0.2, alpha: 1), roughness: 0.6)]
            handle.eulerAngles = SCNVector3(0, 0, Float.pi / 2) // lie flat, pointing inward
            handle.position = SCNVector3(-sx * 1.1, 0, 0)
            pivot.addChildNode(handle)

            let headGeo = SCNCylinder(radius: 0.55, height: 1.2)
            let head = SCNNode(geometry: headGeo)
            head.geometry?.materials = [pbr(UIColor(red: 0.62, green: 0.45, blue: 0.28, alpha: 1), roughness: 0.55)]
            head.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            head.position = SCNVector3(-sx * 2.2, 0, 0)
            head.physicsBody = kinematicBody(Category.gate, shape: headGeo, restitution: 1.3)
            pivot.addChildNode(head)

            // Rock inward toward the lane and back, on a gentle loop.
            let inward = -sx * 0.5
            pivot.runAction(.repeatForever(.sequence([
                .rotateTo(x: 0, y: 0, z: CGFloat(inward), duration: 0.9, usesShortestUnitArc: true),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.9, usesShortestUnitArc: true),
                .wait(duration: 0.6),
            ])))
        }
    }

    /// Obstacle 3 — Tiki Plank Wall. A barrier across the lane with a narrow
    /// centre gate to thread. Static planks.
    private func buildPlankWall() {
        let z: Float = 4
        let gateHalf: Float = 0.9 // centre opening ≈ 1.8 wide
        // Left and right plank banks, leaving the centre gap.
        for sx in [Float(-1), 1] {
            let bankInner = sx * gateHalf
            let bankOuter = sx * laneHalfWidth
            let mid = (bankInner + bankOuter) / 2
            let width = abs(bankOuter - bankInner)
            // A row of vertical bamboo planks.
            let count = 4
            for i in 0..<count {
                let x = bankInner + (bankOuter - bankInner) * (Float(i) + 0.5) / Float(count)
                let plank = SCNBox(width: CGFloat(width) / CGFloat(count) * 0.8, height: 1.3, length: 0.5, chamferRadius: 0.06)
                plank.materials = [pbr(RunwayTex.bamboo(), roughness: 0.6)]
                let p = SCNNode(geometry: plank)
                p.position = SCNVector3(x, 0.65, z)
                p.physicsBody = staticBody(Category.wall, friction: 0.5, restitution: 0.5)
                plankWallNode.addChildNode(p)
            }
            _ = mid
        }
    }

    /// Obstacle 2 — Rotating Propeller. A flat 3-blade fan spinning about Y just
    /// past the plank wall. Each blade is a kinematic body; the hub spins them via
    /// a looping rotateBy, sweeping the ball aside if mistimed.
    private func buildPropeller() {
        let z: Float = -4
        let hub = SCNNode()
        hub.position = SCNVector3(0, 0.45, z)
        propellerNode.addChildNode(hub)

        let hubGeo = SCNCylinder(radius: 0.5, height: 0.5)
        let hubNode = SCNNode(geometry: hubGeo)
        hubNode.geometry?.materials = [pbr(UIColor(red: 0.55, green: 0.4, blue: 0.26, alpha: 1), roughness: 0.5)]
        hub.addChildNode(hubNode)

        for i in 0..<3 {
            let angle = Float(i) * (2 * Float.pi / 3)
            let bladeGeo = SCNBox(width: 2.6, height: 0.4, length: 0.7, chamferRadius: 0.15)
            let blade = SCNNode(geometry: bladeGeo)
            blade.geometry?.materials = [pbr(RunwayTex.candy(), roughness: 0.4)]
            // Offset the blade so it radiates from the hub, then spin the whole hub.
            let bladeHolder = SCNNode()
            bladeHolder.eulerAngles = SCNVector3(0, angle, 0)
            blade.position = SCNVector3(1.5, 0, 0)
            blade.physicsBody = kinematicBody(Category.blade, shape: bladeGeo, restitution: 1.4)
            bladeHolder.addChildNode(blade)
            hub.addChildNode(bladeHolder)
        }
        // Continuous spin — the timing hazard.
        hub.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 2.4)))
    }

    /// Obstacle 1 — Tiki Gate Trap. Two stone blocks that slide closed to meet in
    /// the centre, pause, then slide back open, on a loop. Kinematic.
    private func buildGate() {
        let z: Float = -12
        for sx in [Float(-1), 1] {
            let openX = sx * 2.6
            let closedX = sx * 0.85   // centre gap ≈ 1.7 when closed
            let blockGeo = SCNBox(width: 2.0, height: 2.4, length: 1.4, chamferRadius: 0.12)
            let block = SCNNode(geometry: blockGeo)
            block.geometry?.materials = [pbr(RunwayTex.stone(), roughness: 0.9)]
            block.position = SCNVector3(openX, 1.2, z)
            block.physicsBody = kinematicBody(Category.gate, shape: blockGeo, restitution: 1.0)
            gateNode.addChildNode(block)

            let slide = closedX - openX
            block.runAction(.repeatForever(.sequence([
                .wait(duration: 1.0),
                .moveBy(x: CGFloat(slide), y: 0, z: 0, duration: 0.5),  // slam closed
                .wait(duration: 1.0),
                .moveBy(x: CGFloat(-slide), y: 0, z: 0, duration: 0.6), // open back up
            ])))
        }
    }

    // MARK: - 3. Finish green + hole

    private func buildGreenAndHole() {
        // The funnel facets ARE the green surface (no flat disc — it would float
        // over the carved funnel).
        buildFunnelHole(at: SCNVector3(holeCenter.x, 0, holeCenter.z))

        let pole = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 2.6))
        pole.geometry?.materials = [pbr(UIColor.white, roughness: 0.4, emissive: UIColor(white: 0.7, alpha: 1))]
        pole.position = SCNVector3(holeCenter.x, 1.3, holeCenter.z)
        sceneryNode.addChildNode(pole)

        let pennant = SCNNode(geometry: SCNPyramid(width: 0.1, height: 1.0, length: 0.55))
        pennant.geometry?.materials = [pbr(UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), roughness: 0.5)]
        pennant.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        pennant.position = SCNVector3(holeCenter.x + 0.5, 2.3, holeCenter.z)
        pennant.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0.4, z: 0, duration: 0.9),
            .rotateBy(x: 0, y: -0.4, z: 0, duration: 0.9),
        ])))
        sceneryNode.addChildNode(pennant)
    }

    /// The green is a real concave funnel carved DOWNWARD: a ring of facet panels
    /// whose outer rim is FLUSH at y = 0 (meeting the slab and the rails) and whose
    /// inner edge dips below grade to the cup. Because the slab stops at the green's
    /// near edge, there's nothing solid beneath the funnel — the facets ARE the
    /// floor, so gravity rolls a nearby ball straight down into the hole. No raised
    /// ridge anywhere (the previous "pot" rim is gone). The rim is clamped to the
    /// lane rectangle so it fills the full width with no gaps.
    private func buildFunnelHole(at center: SCNVector3) {
        let cupR: Float = 0.7
        let cupY: Float = -0.8          // carved below grade (no slab beneath here)
        let halfX = laneHalfWidth       // rim reaches the side rails
        let halfZ: Float = 3.5          // rim reaches the slab end (+Z) and far fence (−Z)
        let facets = 28
        let feltMat = pbr(UIColor(red: 0.36, green: 0.74, blue: 0.40, alpha: 1), roughness: 0.85)
        for i in 0..<facets {
            let a = Float(i) * 2 * .pi / Float(facets)
            let dx = cos(a), dz = sin(a)
            let tX = abs(dx) > 0.001 ? halfX / abs(dx) : .greatestFiniteMagnitude
            let tZ = abs(dz) > 0.001 ? halfZ / abs(dz) : .greatestFiniteMagnitude
            let t = min(tX, tZ)
            let outer = SCNVector3(center.x + dx * t, 0, center.z + dz * t)             // flush rim
            let inner = SCNVector3(center.x + dx * cupR, cupY, center.z + dz * cupR)    // sunk cup edge
            let len = CGFloat(sqrt(pow(outer.x - inner.x, 2) + pow(outer.y - inner.y, 2) + pow(outer.z - inner.z, 2)))
            let width = CGFloat(t * 2 * .pi / Float(facets) * 1.6) // overlap so no gaps between facets
            let panel = SCNBox(width: width, height: 0.1, length: len, chamferRadius: 0.02)
            panel.materials = [feltMat]
            let node = SCNNode(geometry: panel)
            node.position = SCNVector3((inner.x + outer.x) / 2, (inner.y + outer.y) / 2, (inner.z + outer.z) / 2)
            // +Z up the slope toward the flush outer rim; the top face is the funnel.
            node.look(at: outer, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
            node.physicsBody = staticBody(Category.fairway, friction: 0.9, restitution: 0.05)
            fairwayNode.addChildNode(node)
        }
        // Dark cup pit at the bottom of the funnel.
        let cup = SCNNode(geometry: SCNCylinder(radius: CGFloat(cupR), height: 0.6))
        cup.geometry?.materials = [pbr(UIColor(white: 0.03, alpha: 1), roughness: 1)]
        cup.position = SCNVector3(center.x, cupY - 0.25, center.z)
        fairwayNode.addChildNode(cup)
    }

    // MARK: - scenery + lighting

    private func buildScenery() {
        // Tiki totems lining the rails.
        for z in stride(from: Float(12), through: -16, by: -7) {
            for sx in [Float(-1), 1] {
                let totem = SCNNode(geometry: SCNBox(width: 0.8, height: 2.2, length: 0.8, chamferRadius: 0.16))
                totem.geometry?.materials = [pbr(UIColor(red: 0.4, green: 0.28, blue: 0.16, alpha: 1), roughness: 0.85)]
                totem.position = SCNVector3(sx * (laneHalfWidth - 0.5), 1.1, z)
                sceneryNode.addChildNode(totem)
            }
        }
        // Start torches.
        for sx in [Float(-1), 1] {
            let torch = SCNNode(geometry: SCNSphere(radius: 0.3))
            torch.geometry?.materials = [pbr(UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1), roughness: 0.3,
                                              emissive: UIColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1))]
            torch.position = SCNVector3(sx * 2.6, 1.4, 19.5)
            torch.runAction(.repeatForever(.sequence([
                .scale(to: 1.18, duration: 0.4), .scale(to: 0.9, duration: 0.4),
            ])))
            sceneryNode.addChildNode(torch)
        }
    }

    private func buildLighting() {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
        sun.light?.castsShadow = true
        sun.eulerAngles = SCNVector3(-Float.pi / 3, 0.4, 0)
        sceneryNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 360
        ambient.light?.color = UIColor(red: 0.55, green: 0.68, blue: 0.75, alpha: 1)
        sceneryNode.addChildNode(ambient)
    }
}

// MARK: - Procedural textures

private enum RunwayTex {
    static func grass() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.33, green: 0.72, blue: 0.38, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.28, green: 0.64, blue: 0.33, alpha: 1).setFill()
            let band = s.height / 8
            for i in stride(from: 0, to: 8, by: 2) {
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * band, width: s.width, height: band))
            }
        }
    }
    static func water() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.20, green: 0.45, blue: 0.7, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(white: 1, alpha: 0.14).setStroke()
            for r in 0..<6 {
                let y = CGFloat(r) * s.height / 6 + 12
                let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: s.width, y: y))
                p.lineWidth = 4; p.stroke()
            }
        }
    }
    static func bamboo() -> UIImage {
        draw(128, 256) { ctx, s in
            UIColor(red: 0.78, green: 0.68, blue: 0.36, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.58, green: 0.48, blue: 0.24, alpha: 1).setStroke()
            for i in 0..<6 {
                let y = CGFloat(i) * s.height / 6
                let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: s.width, y: y))
                p.lineWidth = 5; p.stroke()
            }
        }
    }
    static func candy() -> UIImage {
        draw(128) { ctx, s in
            UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1).setFill()
            let band = s.width / 5
            for i in stride(from: 0, to: 5, by: 2) {
                ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: s.height))
            }
        }
    }
    static func stone() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.62, green: 0.6, blue: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.5, green: 0.48, blue: 0.44, alpha: 1).setFill()
            for _ in 0..<26 {
                let r = CGFloat.random(in: 7...22)
                ctx.fill(CGRect(x: CGFloat.random(in: 0...s.width), y: CGFloat.random(in: 0...s.height), width: r, height: r))
            }
        }
    }
    private static func draw(_ w: CGFloat, _ h: CGFloat? = nil,
                             _ body: (UIGraphicsImageRendererContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: w, height: h ?? w)
        return UIGraphicsImageRenderer(size: size).image { ctx in body(ctx, size) }
    }
}

// MARK: - Standalone preview (FRANTICS_DEMO=runway)

struct TikiRunwayCoursePreview: View {
    @ObservedObject private var loc = Localization.shared
    @State private var scene: SCNScene = TikiRunwayCoursePreview.makeScene()

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        let course = TikiRunwayCourse()
        scene.rootNode.addChildNode(course.root)
        scene.background.contents = UIColor(red: 0.20, green: 0.42, blue: 0.62, alpha: 1)

        let camera = SCNNode()
        camera.name = "previewCamera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 52
        camera.camera?.zFar = 400
        camera.position = SCNVector3(0, 40, 34)
        camera.eulerAngles = SCNVector3(-0.85, 0, 0)
        scene.rootNode.addChildNode(camera)
        return scene
    }

    var body: some View {
        ZStack(alignment: .top) {
            SceneView(
                scene: scene,
                pointOfView: scene.rootNode.childNode(withName: "previewCamera", recursively: false),
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .ignoresSafeArea()

            HStack {
                Text(TikiRunwayCourse.title)
                    .font(Theme.title(26))
                    .foregroundStyle(.white)
                    .neonGlow(Theme.cyan, radius: 8)
                Spacer()
                Button { loc.toggle() } label: {
                    Text(loc.isArabic ? "EN" : "ع")
                        .font(Theme.title(18)).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(Circle().fill(.black.opacity(0.35)))
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    TikiRunwayCoursePreview()
}
