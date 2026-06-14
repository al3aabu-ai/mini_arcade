# Tiki Jungle Adventure — Unity port

Port of the SceneKit `TikiJungleCourse` (Hole 5) to Unity / C#. This folder holds
**only the scripts** — drop them into a Unity project's `Assets/` and follow the
setup below. The SceneKit version is untouched and preserved on the
`scenekit-stable-backup` branch / `scenekit-stable` tag.

## Scripts (`Assets/Scripts/`)

| Script | Role |
|---|---|
| `TikiJungleCourse.cs` | Procedural builder — assembles the whole hole at `Awake()` into modular child groups, spawns the ball, wires hazards. Mirrors the Swift builder. |
| `GolfBall.cs` | Ball marker/controller: `ResetToSpawn()`, `EnterSand()/ExitSand()`. Hazards talk to this. |
| `SandBunker.cs` | Trigger that spikes `Rigidbody.drag` while the ball is inside. |
| `WaterHazard.cs` | Trigger that resets the ball to the spawn point on entry. |
| `MalletSwing.cs` | Kinematic mallet swing loop (deflects the ball). |

## Quick start

1. New Unity project (built-in or URP — see "Rendering" below). Unity 2021 LTS+.
2. Copy `Assets/Scripts/` into the project's `Assets/`.
3. **Add two layers** (Project Settings ▸ Tags and Layers): `Ball` and `Environment`.
4. Create an empty GameObject in the scene, name it `TikiCourse`, add the
   **`TikiJungleCourse`** component, press Play. The hole builds itself and a ball
   drops onto the tee.

That's it — everything else (colliders, Rigidbodies, physic materials, the ball,
hazard triggers, lights) is created in code.

## 4. Layers & the collision matrix (instead of bitmasks)

SceneKit used `categoryBitMask` / `collisionBitMask`. Unity uses **layers + the
Physics collision matrix**:

- Add layers **`Ball`** and **`Environment`**.
- Project Settings ▸ Physics ▸ **Layer Collision Matrix**: leave **Ball × Environment ticked**
  (they must collide). This is the universal-collide requirement — it's the matrix
  equivalent of the SceneKit fix where the floor had to collide with the ball
  regardless of category. The default matrix already has everything ticked, so the
  course works out of the box; the named layers just let you add finer rules later
  (e.g. Ball × Ball) without ever un-ticking Ball × Environment.

If the layers are missing the builder logs a warning and falls back to `Default`
(still fully collidable), so nothing silently falls through the floor.

## 1. Seamless terrain — no tunneling, ever

- The fairway is **one Cube** scaled `17 × 3 × 39`, positioned so its top face is
  the `y = 0` plane. One `BoxCollider`, **3 units thick** → zero internal seams and
  far too deep to tunnel. (This is the Unity equivalent of the single-slab fix.)
- The green and bunker/water visuals are **decals with their colliders removed**, so
  there's no lip/step for the ball to catch on. The slab is the only floor collider.
- The ball's `Rigidbody.collisionDetectionMode = ContinuousDynamic` — even a
  max-power shot can't pass through the slab between physics frames.

## 2. Physics & materials

- **Fairway** `PhysicMaterial`: `dynamicFriction = staticFriction = 0.95`,
  `bounciness = 0.2`, `frictionCombine = Maximum` — matches the smooth SceneKit
  0.95 roll regardless of the ball's own material.
- **Ball** `Rigidbody`: `mass 1`, `drag 0.16` (baseline roll), `angularDrag 0.4`,
  `ContinuousDynamic`, `Interpolate`.
- **Sand bunker**: a `SphereCollider` trigger; `SandBunker` sets `rb.drag = 4.0`
  on enter and restores `0.16` on exit (overlap-safe via a contact counter on
  `GolfBall`).
- **Hippo pool**: a `SphereCollider` trigger; `WaterHazard` calls
  `GolfBall.ResetToSpawn()` — zeroes velocity and teleports to the tee.

Tune all of these on the `TikiJungleCourse` component's inspector fields
(`fairwayFriction`, `ballDrag`, `sandDrag`, hazard centres/radii, `teeSpawn`).

## 3. Mallet monkey (kinematic)

- Monkey + pedestal on the right of the fairway; an empty **SwingPivot** holds the
  arm + `MalletHead`.
- The pivot has a **kinematic `Rigidbody`** driven by `MalletSwing` via
  `MoveRotation` in `FixedUpdate`. Kinematic + `MoveRotation` is what makes the
  sweep transfer momentum to the ball cleanly (it shoves the ball and is never
  pushed back), avoiding the transform-fight glitches we hit in SceneKit.
- Rhythm (`restHold → slam → slamHold → lift`) is exposed on the component.

## GameObject hierarchy (built at runtime)

```
TikiCourse (TikiJungleCourse)
├─ FairwayRoot
│  ├─ FairwaySlab      (Cube 17×3×39, BoxCollider, Fairway physic mat, layer=Environment)
│  └─ Green            (flat Cylinder decal, no collider)
├─ FenceRoot           (6 bamboo rails, BoxColliders, layer=Environment)
├─ ArchwaysRoot        (2 arches × [2 pillars + lintel], BoxColliders, layer=Environment)
├─ BunkerRoot
│  ├─ SandBunker       (flat Cylinder decal)
│  └─ SandTrigger      (SphereCollider isTrigger + SandBunker.cs)
├─ WaterRoot
│  ├─ HippoPool + Hippo(decals)
│  └─ WaterTrigger     (SphereCollider isTrigger + WaterHazard.cs)
├─ MonkeyRoot
│  ├─ Pedestal + Monkey
│  └─ SwingPivot       (kinematic Rigidbody + MalletSwing.cs)
│     ├─ arm
│     └─ MalletHead    (BoxCollider, layer=Environment)
├─ SceneryRoot         (palms, island lip, Sun)
└─ GolfBall            (Sphere, Rigidbody + SphereCollider + GolfBall.cs, layer=Ball)
```

## Rendering

Materials use the built-in **`Standard`** shader. On **URP**, the builder falls back
to `Universal Render Pipeline/Lit` automatically; if your project is URP make sure
that shader is included, or replace `Tint(...)` with your own material setup.

## Unity version note

Written against **Unity 2021/2022 LTS** APIs: `PhysicMaterial`, `Rigidbody.drag`,
`Rigidbody.angularDrag`. On **Unity 6 (2023+)** these were renamed —
`PhysicsMaterial`, `Rigidbody.linearDamping`, `Rigidbody.angularDamping`. If you're
on Unity 6, do a find-and-replace (the semantics are identical). I kept `drag`
because the task spec referred to `rigidbody.drag`.

## Coordinate notes (SceneKit → Unity)

Both are Y-up. SceneKit is right-handed, Unity left-handed, so Z is mirrored — the
layout numbers are carried over as-is (tee at `+Z`, green at `-Z`), which reads
correctly with Unity's `+Z = forward`. Camera/lighting are project-specific and not
created here beyond a fallback Sun.

## Multiplayer / networking

This port is the **single-hole course + physics only**. The room/round/stroke logic
still lives in the Node server (`server/`) and is engine-agnostic — a Unity client
would talk to it over the same WebSocket protocol. Wiring Unity to that server is a
separate step, not included here.
