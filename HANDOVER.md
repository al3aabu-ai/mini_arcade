# Mini Arcade — Handover (Stage 2: wire the phone web UI into the Unity host)

**Audience:** a fresh coding agent (Codex) with no prior context.
**Date:** 2026-06-18. **Last worked by:** Claude Code.

---

## 1. What this project is

Asymmetric local-multiplayer party game (spec: `Asymmetric_Multiplayer_Game_Specification.md`).
Model: **one device hosts** (also drives the TV/“console”); **every phone is a private controller**.

- **Unity** = the host/server + TV/public view + the 3D mini-games. Windows/Editor
  prototype only. **iOS cannot be built on this Windows PC** (needs a Mac + Xcode);
  keep code platform-agnostic. Editor: **Unity `6000.3.18f1`**.
- **Phone web app** = the control surface (host picker + player controllers),
  served by the host over LAN so it runs in any iPhone/Android browser, no install.

The phone UI was designed by the user in Claude Design; the exports live in
`Game UI/*.dc.html` (6 screens). We rebuilt them as a real web app. **Treat the
`Game UI/` files as the visual source of truth** — match them exactly.

---

## 2. Current status

### Stage 1 — DONE & verified
Full phone web app, faithful to the designs, with client-side navigation:
- `web/index.html` — all screens (Home, Join/Host-Setup shared, Lobby host+player, Pick Games) + shared CSS design system.
- `web/app.js` — data (faces/colors/games), state, router `go(screen)`, render fns, button wiring, and a WebSocket client hook (`ws://location.host/`).
- Verified by driving Home→Host→Setup→Create Room→Lobby→Pick in-browser (no JS errors); Pick screen styling confirmed pixel-exact (Fredoka, gold button gradient `#FFE27A→#FFC21A` + `0 7px 0 #D99700`, etc.).
- Copied to **`Assets/StreamingAssets/web/`** (so the Unity host can serve it in Editor and builds). **Keep `web/` and `Assets/StreamingAssets/web/` in sync** (web/ is for local preview; StreamingAssets is what the host serves).

Design tokens: font **Fredoka**; bg `radial-gradient(135% 95% at 50% -12%, #a435ee 0%, #6d28d9 44%, #3b0d73 100%)`; gold `#FFD23F`; deep `#3b0d73`; accents pink `#FF5DA2`, cyan `#38E1FF`, lime `#B6FF4B`.

### Stage 2 — REMAINING (your job)
Wire the web app to the live match. Two files (both already exist, both have evolved — READ them first):
- `Assets/Scripts/Networking/WebControllerServer.cs`
- `Assets/Scripts/Core/AppRoot.cs`  (large; heavily edited — read fully before touching)

---

## 3. The web ↔ host protocol (the contract — match on BOTH sides)

`web/app.js` already sends/receives these. Implement the host side to match.

**Browser → host** (`ws.send(JSON.stringify(...))`):
| message | when | host action |
|---|---|---|
| `{t:"createRoom", name, avatar, color}` | host taps Create Room | make this connection the host-player; generate a 4-char room code; reply `roomCreated`; broadcast `lobby` |
| `{t:"join", code, name, avatar, color}` | player taps “That’s me — Join!” | add player (validate code; reply `error` if wrong); broadcast `lobby` |
| `{t:"profile", name, avatar, color}` | avatar/color/name change | update that player; broadcast `lobby` |
| `{t:"startPick"}` | host taps “Pick Mini-Games” | (host advances to pick locally; optionally tell others) |
| `{t:"pickUpdate", games:[keys], mode}` | host changes selection | optional: mirror to TV |
| `{t:"pickStart", games:[keys], mode}` | host taps “Let’s Go!” | map keys→catalog ids and **start the match** |
| `{t:"leave"}` | back/leave | remove player; broadcast `lobby` |
| `{t:"tap"}` / `{t:"bid", amount}` | in-game (existing) | existing ControllerInput / Bid handling |

`games` keys are: `golf`, `sumo`, `bomb` (the 3 unlocked cards). **Mapping decision (user-approved):**
`golf→mini_golf`, `sumo→coin_rush`, `bomb→reaction` (Sumo Smash & Hot Bomb aren’t built; map to existing games for now). Catalog ids are in `Assets/Scripts/MiniGames/MiniGameCatalog.cs` (`mini_golf`, `coin_rush`, `reaction`).

**Host → browser** (WebControllerServer wraps as `{"t":<type>,"d":<payloadJSON>}`):
| message | payload `d` | app.js handler (already present) |
|---|---|---|
| `roomCreated` | `{code}` | sets `state.code`, re-renders lobby |
| `lobby` | `{players:[{name,color,isHost,you}], code, hostName, premium}` | renders host grid / player room |
| `goPick` | – | host SPA navigates to Pick |
| `error` | `{msg}` | toast |
| `game`/`bidding`/`results` | existing DTOs | in-game (wire later) |

> app.js `lobby` handler reads `d.players` as an **array of objects** `{name,color,isHost,you}`. The existing `LobbyStateDto` is shaped `{PlayerIds,PlayerNames,...}` — DIFFERENT. So add a **web-shaped** lobby DTO (below) rather than reuse `LobbyStateDto`.

---

## 4. Stage 2 implementation steps

### 4a. WebControllerServer: serve the SPA (replaces the embedded controller page)
- Add `private string _webRoot;`. In `StartServer(port)` (runs on Unity main thread) set
  `_webRoot = System.IO.Path.Combine(Application.streamingAssetsPath, "web");`
  (Must be read on main thread — `Application.streamingAssetsPath` is a Unity API.)
- In `HandleConnection`, for a non-WebSocket GET, parse the path from the request line
  (`GET /path HTTP/1.1`), strip query, default `/`→`index.html`, **reject any `..`**, and
  serve `Path.Combine(_webRoot, relPath)` with `File.ReadAllBytes`. 404 if missing.
- Content types: `.html`→`text/html; charset=utf-8`, `.js`→`application/javascript`,
  `.css`→`text/css`, `.svg`→`image/svg+xml`, `.png`→`image/png`, else `application/octet-stream`.
- The old `ControllerPageHtml` const can be deleted once file serving works.

### 4b. WebControllerServer: inbound translation
- Extend the `WebInbound` `[Serializable]` class with: `public string code; public string color; public int avatar; public string[] games; public string mode;`
- In `HandleWsText`, translate the new `t` values into `NetworkMessage`s (use new `MessageType`s — see 4c) carrying a JSON DTO in `Payload`, then enqueue via `MainThreadDispatcher` to `MessageReceived` (set `SenderId = conn.Id`, authoritative). Keep existing `tap`/`bid`.

### 4c. Protocol DTOs + MessageType (in `Networking/`)
- Add `MessageType` values: `CreateRoom, JoinRoom, Profile, StartPick, PickStart, Leave, RoomCreated, WebLobby, GoPick` (append; don't renumber existing).
- Add DTOs in `Dtos.cs`:
  - `WebPlayerDto { string id; string name; string color; bool isHost; bool you; int avatar; }`
  - `WebLobbyDto { WebPlayerDto[] players; string code; string hostName; bool premium; }`
  - `CreateRoomDto/JoinRoomDto { string name; string color; int avatar; string code; }`
  - `PickStartDto { string[] games; string mode; }`
- In `WebControllerServer.BuildWebFrame`, map `RoomCreated→"roomCreated"`, `WebLobby→"lobby"`, `GoPick→"goPick"` (in addition to existing joined/lobby/game/bidding/results).

### 4d. AppRoot: host/session wiring
Read the CURRENT `AppRoot.cs` first — it now boots `DisplayManager`, has a big IMGUI/“tiki” HUD, a `MatchDirector`, `BiddingSystem`, and uses `IMiniGame.HandleInput(string playerId, string action)` (NOTE the 2-arg signature). Then:
- On host start, generate a room code (e.g., 4 of `ABCDEFGHJKLMNPQRSTUVWXYZ`); show it on the TV/IMGUI view and store on `SessionData`.
- Handle the new web messages in the existing `OnHostMessage(NetworkMessage)` switch:
  - `CreateRoom`/`JoinRoom`/`Profile` → create/update `PlayerData` (the web sends name/color/avatar; add `Color`/`AvatarIndex` to `PlayerData` if missing). Reply `RoomCreated` to that client; broadcast `WebLobby` to all.
  - `PickStart` → map `games` keys→catalog ids (4-table above), set `SessionData.SelectedMiniGames`, and start the match via `MatchDirector` (it currently auto-cycles the catalog — make it consume `SelectedMiniGames` when present). Then broadcast match start as today.
  - `Leave` → remove player; broadcast `WebLobby`.
- Add `BuildWebLobby()` → `WebLobbyDto` from `SessionData.Players` (+ code, host name, `IsPremiumHost`), broadcast via both transports (`_host` TCP + `_web`). Reuse the existing fan-out helper (e.g. `HostBroadcast`).
- Keep the Unity-app TCP controllers (`TcpHostService`) working in parallel (web + app feed the same session).

### 4e. Sync `web/` ⇄ StreamingAssets
After editing `web/index.html`/`web/app.js`, copy them to `Assets/StreamingAssets/web/` (the host serves from StreamingAssets).

---

## 5. Build / run / verify

- **Open in Unity `6000.3.18f1`** (Unity Hub installed at `C:\Program Files\Unity Hub`). A free Unity account/license must be active to open the editor (user’s step).
- **Run:** press Play (the app self-boots via `AppRoot` `[RuntimeInitializeOnLoadMethod]`, no scene wiring). Host starts TCP `7777` + web `8080`.
- **Phone test:** host on PC, open `http://<PC-LAN-IP>:8080` on a phone on the same Wi‑Fi (allow the app through Windows Firewall on Private networks). `localhost:8080` works on the PC itself.

### Compile-check C# WITHOUT a license (use this to verify your edits)
Unity ships a Roslyn compiler; compile `Assets/Scripts` against the editor DLLs. PowerShell:
```powershell
$ed='C:\Program Files\Unity\Hub\Editor\6000.3.18f1\Editor\Data'
$cscDll="$ed\DotNetSdkRoslyn\csc.dll"; $dotnet="$ed\NetCoreRuntime\dotnet.exe"
$ns="$ed\NetStandard\ref\2.1.0\netstandard.dll"; $ueDir="$ed\Managed\UnityEngine"
$out="$env:TEMP\ma_cc.dll"
$src=Get-ChildItem 'C:\Users\al3aa\Desktop\Projects\Mini_Arcade\Assets\Scripts' -Recurse -Filter *.cs | Select-Object -ExpandProperty FullName
$lines=@('-target:library','-nostdlib+','-warn:0',('-out:"'+$out+'"'),('-r:"'+$ns+'"'))
Get-ChildItem $ueDir -Filter *.dll | ForEach-Object { $lines += ('-r:"'+$_.FullName+'"') }
foreach($s in $src){ $lines += ('"'+$s+'"') }
$rsp="$env:TEMP\ma_cc.rsp"; Set-Content -Path $rsp -Value $lines -Encoding ASCII
& $dotnet $cscDll ('@'+$rsp); "EXIT=$LASTEXITCODE"
```
`EXIT=0` = clean. NOTE: `UnityEngine.UI` is NOT in those DLLs, so don’t use uGUI in scripts you compile this way — the project UI is IMGUI + the web app. (The web app needs no Unity compile.)

### Preview the web app (no Unity needed)
`.claude/launch.json` runs `python -m http.server 5173 --directory web`. Use the Claude Preview MCP (`preview_start` name `webui`, then `preview_list` for serverId).
**GOTCHA:** the preview *screenshot* tool returns **stale** frames here. Verify with `preview_eval` (e.g. `location.reload(true)`, then click-through via `.click()` + `getBoundingClientRect`) and `preview_inspect` (computed styles). Don’t trust screenshots.

---

## 6. Gotchas / facts
- iOS build impossible on Windows; this is an Editor/Windows prototype. Production target is iOS (Mac + Xcode) + external display (AirPlay/HDMI) via `DisplayManager`.
- Unity Hub CLI on this machine prints a TLS “unable to verify the first certificate” error and exits 1 but still installs — verify on disk, not by exit code.
- The Unity gameplay/networking code evolved across sessions (real `MiniGolf` mini-game; `IMiniGame.HandleInput(playerId, action)`; tiki HUD; `DisplayManager`; `BiddingStateDto.HasSubmitted`). **Always read the current file before editing.**
- Memory notes for this project live in the agent memory: `mini-arcade-unity-setup`, `mini-arcade-web-ui`, `unity-hub-tls-download-quirk`.

## 7. Definition of done for Stage 2
1. Phone opens `http://<host-ip>:8080` and sees the **identical** web UI served by the running Unity host.
2. Web “Host a Game” → Create Room shows a real room code (from Unity) and a lobby that updates as phones join over `8080` (and as Unity-app controllers join over `7777`).
3. Web “Let’s Go!” starts the 3-round match using the picked games (mapped), playable via the existing controller/bidding flow.
4. `Assets/Scripts` compiles clean (EXIT=0) via the command in §5.
