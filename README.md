# Mini Arcade

Asymmetric local-multiplayer 3D party game prototype inspired by the broad
mini-game-party feel of titles like *Frantics*. The production concept matches
the original SwiftUI/SceneKit draft in `al3aabu-ai/mini_arcade`: one iPhone is
the host, AirPlay/HDMI sends the public board to the TV like a console, and the
host phone plus every other phone stays a private controller.

This Windows/Unity prototype keeps the game logic and LAN controller model
platform-agnostic so it can later move to iOS.

All mini-games should be original 3D party-game challenges. The first/main game
is a 3D mini-golf game; the older tap games are temporary framework samples.

See `Asymmetric_Multiplayer_Game_Specification.md` for the full design.

## Current Status

Milestone 1: project setup complete.

Milestone 2: first playable complete.

Milestone 3: multi-round match loop complete and compile-verified.

Milestone 4 started: first 3D party mini-game, `Party Mini Golf`, implemented
as a procedural Unity physics course.

Milestone 4 presentation pass: dynamic arcade camera, safe-area UI scaling, and
first-pass ball VFX hooks are implemented.

Milestone 4 tiki theme pass: procedural tropical/tiki environment pieces and a
matching arcade HUD skin are implemented.

External-display routing pass: the app now boots `DisplayManager`, activates
external displays, keeps private UI on display 0, and routes the public
mini-golf camera to display 1 when AirPlay/HDMI is available.

The prototype is code-driven. Pressing Play boots the whole app through
`AppRoot`; no scene or prefab wiring is required.

## Playable Flow

Current loop:

`Role select -> Lobby -> 3-round match -> Round result -> Secret bidding -> Next round -> Final standings`

Implemented now:

- Host and controller role selection.
- Host device runs the authoritative local session and owns the public TV view.
- Unity-app controllers over raw TCP on port `7777`.
- Browser controllers over HTTP/WebSocket on port `8080`.
- Shared lobby across both controller types.
- Free-tier 2-player cap with a Premium host toggle for larger tests.
- Three mini-games in rotation:
  - `Party Mini Golf`: 3D procedural mini-golf course with physics ball, rails,
    blockers, rotating bumper, coin pickups, aim/power/shoot controls, strokes,
    hole scoring, speed-follow camera, ball trail, shot burst, and impact burst
    feedback. The course now uses a tropical/tiki visual pass: raised wood
    platform, bamboo rail placeholders, leaf accents, glowing masks, torches,
    warm lighting, and hot arcade colors.
  - `Coin Rush`: tap race, each tap scores and earns coins.
  - `Reaction Duel`: wait for GO, then tap fast; early taps false-start.
- Three-round default match, cycling through the mini-game catalog.
- Secret bidding between rounds:
  - Controllers see only their own spendable coin balance.
  - TV/host public view sees only who has submitted, not amounts or balances.
  - Highest unique bid pays that amount and receives a small score head-start
    in the next round.
  - Tied highest bids award no advantage.
- Final winner uses the spec rule: most mini-game wins, then highest total coins
  earned across the match as the tie-breaker.

## Running

1. Open the project in Unity `6000.3.18f1`.
2. Press Play.
3. Fastest single-window demo: click `Host + 1 local bot`, then `Start Match`.
   The first round starts with `Party Mini Golf`.
4. Browser controller: click `Host a game`, then open the lobby URL shown in
   Unity. On this same PC use `http://localhost:8080`; on a phone use the
   `http://<PC-LAN-IP>:8080` address shown in the lobby.
5. Unity-app controller: run another app instance/device and Join the host LAN
   IP on port `7777`.

Browsers cannot use `localhost:7777`; that is the raw TCP protocol. Browser
controllers use `8080`.

Windows Firewall must allow the Unity app on the private network for phones to
connect over Wi-Fi.

Target iPhone/TV behavior:

- Host taps Host Party on the iPhone.
- Host starts AirPlay Screen Mirroring or connects HDMI.
- iOS exposes the TV as an external display.
- Unity activates display 1 and renders the public mini-golf board there.
- The host iPhone screen remains display 0 and shows private controls.
- Other phones join the same LAN session as controllers.

Mini-golf controls:

- Aim Left / Aim Right
- Power - / Power +
- Shoot

These controls appear both in Unity-app controllers and the browser controller
during mini-golf. Tap-based games still show a TAP button.

The mini-golf camera now uses a center gameplay viewport with reserved HUD zones:
about 12% at the top and 18% at the bottom. The Unity IMGUI overlay and browser
controller both derive layout from safe-area / viewport-relative measurements
instead of fixed screen pixels. The HUD skin uses procedural wood/bamboo/hot
orange textures so iPhone notch and Dynamic Island layouts stay inside safe
bounds while still reading as a tropical arcade controller.

## Project Structure

```text
Assets/Scripts/
  Core/
    AppRoot.cs              code-driven app coordinator and IMGUI prototype
    MatchDirector.cs        multi-round match sequence and scoring
    AppState.cs             lobby/game/bidding/results states
    GameStateMachine.cs
    MainThreadDispatcher.cs socket callbacks back onto Unity main thread
  Networking/
    TcpHostService.cs       host transport for Unity-app controllers
    TcpClientService.cs     Unity-app controller transport
    WebControllerServer.cs  HTTP + WebSocket browser controller
    MessageCodec.cs         length-prefixed JSON TCP framing
    NetworkMessage.cs       shared message envelope
    Dtos.cs                 payload DTOs
    LanDiscovery.cs         scaffold for later auto-discovery
  MiniGames/
    IMiniGame.cs
    MiniGameCatalog.cs
    MiniGameResult.cs
    MiniGolf/MiniGolfGame.cs
    CoinRush/CoinRushGame.cs
    Reaction/ReactionGame.cs
  Economy/
    BiddingSystem.cs
  Players/
    PlayerData.cs           private spendable coins, earned coins, wins
  Session/
    SessionData.cs          host-owned session state and free/premium cap
  Display/
    DisplayManager.cs       activates AirPlay/HDMI display and exposes display routing
```

## Spec Mapping

| Spec area | Implementation |
|---|---|
| Guest-first onboarding | Role-select flow, no login requirement |
| Local LAN host topology | Host opens TCP and WebSocket services |
| Phone controllers | Unity-app controllers plus browser controllers |
| One phone as TV console | `DisplayManager` plus public camera target display routing |
| Public/private information split | Public TV hides balances and bid amounts; controllers receive private bidding state |
| Multi-round loop | `MatchDirector` and `AppRoot` |
| Coin reset at match start | `SessionData.ResetForNewSession()` |
| Coin earning | Mini-game score, mini-golf pickups, plus placement payout |
| Hidden bidding | `BiddingSystem`, `BiddingStateDto`, bid UI on Unity/browser controllers |
| Final tie-breaker | Wins first, total coins earned second |
| Host-centric premium cap | `SessionData.MaxPlayers` and Premium host toggle |

## Prototype Notes

The current UI is IMGUI and intentionally plain. The mini-golf arena itself is
real Unity 3D; the control/status UI is still prototype-level.

On Windows, display separation is only testable if a second monitor is attached.
On iPhone, the target behavior is the same as the SwiftUI/SceneKit draft:
external display gets the public board; the physical phone remains the private
controller/master UI. iOS build and real AirPlay/HDMI testing require a Mac with
Xcode and Unity iOS Build Support.

The mini-game selector from the spec is represented by a default 3-round
rotation. A polished selector is a later UI milestone.

## Next Milestones

- Replace IMGUI with real TV and controller UI.
- Add the mini-game selector screen.
- Expand mini-golf into a richer 3D party course: themed obstacles, better camera
  work, stronger feedback, and multiple course layouts.
- Add LAN auto-discovery to remove manual IP entry.
- Add secret tasks pushed to individual controllers.
- Add ads, IAP subscription gating, and restore-purchase sign-in.
- Port to iOS on a Mac with Xcode and Unity iOS Build Support.
