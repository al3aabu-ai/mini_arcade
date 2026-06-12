# Unity Migration Plan

How to move the Frantics board rendering from SceneKit to Unity **without
rewriting the game**. The key architectural fact that makes this cheap: the
game board is just *another WebSocket client* of the Node server. Unity never
needs to know about SwiftUI, and the server/protocol/phones don't change at all.

```
phones (SwiftUI controllers)──┐
                              ├──► Node server ◄── board client
host phone (SwiftUI shell) ───┘                    (today: SceneKit view,
                                                    later: Unity view)
```

## Why migrate (and why not yet)

| | SceneKit (today) | Unity |
|---|---|---|
| Ships in the app today | ✅ working, crash-hardened | ❌ multi-day integration |
| App size | ~5 MB | +30–60 MB |
| Art pipeline (assets, shaders, post) | manual / procedural | ✅ industry standard |
| Toon/stylized shading, VFX graph | limited | ✅ excellent |
| Many minigames at scale | gets painful | ✅ scene-per-minigame |
| Apple long-term support | deprecated-ish | n/a (own engine) |

Verdict: stay native while the game is 1–2 minigames; migrate the **board only**
when you're ready to invest in real art (Blender models or licensed low-poly
asset packs — never ripped assets from other games).

## Phase 0 — Install (you, ~1 hour, mostly downloads)

1. Download **Unity Hub** from unity.com/download, sign in / create a Unity ID
   (Personal license is free and fine for this).
2. In Hub → Installs → add **Unity 6 LTS** with the **iOS Build Support** module
   (~10 GB total).
3. Verify: Hub → New Project → 3D (URP) template opens.

## Phase 1 — Standalone Unity board (1–2 sessions, zero risk)

Build the board as a *separate Unity app first* — run it on the Mac or a spare
device, pointed at the same server. Nothing in the iOS app changes yet.

- New URP project `FranticsBoard`, package: **NativeWebSocket** (or
  `System.Net.WebSockets` wrapper).
- Port `protocol.ts` shapes to C# records; subscribe exactly like
  `GameClient.swift` does: consume `room_state`, `aim`, `fire`; send
  `golf_progress`, `golf_finished`.
- Rebuild Guerilla Golf: Unity's PhysX replaces SCNPhysicsBody 1:1
  (`Rigidbody`, `PhysicMaterial` bounciness ≈ restitution). Keep the same
  tuning constants (impulse 5+14·power, loft 2.2+4.8·power, anvil ×0.7).
- Art: URP toon-lit shader (e.g. free "Toony Colors"-style or a custom Shader
  Graph ramp), post stack (Bloom, Vignette, SSAO) — Unity's versions of these
  are robust on iOS where SceneKit's were fragile.
- Acceptance test: a full game with phones + Unity board on the Mac, server
  smoke suite still green.

## Phase 2 — Unity as a Library inside the iOS app (1–2 sessions, the fiddly part)

Unity exports an `UnityFramework.xcframework` that the existing app embeds.

1. Unity → Build Settings → iOS → export the Xcode project; it produces
   `Unity-iPhone` + `UnityFramework` targets. Add `UnityFramework` to the
   Frantics workspace (official guide: "Unity as a Library" / UaaL).
2. Boot Unity lazily: `UnityFramework.getInstance().runEmbedded(...)` the first
   time a board is needed (golf phase or external display connect).
3. **External display**: grab `UnityFramework.appController().rootView` and
   re-parent it into the window that `BoardSceneDelegate` already creates for
   the AirPlay screen. SwiftUI keeps the phone screen; Unity owns only the TV
   window. (This re-parenting is the known-tricky bit of UaaL — budget a day.)
4. Networking: simplest is to let the Unity side keep its own WebSocket client
   from Phase 1 (the server already supports any number of board observers via
   the host seat). No Swift⇄C# bridging needed beyond "show/hide board".
5. Keep the SceneKit board behind a feature flag until Unity has run a few
   real parties: `UserDefaults` toggle `useUnityBoard`.

## Phase 3 — Art that actually moves the needle

The engine swap buys tooling; these buy beauty:

- **Models**: stylized props/characters from Blender or licensed packs
  (e.g. Synty/POLYGON-style sets on the Unity Asset Store). Original or
  licensed only.
- **Shading**: ramp-lit toon shader + rim light; gradient skybox; baked AO.
- **VFX**: trail renderers on balls, confetti burst prefabs, screen shake.
- **Animation**: DOTween for squash/stretch, UI pops, camera punches.

## Risks & gotchas

- UaaL + multiple `UIWindowScene`s is the least-documented corner of Unity iOS;
  if the external-display re-parenting fights back, fallback is: Unity renders
  on the phone and the *external scene shows a Metal-layer mirror* of it.
- Unity Personal shows a splash screen on launch (removable with Pro).
- Build times jump from ~30 s to several minutes per iteration.
- Keep the Node server + phones untouched — that's the contract that makes
  this migration safe to do gradually.
