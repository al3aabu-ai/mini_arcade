import SwiftUI
import SceneKit

/// Tiki Snake — Round 4, built from the "minigolf_hole11_tiki_snake" blueprint.
///
/// An extreme winding serpentine bridge enclosed by bamboo rails, surrounded by
/// open water. Per the clip-free standard it is built on ONE thick seamless slab
/// (top at y = 0): the slab is the physics floor everywhere, the snake PATH is a
/// green decal corridor marked by rails, and everything off the corridor reads as
/// water — `isOverWater` returns true there, so a ball knocked over a rail resets
/// to the circular START tee. Conforms to `GolfHazardCourse`.
final class TikiSnakeCourse: GolfHazardCourse {

    enum Category {            // collisionBitMask is always -1 (see body helpers)
        static let fairway = 1 << 3
        static let wall    = 1 << 4
        static let blade   = 1 << 6
        static let gate    = 1 << 7
    }

    @MainActor static var title: String { Localization.shared.tr("Tiki Snake") }

    let teePosition = SCNVector3(0, 1.0, 16)
    let holeCenter = SCNVector3(0, 0.2, -17)

    /// The serpentine corridor as axis-aligned rectangles (the half-width is baked
    /// in). The ball is "on the bridge" inside any of these; everywhere else is water.
    private struct Seg { let xMin, xMax, zMin, zMax: Float }
    private let segments: [Seg] = [
        Seg(xMin: -2.3, xMax: 2.3,  zMin: 8,    zMax: 18),    // S1 start (vertical)
        Seg(xMin: -2.3, xMax: 6.3,  zMin: 4,    zMax: 8.6),   // S2 → right
        Seg(xMin: 2.3,  xMax: 6.3,  zMin: -4,   zMax: 5),     // S3 up (right)
        Seg(xMin: -6.3, xMax: 6.3,  zMin: -8.6, zMax: -4),    // S4 ← left (middle straight)
        Seg(xMin: -6.3, xMax: -2.3, zMin: -15,  zMax: -8),    // S5 up (left)
        Seg(xMin: -6.3, xMax: 2.3,  zMin: -19.6, zMax: -14.6),// S6 → right to green
    ]

    let root = SCNNode()
    let fairwayNode = SCNNode()
    let railsNode = SCNNode()
    let totemsNode = SCNNode()
    let propellerNode = SCNNode()
    let spikesNode = SCNNode()
    let malletNode = SCNNode()
    let sceneryNode = SCNNode()

    init() {
        root.name = "TikiSnakeCourse"
        for g in [fairwayNode, railsNode, totemsNode, propellerNode, spikesNode, malletNode, sceneryNode] {
            root.addChildNode(g)
        }
        buildBaseAndWater()
        buildPathAndRails()
        buildTeePad()
        buildSlidingTotems()
        buildPropeller()
        buildSpikes()
        buildFinalMallet()
        buildGreenAndHole()
        buildLighting()
    }

    // MARK: - Hazard queries

    /// On the snake bridge inside any corridor segment; otherwise it's in the water.
    func isOverWater(_ p: SCNVector3) -> Bool {
        for s in segments {
            if p.x >= s.xMin - 0.2, p.x <= s.xMax + 0.2, p.z >= s.zMin - 0.2, p.z <= s.zMax + 0.2 {
                return false
            }
        }
        return true
    }

    func isOverSand(_ p: SCNVector3) -> Bool { false }

    // MARK: - Materials / bodies

    private func pbr(_ contents: Any, roughness: CGFloat = 0.85,
                     emissive: UIColor? = nil, tile: (Float, Float)? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = roughness
        m.metalness.contents = 0
        if let emissive { m.emission.contents = emissive }
        if let tile {
            m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(tile.0, tile.1, 1)
        }
        return m
    }

    private func staticBody(_ category: Int, friction: CGFloat = 0.6, restitution: CGFloat = 0.5) -> SCNPhysicsBody {
        let b = SCNPhysicsBody(type: .static, shape: nil)
        b.friction = friction; b.restitution = restitution
        b.categoryBitMask = category; b.collisionBitMask = -1 // catch the ball whatever its category
        return b
    }

    private func kinematicBody(_ category: Int, shape: SCNGeometry, restitution: CGFloat = 1.1) -> SCNPhysicsBody {
        let b = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: shape))
        b.restitution = restitution
        b.categoryBitMask = category; b.collisionBitMask = -1
        return b
    }

    // MARK: - 1. Seamless slab + surrounding water

    private func buildBaseAndWater() {
        // ONE thick slab is the floor everywhere (top at y = 0). Its surface reads
        // as the lagoon; the snake bridge is painted on top as green decals.
        let slab = SCNBox(width: 20, height: 3, length: 44, chamferRadius: 0.2)
        let top = pbr(SnakeTex.water(), roughness: 0.25, tile: (4, 9))
        let side = pbr(UIColor(red: 0.16, green: 0.30, blue: 0.42, alpha: 1), roughness: 0.9)
        slab.materials = [side, side, side, side, top, side]
        let node = SCNNode(geometry: slab)
        node.position = SCNVector3(0, -1.5, -1)
        node.physicsBody = staticBody(Category.fairway, friction: 0.95, restitution: 0.2)
        node.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.04, z: 0, duration: 1.8), .moveBy(x: 0, y: -0.04, z: 0, duration: 1.8),
        ])))
        fairwayNode.addChildNode(node)
    }

    // MARK: - 1b. Green path decals + bamboo rails along the corridor

    private func buildPathAndRails() {
        let grass = SnakeTex.grass()
        for s in segments {
            // Green bridge-surface decal (no body — the slab is the floor).
            let w = CGFloat(s.xMax - s.xMin), l = CGFloat(s.zMax - s.zMin)
            let deck = SCNBox(width: w + 0.4, height: 0.06, length: l + 0.4, chamferRadius: 0.1)
            deck.materials = [pbr(grass, roughness: 0.9, tile: (Float(w) / 3, Float(l) / 3))]
            let d = SCNNode(geometry: deck)
            d.position = SCNVector3((s.xMin + s.xMax) / 2, 0.04, (s.zMin + s.zMax) / 2)
            fairwayNode.addChildNode(d)

            // Rails on the segment's two LONG edges (short ends stay open so the
            // corridor connects from segment to segment).
            let vertical = (s.zMax - s.zMin) >= (s.xMax - s.xMin)
            if vertical {
                addRail(x1: s.xMin, z1: s.zMin, x2: s.xMin, z2: s.zMax)
                addRail(x1: s.xMax, z1: s.zMin, x2: s.xMax, z2: s.zMax)
            } else {
                addRail(x1: s.xMin, z1: s.zMin, x2: s.xMax, z2: s.zMin)
                addRail(x1: s.xMin, z1: s.zMax, x2: s.xMax, z2: s.zMax)
            }
        }
    }

    private func addRail(x1: Float, z1: Float, x2: Float, z2: Float) {
        let dx = x2 - x1, dz = z2 - z1
        let length = sqrt(dx * dx + dz * dz)
        let rail = SCNBox(width: 0.28, height: 1.1, length: CGFloat(length), chamferRadius: 0.1)
        rail.materials = [pbr(SnakeTex.bamboo(), roughness: 0.6, tile: (1, Float(length) / 2))]
        let r = SCNNode(geometry: rail)
        r.position = SCNVector3((x1 + x2) / 2, 0.55, (z1 + z2) / 2)
        r.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
        r.physicsBody = staticBody(Category.wall)
        railsNode.addChildNode(r)
    }

    private func buildTeePad() {
        let pad = SCNCylinder(radius: 2.0, height: 0.07)
        pad.materials = [pbr(UIColor(red: 0.42, green: 0.82, blue: 0.45, alpha: 1), roughness: 0.85)]
        let p = SCNNode(geometry: pad)
        p.position = SCNVector3(teePosition.x, 0.06, teePosition.z)
        fairwayNode.addChildNode(p)
        for sx in [Float(-1), 1] {
            let torch = SCNNode(geometry: SCNSphere(radius: 0.28))
            torch.geometry?.materials = [pbr(UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1), roughness: 0.3,
                                             emissive: UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))]
            torch.position = SCNVector3(sx * 1.7, 1.2, teePosition.z + 1.5)
            torch.runAction(.repeatForever(.sequence([.scale(to: 1.18, duration: 0.4), .scale(to: 0.9, duration: 0.4)])))
            sceneryNode.addChildNode(torch)
        }
    }

    // MARK: - 2. Obstacles

    /// A & B — two Tiki totems on the curves sliding left↔right across the track.
    private func buildSlidingTotems() {
        // A: on S3 (right vertical leg); B: on S5 (left vertical leg).
        addSlidingTotem(centerX: 4.3, z: 1.0,  travel: 1.6) // slides x 2.7…5.9
        addSlidingTotem(centerX: -4.3, z: -11, travel: 1.6) // slides x -5.9…-2.7
    }

    private func addSlidingTotem(centerX: Float, z: Float, travel: Float) {
        let geo = SCNBox(width: 1.0, height: 2.4, length: 1.0, chamferRadius: 0.16)
        let totem = SCNNode(geometry: geo)
        totem.geometry?.materials = [pbr(UIColor(red: 0.4, green: 0.28, blue: 0.16, alpha: 1), roughness: 0.85)]
        totem.position = SCNVector3(centerX - travel, 1.2, z)
        totem.physicsBody = kinematicBody(Category.gate, shape: geo, restitution: 1.0)
        totem.runAction(.repeatForever(.sequence([
            .moveBy(x: CGFloat(travel * 2), y: 0, z: 0, duration: 1.1),
            .wait(duration: 0.3),
            .moveBy(x: CGFloat(-travel * 2), y: 0, z: 0, duration: 1.1),
            .wait(duration: 0.3),
        ])))
        totemsNode.addChildNode(totem)
    }

    /// C — a flat 4-blade wooden cross spinning in the centre of the middle straight.
    private func buildPropeller() {
        let center = SCNVector3(0, 0.5, -6.3) // middle of S4
        let hub = SCNNode()
        hub.position = center
        propellerNode.addChildNode(hub)

        let hubGeo = SCNCylinder(radius: 0.45, height: 0.5)
        let hubNode = SCNNode(geometry: hubGeo)
        hubNode.geometry?.materials = [pbr(UIColor(red: 0.5, green: 0.36, blue: 0.22, alpha: 1), roughness: 0.5)]
        hub.addChildNode(hubNode)

        for i in 0..<4 {
            let holder = SCNNode()
            holder.eulerAngles = SCNVector3(0, Float(i) * (.pi / 2), 0)
            let bladeGeo = SCNBox(width: 2.4, height: 0.4, length: 0.6, chamferRadius: 0.12)
            let blade = SCNNode(geometry: bladeGeo)
            blade.geometry?.materials = [pbr(SnakeTex.candy(), roughness: 0.4)]
            blade.position = SCNVector3(1.4, 0, 0)
            blade.physicsBody = kinematicBody(Category.blade, shape: bladeGeo, restitution: 1.3)
            holder.addChildNode(blade)
            hub.addChildNode(holder)
        }
        hub.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 2.6)))
    }

    /// D — a row of bamboo logs that rise out of / sink into the track in an
    /// alternating rhythm; cross when the log in your lane is down.
    private func buildSpikes() {
        let z: Float = 12 // on S1, the opening straight
        let xs: [Float] = [-1.5, -0.5, 0.5, 1.5]
        let upY: Float = 0.9, downY: Float = -1.1, period = 1.6
        for (i, x) in xs.enumerated() {
            let geo = SCNCylinder(radius: 0.26, height: 2.4)
            let log = SCNNode(geometry: geo)
            log.geometry?.materials = [pbr(SnakeTex.bamboo(), roughness: 0.6, tile: (1, 2))]
            let startUp = (i % 2 == 0)
            log.position = SCNVector3(x, startUp ? upY : downY, z)
            log.physicsBody = kinematicBody(Category.gate, shape: geo, restitution: 1.0)
            let rise = SCNAction.moveBy(x: 0, y: CGFloat(upY - downY), z: 0, duration: 0.5)
            let drop = SCNAction.moveBy(x: 0, y: CGFloat(downY - upY), z: 0, duration: 0.5)
            let cycle = SCNAction.repeatForever(.sequence([
                startUp ? drop : rise, .wait(duration: 0.3), startUp ? rise : drop, .wait(duration: 0.3),
            ]))
            // Offset alternating logs by half a period so they interleave.
            log.runAction(.sequence([.wait(duration: (i % 2 == 0) ? 0 : period / 2), cycle]))
            spikesNode.addChildNode(log)
        }
    }

    /// A large swinging mallet on the final bend, guarding the green.
    private func buildFinalMallet() {
        let pivot = SCNNode()
        pivot.position = SCNVector3(-2.0, 2.6, -15) // S5→S6 corner
        malletNode.addChildNode(pivot)

        let arm = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 1.4))
        arm.geometry?.materials = [pbr(UIColor(red: 0.5, green: 0.36, blue: 0.24, alpha: 1), roughness: 0.6)]
        arm.position = SCNVector3(0, -0.7, 0)
        pivot.addChildNode(arm)

        let headGeo = SCNBox(width: 1.5, height: 0.8, length: 0.8, chamferRadius: 0.12)
        let head = SCNNode(geometry: headGeo)
        head.geometry?.materials = [pbr(SnakeTex.stone(), roughness: 0.85)]
        head.position = SCNVector3(0, -1.5, 0)
        head.physicsBody = kinematicBody(Category.gate, shape: headGeo, restitution: 1.3)
        pivot.addChildNode(head)

        pivot.runAction(.repeatForever(.sequence([
            .wait(duration: 0.8),
            .rotateTo(x: 0, y: 0, z: -CGFloat.pi / 2.2, duration: 0.32, usesShortestUnitArc: true),
            .wait(duration: 0.4),
            .rotateTo(x: 0, y: 0, z: 0.15, duration: 0.7, usesShortestUnitArc: true),
        ])))
    }

    // MARK: - Green + hole

    private func buildGreenAndHole() {
        let green = SCNCylinder(radius: 2.6, height: 0.08)
        green.materials = [pbr(UIColor(red: 0.42, green: 0.82, blue: 0.45, alpha: 1), roughness: 0.85)]
        let g = SCNNode(geometry: green)
        g.position = SCNVector3(holeCenter.x, 0.06, holeCenter.z)
        fairwayNode.addChildNode(g)

        let cup = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.04))
        cup.geometry?.materials = [pbr(UIColor(white: 0.04, alpha: 1), roughness: 1)]
        cup.position = SCNVector3(holeCenter.x, 0.08, holeCenter.z)
        fairwayNode.addChildNode(cup)

        let pole = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 2.6))
        pole.geometry?.materials = [pbr(UIColor.white, roughness: 0.4, emissive: UIColor(white: 0.7, alpha: 1))]
        pole.position = SCNVector3(holeCenter.x, 1.3, holeCenter.z)
        sceneryNode.addChildNode(pole)

        let pennant = SCNNode(geometry: SCNPyramid(width: 0.1, height: 1.0, length: 0.55))
        pennant.geometry?.materials = [pbr(UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), roughness: 0.5)]
        pennant.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        pennant.position = SCNVector3(holeCenter.x + 0.5, 2.3, holeCenter.z)
        pennant.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0.4, z: 0, duration: 0.9), .rotateBy(x: 0, y: -0.4, z: 0, duration: 0.9),
        ])))
        sceneryNode.addChildNode(pennant)
    }

    private func buildLighting() {
        let sun = SCNNode()
        sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 1100
        sun.light?.color = UIColor(red: 1, green: 0.96, blue: 0.86, alpha: 1)
        sun.light?.castsShadow = true
        sun.eulerAngles = SCNVector3(-Float.pi / 3, 0.4, 0)
        sceneryNode.addChildNode(sun)
        let amb = SCNNode()
        amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 360
        amb.light?.color = UIColor(red: 0.5, green: 0.66, blue: 0.76, alpha: 1)
        sceneryNode.addChildNode(amb)
    }
}

// MARK: - Procedural textures

private enum SnakeTex {
    static func grass() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.34, green: 0.74, blue: 0.4, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.28, green: 0.66, blue: 0.34, alpha: 1).setFill()
            let band = s.width / 6
            for i in stride(from: 0, to: 6, by: 2) { ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: s.height)) }
        }
    }
    static func water() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.18, green: 0.42, blue: 0.66, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(white: 1, alpha: 0.12).setStroke()
            for r in 0..<6 { let y = CGFloat(r) * s.height / 6 + 12
                let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: s.width, y: y)); p.lineWidth = 4; p.stroke() }
        }
    }
    static func bamboo() -> UIImage {
        draw(128, 256) { ctx, s in
            UIColor(red: 0.78, green: 0.68, blue: 0.36, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.58, green: 0.48, blue: 0.24, alpha: 1).setStroke()
            for i in 0..<6 { let y = CGFloat(i) * s.height / 6
                let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: s.width, y: y)); p.lineWidth = 5; p.stroke() }
        }
    }
    static func candy() -> UIImage {
        draw(128) { ctx, s in
            UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1).setFill()
            let band = s.width / 5
            for i in stride(from: 0, to: 5, by: 2) { ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: s.height)) }
        }
    }
    static func stone() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.62, green: 0.6, blue: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.5, green: 0.48, blue: 0.44, alpha: 1).setFill()
            for _ in 0..<24 { let r = CGFloat.random(in: 7...20)
                ctx.fill(CGRect(x: CGFloat.random(in: 0...s.width), y: CGFloat.random(in: 0...s.height), width: r, height: r)) }
        }
    }
    private static func draw(_ w: CGFloat, _ h: CGFloat? = nil, _ body: (UIGraphicsImageRendererContext, CGSize) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h ?? w)).image { ctx in body(ctx, CGSize(width: w, height: h ?? w)) }
    }
}

// MARK: - Standalone preview (FRANTICS_DEMO=snake)

struct TikiSnakeCoursePreview: View {
    @ObservedObject private var loc = Localization.shared
    @State private var scene: SCNScene = TikiSnakeCoursePreview.makeScene()

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        let course = TikiSnakeCourse()
        scene.rootNode.addChildNode(course.root)
        scene.background.contents = UIColor(red: 0.16, green: 0.38, blue: 0.58, alpha: 1)
        let camera = SCNNode()
        camera.name = "previewCamera"
        camera.camera = SCNCamera(); camera.camera?.fieldOfView = 52; camera.camera?.zFar = 400
        camera.position = SCNVector3(0, 44, 34)
        camera.eulerAngles = SCNVector3(-0.9, 0, 0)
        scene.rootNode.addChildNode(camera)
        return scene
    }

    var body: some View {
        ZStack(alignment: .top) {
            SceneView(scene: scene,
                      pointOfView: scene.rootNode.childNode(withName: "previewCamera", recursively: false),
                      options: [.allowsCameraControl, .autoenablesDefaultLighting])
                .ignoresSafeArea()
            HStack {
                Text(TikiSnakeCourse.title).font(Theme.title(26)).foregroundStyle(.white).neonGlow(Theme.cyan, radius: 8)
                Spacer()
                Button { loc.toggle() } label: {
                    Text(loc.isArabic ? "EN" : "ع").font(Theme.title(18)).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(Circle().fill(.black.opacity(0.35)))
                }
            }.padding(20)
        }
    }
}

#Preview { TikiSnakeCoursePreview() }
