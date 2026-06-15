import SwiftUI
import SceneKit

/// Tiki Jungle Adventure — Hole 5.
///
/// A self-contained, modular SceneKit course built from the 2D map concept:
/// a winding S-curve fairway inside a bamboo fence, an elevated green at the
/// top, a sand bunker in the lower loop, a hippo water pool on the upper-left
/// bend, two stone archways, and a mallet-swinging monkey on the right.
///
/// Everything assembles under `root` as clean child groups so the level can be
/// dropped into the golf board or previewed standalone (see `TikiJungleCoursePreview`).
/// Hazard regions are exposed (`isOverWater` / `isOverSand`) for the game loop:
/// water triggers the out-of-bounds reset, sand asks the loop to spike the ball's
/// linear damping while it's inside.
final class TikiJungleCourse: GolfHazardCourse {

    /// Physics categories. Deliberately start at 1<<2 — never reuse SceneKit's
    /// reserved 1<<0 (default) / 1<<1 (static), which would make dynamic/static
    /// pairs mis-collide. Masks below are kept tight: static geometry only ever
    /// collides with the ball.
    enum Category {
        static let ball    = 1 << 2
        static let fairway = 1 << 3
        static let wall    = 1 << 4
        static let sand    = 1 << 5
        static let water   = 1 << 6
        static let mallet  = 1 << 7
    }

    // Localized identity — flips with the app's English/Arabic toggle.
    @MainActor static var title: String { Localization.shared.tr("Tiki Jungle Adventure") }
    @MainActor static var hole: String  { Localization.shared.tr("Hole 5") }
    @MainActor static var par: String   { Localization.shared.tr("Par 4 · 75 ft") }

    // MARK: modular node groups
    let root = SCNNode()
    let fairwayNode = SCNNode()
    let fenceNode = SCNNode()
    let archwaysNode = SCNNode()
    let bunkerNode = SCNNode()
    let waterHazardNode = SCNNode()
    let monkeyObstacleNode = SCNNode()
    let sceneryGroupNode = SCNNode()

    // Key world positions (xz plane; +z is the near/tee end, -z is the far green).
    // The whole course sits on ONE slab whose top surface is the y = 0 plane.
    // Spawn a full unit ABOVE the surface (ball radius is 0.42) so the ball is born
    // cleanly in mid-air and drops onto the slab — never initialized inside the
    // floor body. The ball spawns with zero velocity (allowsResting = false only
    // keeps it awake; it doesn't inject motion), so the drop is clean.
    let teePosition = SCNVector3(0, 1.0, 15.5)
    let holeCenter = SCNVector3(2.5, 0.2, -16)

    // Hazard regions for the game loop (xz centre + radius; y = surface height).
    private(set) var waterHazards: [(center: SCNVector3, radius: Float)] = []
    private(set) var sandTraps: [(center: SCNVector3, radius: Float)] = []

    init() {
        root.name = "TikiJungleCourse"
        for group in [fairwayNode, fenceNode, archwaysNode, bunkerNode,
                      waterHazardNode, monkeyObstacleNode, sceneryGroupNode] {
            root.addChildNode(group)
        }
        fairwayNode.name = "fairwayNode"
        waterHazardNode.name = "waterHazardNode"
        bunkerNode.name = "bunkerNode"
        monkeyObstacleNode.name = "monkeyObstacleNode"
        sceneryGroupNode.name = "sceneryGroupNode"

        buildFairway()
        buildGreen()
        buildFence()
        buildArchways()
        buildBunker()
        buildWaterHazard()
        buildMonkey()
        buildScenery()
        buildLighting()
    }

    // MARK: - Hazard queries (called from the physics/turn loop)

    /// A ball over the hippo pool — the caller should trigger the out-of-bounds
    /// reset back to the tee.
    func isOverWater(_ p: SCNVector3) -> Bool {
        waterHazards.contains { h in
            let dx = p.x - h.center.x, dz = p.z - h.center.z
            return sqrt(dx * dx + dz * dz) < h.radius && p.y < h.center.y + 0.6
        }
    }

    /// A ball in a sand bunker — the caller should spike the ball's linear
    /// damping while this is true to drastically slow it down.
    func isOverSand(_ p: SCNVector3) -> Bool {
        sandTraps.contains { s in
            let dx = p.x - s.center.x, dz = p.z - s.center.z
            return sqrt(dx * dx + dz * dz) < s.radius
        }
    }

    // MARK: - Materials

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

    private func staticBody(category: Int, friction: CGFloat = 0.8,
                            restitution: CGFloat = 0.3) -> SCNPhysicsBody {
        let body = SCNPhysicsBody(type: .static, shape: nil)
        body.friction = friction
        body.restitution = restitution
        body.categoryBitMask = category
        // CRITICAL: collide with ALL categories (~0). The live golf ball uses the
        // controller's own ball category, not this module's Category.ball, so a
        // restrictive mask here filtered the floor↔ball pair and the ball fell
        // straight through. Static bodies never move, so colliding with all is safe.
        body.collisionBitMask = -1
        return body
    }

    // MARK: - 1. Fairway (one seamless landmass)

    private func buildFairway() {
        // CRITICAL FIX: a SINGLE thick slab instead of overlapping rotated tiles.
        // Tiles left visual seams and overlapping collision edges the ball caught
        // on or fell between. One body means: visual top == collision top (the
        // y = 0 plane), zero internal seams, and 3 units of floor thickness so the
        // ball cannot tunnel through even at full shot speed. The S-curve now reads
        // from the fence, the hazards, and the obstacle placement.
        let span = SCNBox(width: 17, height: 3.0, length: 39, chamferRadius: 0.3)
        let top = pbr(TikiTex.grass(), roughness: 0.95, tile: (4, 9))
        let side = pbr(UIColor(red: 0.46, green: 0.33, blue: 0.20, alpha: 1), roughness: 0.95)
        let bottom = pbr(UIColor(red: 0.22, green: 0.15, blue: 0.10, alpha: 1))
        span.materials = [side, side, side, side, top, bottom] // +z +x -z -x +y -y
        let node = SCNNode(geometry: span)
        node.position = SCNVector3(0, -1.5, -1) // top surface flush at y = 0
        node.physicsBody = staticBody(category: Category.fairway, friction: 0.95, restitution: 0.2)
        fairwayNode.addChildNode(node)

        // Decorative grass lip overhanging the island edge (no physics body).
        let lip = SCNBox(width: 17.7, height: 0.26, length: 39.7, chamferRadius: 0.15)
        lip.materials = [pbr(UIColor(red: 0.26, green: 0.6, blue: 0.34, alpha: 1), roughness: 0.9)]
        let lipNode = SCNNode(geometry: lip)
        lipNode.position = SCNVector3(0, -0.12, -1)
        sceneryGroupNode.addChildNode(lipNode)
    }

    // MARK: - 1b. Green + hole (flush with the slab — no physics step)

    private func buildGreen() {
        // Felt disc that sits ON the single slab as a decal. No separate physics
        // body, so there's no lip/seam for the ball to clip on near the cup.
        let green = SCNCylinder(radius: 4.0, height: 0.08)
        green.materials = [pbr(TikiTex.greenFelt(), roughness: 0.85)]
        let greenNode = SCNNode(geometry: green)
        greenNode.position = SCNVector3(holeCenter.x, 0.05, holeCenter.z)
        sceneryGroupNode.addChildNode(greenNode)

        buildHole(at: SCNVector3(holeCenter.x, 0.0, holeCenter.z))
    }

    private func buildHole(at center: SCNVector3) {
        let cup = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.1))
        cup.geometry?.materials = [pbr(UIColor(white: 0.02, alpha: 1), roughness: 1)]
        cup.position = SCNVector3(center.x, center.y + 0.06, center.z)
        sceneryGroupNode.addChildNode(cup)

        let pole = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 2.6))
        pole.geometry?.materials = [pbr(UIColor.white, roughness: 0.4, emissive: UIColor(white: 0.7, alpha: 1))]
        pole.position = SCNVector3(center.x, center.y + 1.3, center.z)
        sceneryGroupNode.addChildNode(pole)

        let pennant = SCNNode(geometry: SCNPyramid(width: 0.1, height: 1.0, length: 0.55))
        pennant.geometry?.materials = [pbr(UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), roughness: 0.5)]
        pennant.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        pennant.position = SCNVector3(center.x + 0.5, center.y + 2.3, center.z)
        pennant.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0.4, z: 0, duration: 0.9),
            .rotateBy(x: 0, y: -0.4, z: 0, duration: 0.9),
        ])))
        sceneryGroupNode.addChildNode(pennant)
    }

    // MARK: - 1c. Bamboo fence perimeter

    private func buildFence() {
        // Boundary loop hugging the course; bamboo rails + posts between points.
        let pts: [SCNVector3] = [
            SCNVector3(-7.5, 0, 18), SCNVector3(7.5, 0, 18),
            SCNVector3(8.5, 0, -3), SCNVector3(7.5, 0, -20),
            SCNVector3(-7.5, 0, -20), SCNVector3(-8.5, 0, -3),
        ]
        for i in 0..<pts.count {
            addFenceRail(from: pts[i], to: pts[(i + 1) % pts.count])
        }
    }

    private func addFenceRail(from a: SCNVector3, to b: SCNVector3) {
        let dx = b.x - a.x, dz = b.z - a.z
        let length = sqrt(dx * dx + dz * dz)

        let rail = SCNBox(width: 0.3, height: 1.1, length: CGFloat(length), chamferRadius: 0.12)
        rail.materials = [pbr(TikiTex.bamboo(), roughness: 0.6, tile: (1, Float(length) / 2))]
        let railNode = SCNNode(geometry: rail)
        railNode.position = SCNVector3((a.x + b.x) / 2, 0.55, (a.z + b.z) / 2)
        railNode.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
        railNode.physicsBody = staticBody(category: Category.wall, friction: 0.5, restitution: 0.45)
        fenceNode.addChildNode(railNode)

        let post = SCNNode(geometry: SCNCylinder(radius: 0.24, height: 1.6))
        post.geometry?.materials = [pbr(TikiTex.bamboo(), roughness: 0.6, tile: (1, 2))]
        post.position = SCNVector3(a.x, 0.8, a.z)
        post.physicsBody = staticBody(category: Category.wall, friction: 0.5, restitution: 0.45)
        fenceNode.addChildNode(post)
    }

    // MARK: - 2c. Stone archways

    private func buildArchways() {
        addArch(at: SCNVector3(0, 0, 11), yaw: 0)        // near the tee/start
        addArch(at: SCNVector3(1.5, 0, -12.5), yaw: 0)   // green entrance
    }

    private func addArch(at position: SCNVector3, yaw: Float) {
        let group = SCNNode()
        group.position = position
        group.eulerAngles = SCNVector3(0, yaw, 0)
        let stone = TikiTex.stone()

        for x in [Float(-2.0), 2.0] {
            let pillar = SCNBox(width: 1.0, height: 3.4, length: 1.0, chamferRadius: 0.12)
            pillar.materials = [pbr(stone, roughness: 0.9)]
            let pillarNode = SCNNode(geometry: pillar)
            pillarNode.position = SCNVector3(x, 1.7, 0)
            pillarNode.physicsBody = staticBody(category: Category.wall, friction: 0.6, restitution: 0.4)
            group.addChildNode(pillarNode)
        }
        // Lintel across the top — leaves a ~3-unit gap the ball threads through.
        let lintel = SCNBox(width: 5.0, height: 1.0, length: 1.3, chamferRadius: 0.12)
        lintel.materials = [pbr(stone, roughness: 0.9)]
        let lintelNode = SCNNode(geometry: lintel)
        lintelNode.position = SCNVector3(0, 3.7, 0)
        lintelNode.physicsBody = staticBody(category: Category.wall, friction: 0.6, restitution: 0.4)
        group.addChildNode(lintelNode)

        archwaysNode.addChildNode(group)
    }

    // MARK: - 2a. Sand bunker

    private func buildBunker() {
        let center = SCNVector3(2.0, 0, 4.0) // lower-central loop
        let radius: Float = 2.4
        let disc = SCNCylinder(radius: CGFloat(radius), height: 0.05)
        disc.materials = [pbr(TikiTex.sand(), roughness: 1.0, tile: (2, 2))]
        let node = SCNNode(geometry: disc)
        node.position = SCNVector3(center.x, 0.04, center.z)
        // Pure decal — NO physics body (a raised bunker body was a collision seam).
        // The slow-down is the game loop spiking the ball's linear damping while
        // isOverSand(...) is true, so the ball just rolls flat over the slab.
        bunkerNode.addChildNode(node)
        sandTraps.append((center: SCNVector3(center.x, 0, center.z), radius: radius))
    }

    // MARK: - 2b. Water hazard (hippo pool)

    private func buildWaterHazard() {
        let center = SCNVector3(-4.0, 0, -6.0) // upper-left bend
        let radius: Float = 3.0

        let pool = SCNCylinder(radius: CGFloat(radius), height: 0.25)
        let waterMat = pbr(TikiTex.water(), roughness: 0.2)
        waterMat.transparency = 0.9
        pool.materials = [waterMat]
        let poolNode = SCNNode(geometry: pool)
        // Decal resting ON the slab (no collision body). A ball that rolls over
        // it is caught by the loop's isOverWater check, which fires the OOB reset.
        poolNode.position = SCNVector3(center.x, 0.05, center.z)
        poolNode.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.03, z: 0, duration: 1.6),
            .moveBy(x: 0, y: -0.03, z: 0, duration: 1.6),
        ])))
        waterHazardNode.addChildNode(poolNode)

        addHippo(at: SCNVector3(center.x, 0.25, center.z))
        waterHazards.append((center: SCNVector3(center.x, 0, center.z), radius: radius))
    }

    private func addHippo(at position: SCNVector3) {
        let hippo = SCNNode()
        hippo.position = position
        let skin = pbr(UIColor(red: 0.55, green: 0.45, blue: 0.62, alpha: 1), roughness: 0.7)

        let body = SCNNode(geometry: SCNSphere(radius: 0.95))
        body.scale = SCNVector3(1.3, 0.7, 1.0)
        body.geometry?.materials = [skin]
        hippo.addChildNode(body)

        for x in [Float(-0.4), 0.4] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.16))
            eye.geometry?.materials = [pbr(UIColor.white, roughness: 0.3)]
            eye.position = SCNVector3(x, 0.45, 0.55)
            hippo.addChildNode(eye)
            let ear = SCNNode(geometry: SCNSphere(radius: 0.18))
            ear.geometry?.materials = [skin]
            ear.position = SCNVector3(x, 0.7, -0.2)
            hippo.addChildNode(ear)
        }
        // Lazy bob in the water.
        hippo.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.12, z: 0, duration: 1.8),
            .moveBy(x: 0, y: -0.12, z: 0, duration: 1.8),
        ])))
        waterHazardNode.addChildNode(hippo)
    }

    // MARK: - 3. Mallet monkey (dynamic timing hazard)

    private func buildMonkey() {
        monkeyObstacleNode.position = SCNVector3(5.5, 0, -8.0) // right side, before the green

        let pedestal = SCNNode(geometry: SCNBox(width: 1.8, height: 1.8, length: 1.8, chamferRadius: 0.2))
        pedestal.geometry?.materials = [pbr(TikiTex.stone(), roughness: 0.9)]
        pedestal.position = SCNVector3(0, 0.9, 0)
        pedestal.physicsBody = staticBody(category: Category.wall, friction: 0.6, restitution: 0.4)
        monkeyObstacleNode.addChildNode(pedestal)

        let fur = pbr(UIColor(red: 0.5, green: 0.36, blue: 0.24, alpha: 1), roughness: 0.8)
        let monkey = SCNNode()
        monkey.position = SCNVector3(0, 2.0, 0)
        let torso = SCNNode(geometry: SCNSphere(radius: 0.6)); torso.geometry?.materials = [fur]
        monkey.addChildNode(torso)
        let head = SCNNode(geometry: SCNSphere(radius: 0.45)); head.geometry?.materials = [fur]
        head.position = SCNVector3(0, 0.75, 0)
        monkey.addChildNode(head)
        for x in [Float(-0.42), 0.42] {
            let ear = SCNNode(geometry: SCNSphere(radius: 0.16)); ear.geometry?.materials = [fur]
            ear.position = SCNVector3(x, 0.95, 0)
            monkey.addChildNode(ear)
        }
        monkeyObstacleNode.addChildNode(monkey)

        // Swing rig: a pivot at the shoulder; rotating it about Z sweeps the arm +
        // mallet sideways across the fairway path to the monkey's left.
        let swingPivot = SCNNode()
        swingPivot.position = SCNVector3(0, 2.6, 0)

        let arm = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 1.4))
        arm.geometry?.materials = [fur]
        arm.position = SCNVector3(0, -0.7, 0)
        swingPivot.addChildNode(arm)

        let mallet = SCNNode()
        mallet.position = SCNVector3(0, -1.4, 0)
        let handle = SCNNode(geometry: SCNCylinder(radius: 0.1, height: 1.7))
        handle.geometry?.materials = [pbr(UIColor(red: 0.45, green: 0.3, blue: 0.18, alpha: 1), roughness: 0.6)]
        handle.position = SCNVector3(0, -0.85, 0)
        mallet.addChildNode(handle)

        let headGeo = SCNBox(width: 1.5, height: 0.8, length: 0.8, chamferRadius: 0.12)
        let malletHead = SCNNode(geometry: headGeo)
        malletHead.geometry?.materials = [pbr(TikiTex.stone(), roughness: 0.85)]
        malletHead.position = SCNVector3(0, -1.7, 0)
        // Kinematic so the swing animation physically shoves any ball it meets.
        let mBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: headGeo))
        mBody.categoryBitMask = Category.mallet
        mBody.collisionBitMask = -1 // deflect the live ball regardless of its category
        mBody.restitution = 1.1 // a satisfying whack
        malletHead.physicsBody = mBody
        mallet.addChildNode(malletHead)
        swingPivot.addChildNode(mallet)
        monkeyObstacleNode.addChildNode(swingPivot)

        // Looping timing hazard: rest up, SLAM down across the path, hold, lift.
        let swing = SCNAction.sequence([
            .wait(duration: 1.2),
            .rotateTo(x: 0, y: 0, z: -CGFloat.pi / 2.1, duration: 0.3, usesShortestUnitArc: true), // slam across
            .wait(duration: 0.4),
            .rotateTo(x: 0, y: 0, z: 0.15, duration: 0.7, usesShortestUnitArc: true),         // wind back up
        ])
        swingPivot.runAction(.repeatForever(swing))
    }

    // MARK: - Scenery & lighting

    private func buildScenery() {
        let palmSpots: [SCNVector3] = [
            SCNVector3(-6.5, 0, 16), SCNVector3(6.5, 0, 16),
            SCNVector3(-6.8, 0, -17), SCNVector3(6.5, 0, -2),
        ]
        for (i, spot) in palmSpots.enumerated() {
            addPalm(at: spot, tint: i % 2 == 0 ? UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)
                                              : UIColor(red: 0.16, green: 0.62, blue: 0.34, alpha: 1))
        }
        // A couple of tiki totems flanking the tee.
        for x in [Float(-6), 6] {
            let totem = SCNNode(geometry: SCNBox(width: 1.0, height: 2.6, length: 1.0, chamferRadius: 0.18))
            totem.geometry?.materials = [pbr(TikiTex.bamboo(), roughness: 0.8)]
            totem.position = SCNVector3(x, 1.3, 13)
            sceneryGroupNode.addChildNode(totem)
            let face = SCNNode(geometry: SCNBox(width: 0.7, height: 0.7, length: 0.2, chamferRadius: 0.1))
            face.geometry?.materials = [pbr(UIColor(red: 0.4, green: 0.28, blue: 0.16, alpha: 1), roughness: 0.9)]
            face.position = SCNVector3(x, 1.7, 13.55)
            sceneryGroupNode.addChildNode(face)
        }
    }

    private func addPalm(at position: SCNVector3, tint: UIColor) {
        let palm = SCNNode()
        palm.position = position
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.18, height: 2.6))
        trunk.geometry?.materials = [pbr(TikiTex.bamboo(), roughness: 0.9, tile: (1, 2))]
        trunk.position = SCNVector3(0, 1.3, 0)
        palm.addChildNode(trunk)
        for i in 0..<3 {
            let frond = SCNNode(geometry: SCNCone(topRadius: 0.02,
                                                  bottomRadius: CGFloat(1.4 - Double(i) * 0.32),
                                                  height: 0.9))
            frond.geometry?.materials = [pbr(tint, roughness: 0.8)]
            frond.position = SCNVector3(0.16, 2.6 + Float(i) * 0.5, 0)
            palm.addChildNode(frond)
        }
        sceneryGroupNode.addChildNode(palm)
    }

    private func buildLighting() {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
        sun.light?.castsShadow = true
        sun.eulerAngles = SCNVector3(-Float.pi / 3, 0.5, 0)
        sceneryGroupNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 360
        ambient.light?.color = UIColor(red: 0.6, green: 0.75, blue: 0.65, alpha: 1)
        sceneryGroupNode.addChildNode(ambient)
    }
}

// MARK: - Procedural textures (no asset files)

private enum TikiTex {
    static func grass() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.33, green: 0.72, blue: 0.38, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.28, green: 0.64, blue: 0.33, alpha: 1).setFill()
            let band = s.width / 6
            for i in stride(from: 0, to: 6, by: 2) {
                ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: s.height))
            }
        }
    }
    static func greenFelt() -> UIImage {
        draw(128) { ctx, s in
            UIColor(red: 0.42, green: 0.82, blue: 0.45, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
        }
    }
    static func sand() -> UIImage {
        draw(128) { ctx, s in
            UIColor(red: 0.93, green: 0.85, blue: 0.62, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
        }
    }
    static func water() -> UIImage {
        draw(256) { ctx, s in
            UIColor(red: 0.24, green: 0.55, blue: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            UIColor(white: 1, alpha: 0.16).setStroke()
            for r in 0..<5 {
                let y = CGFloat(r) * s.height / 5 + 14
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: s.width, y: y))
                path.lineWidth = 4
                path.stroke()
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
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: s.width, y: y))
                path.lineWidth = 5
                path.stroke()
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
                ctx.fill(CGRect(x: CGFloat.random(in: 0...s.width), y: CGFloat.random(in: 0...s.height),
                                width: r, height: r))
            }
        }
    }
    private static func draw(_ w: CGFloat, _ h: CGFloat? = nil,
                             _ body: (UIGraphicsImageRendererContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: w, height: h ?? w)
        return UIGraphicsImageRenderer(size: size).image { ctx in body(ctx, size) }
    }
}

// MARK: - Standalone preview (load this in Xcode / via FRANTICS_DEMO=tiki)

/// Renders the Tiki Jungle course on its own so the layout can be inspected in
/// Xcode's canvas or on a device. Orbit with a drag; the title flips with the
/// English/Arabic toggle (top-right).
struct TikiJungleCoursePreview: View {
    @ObservedObject private var loc = Localization.shared
    @State private var scene: SCNScene = TikiJungleCoursePreview.makeScene()

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        let course = TikiJungleCourse()
        scene.rootNode.addChildNode(course.root)
        scene.background.contents = UIColor(red: 0.55, green: 0.83, blue: 0.6, alpha: 1)

        let camera = SCNNode()
        camera.name = "previewCamera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.camera?.zFar = 400
        camera.position = SCNVector3(0, 34, 30)
        camera.eulerAngles = SCNVector3(-0.82, 0, 0) // tilt down to frame the whole course
        scene.rootNode.addChildNode(camera)
        return scene
    }

    var body: some View {
        ZStack(alignment: .top) {
            SceneView(
                scene: scene,
                pointOfView: scene.rootNode.childNode(withName: "previewCamera", recursively: false),
                options: [.allowsCameraControl, .autoenablesDefaultLighting],
                preferredFramesPerSecond: GolfSceneController.targetFPS, // thermal cap (matches gameplay)
                antialiasingMode: .multisampling2X
            )
            .ignoresSafeArea()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TikiJungleCourse.title)
                        .font(Theme.title(26))
                        .foregroundStyle(.white)
                        .neonGlow(Theme.cyan, radius: 8)
                    Text("\(TikiJungleCourse.hole) · \(TikiJungleCourse.par)")
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button {
                    loc.toggle()
                } label: {
                    Text(loc.isArabic ? "EN" : "ع")
                        .font(Theme.title(18))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    TikiJungleCoursePreview()
}
