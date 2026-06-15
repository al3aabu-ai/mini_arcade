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
| 3 | `runway` | Tiki Runway (**final round**) |

> Golf is **3 rounds**. A 4th map ("Tiki Snake") was prototyped and then removed
> (path geometry was unsalvageable). The flow terminates and the leaderboard is
> finalized after Round 3.

### Where it lives
- **Server (authoritative):** `server/src/room.ts` + `server/src/protocol.ts`.
  - `startGolf(round, priorStrokes)` sets `map = round >= 3 ? "runway" : round === 2 ? "tiki" : "guerilla"` and resets per-round stroke counts while carrying `priorStrokes` forward.
  - `finishGolf(order)`: if `golf.round < 3` it records standings and schedules `startGolf(round + 1, totals)`; on **round 3** it awards points and proceeds to the next phase.
  - `GolfState` carries `round`, `map`, and cumulative `strokes` per player. `GolfMap = "guerilla" | "tiki" | "runway"`.
- **iOS board:** `ios/Frantics/Board/Golf3DBoard.swift`.
  - `GolfSceneController` builds the course by `courseMap` (`buildWorld()` branches to Guerilla / `buildTikiWorld()` / `buildRunwayWorld()`).
  - `GolfBoardView` **rebuilds the controller whenever `golf.map` changes** (so Round N+1 spawns on a fresh course), and the HUD shows `ROUND n/3` + the map name.
- **On-device engine:** `ios/Frantics/Resources/FranticsEngine.js` is bundled from `room.ts`/`protocol.ts`/`dispatch.ts`. **After ANY server logic change, rebuild it:** `cd server && npm run build:embedded`.

### Winner rule — LOWEST TOTAL STROKES (not finish order)
- A **stroke** is counted **server-side** in `relayFire()` each time the on-turn shooter fires (strict `golf.turnId === playerId`, so the settling window where `turnId === null` is never counted). Strokes are **cumulative across all rounds** (`priorStrokes + roundStrokes`).
- Final standings in `finishGolf` rank **sinkers by fewest total strokes ascending**; ties broken by who sank first. Players who never sank do not place.
- Points awarded by that ranking (`GOLF_BOUNTIES` 500 / 300 / 200, then 100). **The lowest-stroke player is the match winner — finishing first does NOT win.**
- This is regression-tested in `server/scripts/smoke.ts` (R1→R2→R3 transitions, stroke carry-over, tie-break, final awards). Run `cd server && npm run smoke`.

### Shot mechanics — STRICTLY HORIZONTAL
- In `applyFire` (`Golf3DBoard.swift`) the launch impulse's **Y-component is locked to 0** and any residual vertical velocity is zeroed, so the ball never lifts/jumps — it stays flush and glued to the slab. Power scales only the horizontal magnitude (anvil debuff ×0.7). No squash `SCNAction` (it fought the solver).

### Camera follow — ELEVATED third-person, pitched DOWN the fairway
- `GolfSceneController.updateFollowCamera()` (every frame) **smoothly lerps** the camera toward `activeBall + cameraFollowOffset` and the look-target toward `activeBall + cameraLookOffset` (factors 0.06 / 0.10) — a damped chase cam, no hard cuts.
- **Spec:** the follow offset is **elevated and behind** (`y ≈ 14`, `z ≈ +18…22`); `cameraLookOffset ≈ (0, 0, −11)` drops the target to **fairway level AHEAD of the ball** (toward the −Z hole). Because the look-target sits well *below* the camera and ahead, the cam **pitches down the path** (~24°) — a clean angled top-down third-person frame where the runway width, side water hazards, and upcoming obstacles all read clearly.
- **Gotcha:** the pitch is `(cameraFollowOffset.y − cameraLookOffset.y)` over the forward distance. If `cameraLookOffset.y` is set *above* the ball while the camera is low, the cam tilts UP and you lose the path — keep the camera high and the look-target low. Each course sets its own `cameraFollowOffset` in `build*World()`; `cameraLookOffset` is shared.

### No particle splash effects
- The launch/roll **trail** and the **sink celebration** particles are removed (trail `birthRate` forced to 0; `celebrate()` deleted). Only the ball↔ball contact spark remains.

### Thermal / rendering budget (host phone runs the server AND renders)
The host phone runs the JS game server *and* renders the 3D board, so the GPU
budget is tight — it throttles fast. A 60fps + 2X-MSAA pass pushed the heat
threshold from ~3min to ~6min; the levers below are the aggressive low-power
**baseline** (visuals deliberately stripped — raise them back once thermals hold):
- **Cap the frame rate.** Every `SceneView` passes `preferredFramesPerSecond:
  GolfSceneController.targetFPS`. Currently **30** (baseline); was 60. Uncapped,
  ProMotion hardware renders 120Hz and overheats within minutes. One constant.
- **On-demand rendering.** `SceneView` `options` deliberately OMIT
  `.rendersContinuously`, so SceneKit only redraws when the scene is dirty.
- **Cheaper AA.** `antialiasingMode: .multisampling2X` (not the 4X default) — half
  the MSAA resolve cost, edges still smooth.
- **Pause when off-screen.** `GolfBoardView.onDisappear` sets `controller.scene
  .isPaused = true` (and `.onAppear` clears it). One flag freezes every looping
  obstacle action, the physics step, and the render loop while the board isn't
  visible (lobby, podium, between rounds, host closing the preview).
- **No HDR/bloom/SSAO (baseline).** `useHDR` is force-`false` at the
  `GolfSceneController(...)` call site, so the camera keeps SceneKit's defaults
  (`wantsHDR=false`, bloom 0, SSAO 0) and **no post-processing pass runs**. The
  glow + screen-space ambient-occlusion passes were a prime GPU/thermal cost on
  mobile. Restore the rich look by reverting to `!client.boardDisplayConnected`.
- **No real-time shadows (baseline).** All three directional "sun" lights set
  `castsShadow = false`. A 2048² shadow map was re-rendering every frame as the
  moving props/gates dirtied it. The **baked-AO vignette** over the fairway still
  grounds the scene, so it's not fully flat. Flip `castsShadow` back to `true`
  (Guerilla keeps its tuned `shadowMapSize`/`shadowRadius`) to restore them.
- The render loop (`renderer(_:updateAtTime:)`) is **frame-rate independent** —
  all timing gates on wall-clock `CACurrentMediaTime()`/`Date`, never frame counts.
- Decorative looping actions (pennants, torches, water bob, propeller, gates) are
  "juice" and run during play by design — do NOT freeze them mid-game; rely on the
  off-screen pause + FPS cap instead. A map swap rebuilds the controller, which
  releases the old scene and all its actions.

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

### Hole construction — REAL DOWNWARD FUNNEL (carved below grade)
- The cup must be a concave funnel carved **DOWNWARD**, never a raised rim. A raised
  "pot" ring reads as a **volcano** and bounces the ball away — do NOT do that.
- The seamless slab is solid, so to carve below it: **the slab STOPS at the green's
  near edge** (`TikiRunwayCourse.buildFairwayAndWater` shortens the slab to z ≈ −14.5),
  and `buildFunnelHole` lays a ring of facet panels whose **outer rim is flush at
  y = 0** (meeting the slab end and the side rails) and whose **inner edge dips below
  grade** (`cupY ≈ −0.8`) to the cup. With no slab beneath, the facets ARE the floor,
  so gravity rolls a nearby ball straight down into the hole. Each panel is oriented
  with `node.look(at: outerRimPoint, ...)`; the rim is clamped to the lane rectangle
  so it fills the full width with no gaps. Static bodies, `collisionBitMask = -1`.
- The controller's sink radius is `horizontalDist < 0.8` (a touch generous so the
  funnel reliably drops close balls).
- **Secure boundaries:** every course must close ALL edges. Tiki Runway has bamboo
  **end fences** (`addEndFence`) behind the tee (+Z) and behind the green (−Z, just
  past the funnel's far rim) in addition to the side rails — nothing rolls off an end.

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

## 5. Collectible coins (3D pickups + economy)

Loose coins drop on the fields; grabbing one credits a flat `CONST.COIN_VALUE`
(50) to that player's **private** `coins` wallet. Coin POSITIONS are public map
state (`spawnedCoins` on the golf/bomb snapshot) — only the wallet TOTAL is masked.

### Physics bitmasks (`Golf3DBoard.swift`)
| body | category | collision | contactTest |
|------|----------|-----------|-------------|
| ball | `ballCategory = 1<<5` | `~coinCategory` (everything **except** coins) | `ballCategory` (ball↔ball spark) |
| coin | `coinCategory = 1<<6` | `0` (pure trigger — pushes nothing) | `ballCategory` (fires `didBegin` on a ball) |

- The ball's collision mask **excludes** the coin bit so it rolls straight
  THROUGH the coin (no deflection); the coin is a **static, gravity-off** body
  (`SCNPhysicsBody(type: .static)`, `isAffectedByGravity = false`).
- Coins are thin gold `SCNBox`es named `"coin-<i>"`, spun by a looping
  `rotateBy` on Y. `makeCoinNode` builds them; the per-course `coinPositions`
  (in `TikiJungleCourse` / `TikiRunwayCourse`) say WHERE (Guerilla R1 has none).
  Runway's marquee coin sits dead-centre in the plank-wall gap (z = 4).

### Network layout
- **Golf (authoritative board):** after building the course the board calls
  `register_coins {coins:[{id,x,y,z}]}` (host-only) → server stores
  `golf.spawnedCoins`. On a ball↔coin `didBegin` (host board), it animates the
  coin out locally and sends `collect_coin {coinId, playerId}` where `playerId`
  is the **ball's owner** (the active shooter). Server `collectCoin` (host-only)
  validates the coin still exists, removes it, credits the collector, broadcasts.
  The `coins[id]` node registry makes a burst of contacts collect a coin once.
  `startGolf` clears `spawnedCoins`; the board re-registers each round.
- **Bomb (2-D arena, no SceneKit):** the server spawns 2–3 coins at
  `startBomb` (`generateBombCoins`, fractional screen coords). There's no
  physics, so it's **pass-to-collect**: a successful `passBomb` shifts one coin
  off `bomb.spawnedCoins` and banks +50 to the passer. The TV (`BombBoardView`)
  scatters the remaining 🪙 and animates them out as they're grabbed.

---

## 6. Secret tasks (private hidden objectives)

Each player gets ONE random hidden objective per mini-game, shown only on their
own phone, paying `rewardCoins` (150) into their private wallet on completion.

### State + privacy
- `SecretTask {id, descriptionEN, descriptionAR, rewardCoins, isCompleted}`;
  pools live in `SECRET_TASKS[GameType]` (protocol.ts). Both languages travel in
  the data so the phone shows the right one for the user's setting.
- `PlayerState.secretTask` is **PRIVATE**, masked exactly like `coins`: in
  `viewState(viewerId)` it's `p.id === viewerId ? p.secretTask : null`, so it
  only ever reaches the owner — never another player, never the TV. The TV views
  must never read `secretTask`.

### Lifecycle
1. **Assign** at mini-game start — `assignSecretTasks(game)` in `startGolf`
   (only when `round === 1`, since a golf "game" is the whole 3-round segment)
   and `startBomb`. It also resets that game's telemetry on every player.
2. **Track telemetry** during play (server-side, on the player):
   - golf `long_shot` → `taskMaxPower` set in `relayFire` when `power ≥ 0.95`.
   - golf `greedy_golfer` → `taskCoins` bumped in `collectCoin`.
   - golf `safe_play` → `taskReset` set by `reportBallReset` (the host board
     sends `ball_reset {playerId}` from its water/out-of-bounds respawn branch).
   - bomb `hot_potato` → `taskBombHotPotato` set in `passBomb` when held ≤ 1s.
   - bomb `survivor` → `taskBombHoldMs` accumulated via `bomb.holderSince`
     (banked on each `setBombHolder` / `explodeBomb` / `finishBomb`); pass if ≤ 5s.
3. **Evaluate + pay** in `evaluateSecretTask(p)`, called for every player at the
   END of the game (`finishGolf` final round, `finishBomb`). Sets `isCompleted`
   and quietly credits `rewardCoins`.
4. **Display**: `SecretTaskCard` (in `PhoneGolfView.swift`, reused by
   `PhoneBombView` + `PhonePodiumView`) reads `client.me?.secretTask` — an
   expandable banner while active, a "Task complete! +150" confirmation once done.
5. **Clear** in `startAuction` / `startSelection` (so the intermission and next
   game start clean). The final game's task survives to the podium on purpose,
   where the card shows in `completedOnly` mode.

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
