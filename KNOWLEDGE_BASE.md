# Frantics — Engineering Knowledge Base

> Single source of truth for the architecture, hard-won bug fixes, and conventions
> of this project. **Read this first** when starting a new session. Engine: SwiftUI
> + **SceneKit** (iOS) with an authoritative **Node/TypeScript** game server. The
> host iPhone can also run that server on-device via JavaScriptCore (see "Same WiFi").
>
> A short Unity port was explored and then **abandoned** (thermal/overheating). The
> stable SceneKit build is preserved on branch **`scenekit-stable-backup`** and tag
> **`scenekit-stable`**. Active development is on **`lan-auto-discovery`**.

---

## 1. The multi-round golf system

Golf is a **three-round segment**, each round a different course, played turn-based
(one shooter at a time; the host board drives the rotation):

| Round | Map id (`golf.map`) | Course |
|------|---------------------|--------|
| 1 | `guerilla` | Guerilla Golf (the original floating island) |
| 2 | `tiki` | Tiki Jungle Adventure |
| 3 | `runway` | Tiki Runway |
| 4 | `snake` | Tiki Snake |

### Where it lives
- **Server (authoritative):** `server/src/room.ts` + `server/src/protocol.ts`.
  - `startGolf(round, priorStrokes)` sets `map = round >= 4 ? "snake" : round === 3 ? "runway" : round === 2 ? "tiki" : "guerilla"` and resets per-round stroke counts while carrying `priorStrokes` forward.
  - `finishGolf(order)`: if `golf.round < 4` it records standings and schedules `startGolf(round + 1, totals)`; on **round 4** it awards points and proceeds to the next phase.
  - `GolfState` carries `round`, `map`, and cumulative `strokes` per player. `GolfMap = "guerilla" | "tiki" | "runway" | "snake"`.
- **iOS board:** `ios/Frantics/Board/Golf3DBoard.swift`.
  - `GolfSceneController` builds the course by `courseMap` (`buildWorld()` branches to Guerilla / `buildTikiWorld()` / `buildRunwayWorld()` / `buildSnakeWorld()`).
  - `GolfBoardView` **rebuilds the controller whenever `golf.map` changes** (so Round N+1 spawns on a fresh course), and the HUD shows `ROUND n/4` + the map name.
- **On-device engine:** `ios/Frantics/Resources/FranticsEngine.js` is bundled from `room.ts`/`protocol.ts`/`dispatch.ts`. **After ANY server logic change, rebuild it:** `cd server && npm run build:embedded`.

### Winner rule — LOWEST TOTAL STROKES (not finish order)
- A **stroke** is counted **server-side** in `relayFire()` each time the on-turn shooter fires (strict `golf.turnId === playerId`, so the settling window where `turnId === null` is never counted). Strokes are **cumulative across all four rounds** (`priorStrokes + roundStrokes`).
- Final standings in `finishGolf` rank **sinkers by fewest total strokes ascending**; ties broken by who sank first. Players who never sank do not place.
- Points awarded by that ranking (`GOLF_BOUNTIES` 500 / 300 / 200, then 100). **The lowest-stroke player is the match winner — finishing first does NOT win.**
- This is regression-tested in `server/scripts/smoke.ts` (R1→R2→R3→R4 transitions, stroke carry-over, tie-break, final awards). Run `cd server && npm run smoke`.

### Shot mechanics — STRICTLY HORIZONTAL
- In `applyFire` (`Golf3DBoard.swift`) the launch impulse's **Y-component is locked to 0** and any residual vertical velocity is zeroed, so the ball never lifts/jumps — it stays flush and glued to the slab. Power scales only the horizontal magnitude (anvil debuff ×0.7). No squash `SCNAction` (it fought the solver).

### Camera follow
- `GolfSceneController.updateFollowCamera()` (called every frame in the render loop) **smoothly lerps** the camera toward `activeBall + cameraFollowOffset` and the look-target toward the ball (factors 0.06 / 0.10) — a damped chase cam with no hard cuts. Each course sets its own `cameraFollowOffset` (and an initial framing) in its `build*World()`.

---

## 2. The Seamless Landmass component pattern (no sinking/clipping balls)

### The bug
Balls tunnelling through the floor or sinking out of the world had **two distinct causes**:

1. **Physics seams from multi-slab terrain.** Building the fairway from several
   overlapping / rotated box primitives creates ridges and gaps at the seams where
   a fast or settling ball catches or falls *between* tiles.
2. **Collision-mask desync (the Round-2 culprit).** The course's static bodies were
   created with `collisionBitMask = Category.ball` (a course-local bit). But the
   **live golf ball uses `GolfSceneController.ballCategory = 1 << 5`**. SceneKit
   filtered the floor↔ball pair entirely, so the ball never collided with the slab
   and fell straight through. (Round 1 never sank only because its slab uses
   SceneKit's *default* all-bits masks.)
3. **Spawn-inside-floor.** A tee Y at/under the slab top initializes the ball inside
   the static collision box; the solver can resolve that by dropping it out.
4. **Model/presentation desync (the "teleport to tee").** During simulation SceneKit
   moves only the *presentation* node; the *model* node keeps its spawn transform, so
   the next `SCNAction` (e.g. a launch squash) snaps the ball back to the tee.

### The mandatory fix standard (every map MUST follow)
- **One continuous slab.** Build the floor as a **single thick primitive ≥ 3 units
  deep**, top surface flush on a flat plane (`y = 0`). One `SCNPhysicsBody(type:.static)`,
  no overlapping tiles → zero internal seams, too thick to tunnel.
- **Decorations are flush decals with NO physics body.** Greens, sand bunkers, water,
  cups, lips — visuals only. A raised collider for a bunker/green is itself a seam.
  Gameplay effects come from *region queries*, not colliders (see hazards below).
- **Raise the tee.** Spawn the ball clearly **above** the slab (e.g. `teePosition.y = 1.0`,
  ball radius ≈ 0.42) so it drops cleanly onto the top-surface collision.
- **Universal environment collision mask.** Every static/kinematic environment body
  must use **`collisionBitMask = -1`** (`~0`, all categories) so it always catches the
  ball's custom category (`1 << 5`) regardless of mismatches. Static/kinematic bodies
  never move, so colliding with "all" is safe. **Do not** reuse SceneKit's reserved
  bits `1<<0` (default) / `1<<1` (static) for custom categories.
- **Keep the ball awake + transforms unified.** Ball `physicsBody.allowsResting = false`;
  on settle, write `presentation.position` back to the model node and `resetTransform()`
  so the lie is the single source of truth (no tee-snap on the next shot).

### Hazards as region queries (not colliders)
Courses conform to the `GolfHazardCourse` protocol (`root`, `teePosition`, `holeCenter`,
`isOverWater(_:)`, `isOverSand(_:)`). The controller's render loop calls these every
frame: `isOverSand` spikes the ball's `damping`; `isOverWater` triggers the
out-of-bounds reset to the tee (same path as `p.y < outOfBoundsY` = −9).

---

## 3. Tiki Runway blueprint (Round 3) — ref: IMG_7544.PNG

`ios/Frantics/Board/TikiRunwayCourse.swift` (conforms to `GolfHazardCourse`). A long,
dead-straight lane on one thick seamless slab (width ≈ 8, **height 3**, length 48,
top at `y = 0`), walled by bamboo rails at `x = ±3.6`, with **open water on both sides**.

- **Tee:** `(0, 1.0, 18)` (near, +Z). **Hole/green:** `(0, 0.2, -18)` (far, −Z).
- **Out of bounds:** `isOverWater(p) = abs(p.x) > 3.7` — clearing a rail into the water
  resets the ball to the tee. (The slab is the only floor collider; water is a decal.)
- All static/kinematic bodies use `collisionBitMask = -1` per the standard above.

### The four mandatory obstacles (modular node groups + looping `SCNAction`s)
Listed tee → green. Moving parts are **kinematic** bodies driven by `SCNAction`s, so they
physically deflect the ball.

| # | Obstacle | Node group | Motion / structure |
|---|----------|-----------|--------------------|
| — | **Start Mallets** | `malletsNode` | Two oversized mallets flanking the tee. Kinematic; a looping `rotateTo` rocks each inward toward the lane and back, clear of the centre launch line. |
| 3 | **Tiki Plank Wall** | `plankWallNode` | A wall of **static** bamboo planks across the lane with a **narrow centre gate (~1.8 wide)** to thread with a straight power shot. No motion. |
| 2 | **Rotating Propeller** | `propellerNode` | A 3-blade fan lying flat; the hub runs `.repeatForever(.rotateBy(y: 2π, duration: 2.4))`. Each blade is a kinematic body — mistime it and the ball is knocked toward the side water. |
| 1 | **Tiki Gate Trap** | `gateNode` | Two stone blocks just before the green. Each runs a looping `.sequence([wait, moveBy(closed), wait, moveBy(open)])`, sliding to meet in the centre and back. Time the shot through the gap or get deflected/crushed. |

Standalone inspection: run with env `FRANTICS_DEMO=runway` (or the `#Preview` in the file).
Round 1 (`FRANTICS_DEMO` not needed — live) and Round 2 (`FRANTICS_DEMO=tiki`).

---

## 3b. Tiki Snake blueprint (Round 4) — ref: minigolf_hole11_tiki_snake.jpg

`ios/Frantics/Board/TikiSnakeCourse.swift` (conforms to `GolfHazardCourse`). An
extreme winding **serpentine** bridge enclosed by bamboo rails, surrounded by water.

- **Seamless-slab realization of a non-rectangular path.** The whole play area is ONE
  thick slab (20 × 3 × 44, top `y = 0`) whose surface reads as the lagoon. The snake
  **path is a green decal corridor** defined by an array of axis-aligned rectangles
  (`segments`, the S/serpentine), marked by bamboo rails on each segment's long edges
  (short ends open so the corridor connects). `isOverWater(p)` returns **true when the
  ball is outside every corridor segment** — i.e. it cleared a rail into the water →
  reset to the circular START tee at `(0, 1.0, 16)`. Hole at `(0, 0.2, -17)`.
- All static/kinematic bodies use `collisionBitMask = -1`.

### Obstacles (modular node groups + looping `SCNAction`s; kinematic = deflects ball)
| Obstacle | Node group | Motion |
|----------|-----------|--------|
| **A & B — Sliding Totems** | `totemsNode` | Two totems on the curves, each a kinematic body running `moveBy(x:)` left↔right across the narrow track on a loop. |
| **C — 4-Blade Cross Propeller** | `propellerNode` | A flat wooden cross at the centre of the middle straight; hub `.repeatForever(.rotateBy(y: 2π))`, four kinematic blades. Thread the rotating gaps. |
| **D — Vertical Bamboo Spikes** | `spikesNode` | A row of bamboo logs that rise/sink (`moveBy(y:)`) in an **alternating** rhythm (odd logs offset by half a period). Cross when your lane's log is down. |
| **Final Curve Mallet** | `malletNode` | A large kinematic mallet on the final bend (`rotateTo` slam/lift loop), guarding the green. |

Standalone inspection: `FRANTICS_DEMO=snake` (or the `#Preview` in the file).

---

## 4. Xcode Cloud & CI preservation

Apple enforces a **daily deployment/upload limit** (we hit `ITMS-90382`). To avoid
triggering Xcode Cloud builds on every push:

- **Append `[ci skip]` to every commit message** for standard development work, until
  active production deployment is explicitly requested. Example:
  `feat: tune Tiki Runway gate timing [ci skip]`.

### Deploying / testing on device (bypasses TestFlight)
- Use **`./local-install.sh`** (repo root): cleans → builds + signs for device
  (automatic signing, `DEVELOPMENT_TEAM` defaults to the personal team `9472PWTG9J`,
  overridable) → installs + launches on the plugged-in iPhone via `xcrun devicectl`
  (fallback `ios-deploy`). It detects the device by its **OS-version line** in
  `xctrace list devices` (not the device name) and never targets a simulator.
- **Do not boot the iOS Simulator** without telling the user first — they test on a
  real device. Prefer device builds or the headless `npm run smoke` / engine tests.

---

## Repo orientation (key files)

```
server/src/
  protocol.ts     wire contract + CONST (timers, bounties); GolfMap, GolfState
  room.ts         authoritative state machine (lobby/auction/golf×3/bomb/podium)
  dispatch.ts     per-connection message routing (shared by server + on-device engine)
  embedded.ts     entry bundled into the iOS JavaScriptCore engine
  server.ts       Node WebSocket server + Bonjour advertising
  scripts/build-embedded.mjs   esbuild → ios/Frantics/Resources/FranticsEngine.js
  scripts/smoke.ts             full-game E2E test (npm run smoke)
ios/Frantics/
  Core/Models.swift            mirrors protocol.ts (keep in sync)
  Core/GameClient.swift        WebSocket client, connection modes, hosting
  Core/Localization.swift      runtime EN/AR string-swap table (Najdi Arabic)
  Core/LANServer.swift         on-device WebSocket server (host phone)
  Core/FranticsEngine.swift    JavaScriptCore host for FranticsEngine.js
  Board/Golf3DBoard.swift      GolfSceneController, GolfBoardView, GolfHazardCourse, Round 1
  Board/TikiJungleCourse.swift Round 2 course
  Board/TikiRunwayCourse.swift Round 3 course
local-install.sh               side-load to a plugged-in iPhone
```

### Cross-cutting conventions
- `Models.swift` mirrors `protocol.ts` — change both together.
- After editing `room.ts`/`protocol.ts`/`dispatch.ts`, **rebuild the engine bundle**
  (`npm run build:embedded`) or the on-device host runs stale logic.
- All player-facing UI text goes through `Localization.shared.tr("English")`; add the
  Najdi value to the table in `Localization.swift` (casual white-Najdi tone).
