# Game Design & Technical Specification Document
## Project: Asymmetric Local Multiplayer Party Game

---

## 1. Executive Summary & Core Concept
This document establishes the official technical blueprint and design scaffolding for an asymmetric, local multiplayer mobile party game inspired by titles like *Frantics* (PS4) and *Madagascar: Escape 2 Africa* mini-games. 

The core signature of this experience is its barrier-to-entry accessibility: it removes the need for a traditional gaming console. Instead, a single iPhone acts as the **Host**, outputting the primary gameplay graphics to a shared television screen via AirPlay Screen Mirroring or a physical HDMI connection. All other players connect using their own iPhones, which transform into private, dynamic game controllers. The television serves as the central, public visual arena, while each player’s phone screen displays a specialized, uncluttered interface tailored specifically to their immediate needs.

---

## 2. Onboarding Flow & Authentication
Upon launching the application, the user is presented with an initial gateway screen designed to maximize accessibility while preserving premium user data.

* **Authentication Options:**
    * **Play as Guest:** The default onboarding path. Users can immediately access the local multiplayer lobby, host a game, or join an existing room without creating an account or entering credentials.
    * **Login / Sign In:** A dedicated option primarily reserved for premium users. 
* **Sign-In Logic:** Account creation and login are entirely optional. Users do not need to sign in to experience the core game loops. Authentication is strictly used to bind, sync, and restore premium in-app subscription purchases across multiple devices or after re-installing the application.

---

## 3. Network Architecture & Latency Management
The fundamental technical challenge of this architecture is mitigating the inherent transmission lag introduced by wireless display protocols (such as AirPlay Screen Mirroring), which can reach between 100ms and 500ms. To maintain crisp, responsive real-time gameplay controls, the network topology is structured as follows:

* **Local Network Topology:**
    * The **Host iPhone** serves as both the central processing server and the visual graphics router.
    * The Host spins up a localized network session (utilizing a high-performance local network framework such as low-latency WebSockets or UDP via a local socket server).
    * All **Client iPhones** (Players) must connect to the **exact same local Wi-Fi network** as the Host iPhone to discover and join the room.
* **Input Synchronization:**
    * When a player interacts with their phone controller, the input command is transmitted directly to the Host iPhone over local IP addresses.
    * Because these packets travel strictly within the local Wi-Fi router space, input latency between the controller and the Host processor is negligible (<16ms).
* **Dual-Screen Video Output:**
    * The game is developed using an engine (such as Unity via its Universal Render Pipeline or Flutter) capable of native **External Display Support**.
    * When an external display (TV via AirPlay or HDMI) is detected, the engine separates its visual outputs.
    * The high-fidelity, animated 3D/2D game world is rendered and routed exclusively out of the iPhone’s video-out port to the TV screen. 
    * The physical iPhone screen of the Host changes instantly from a duplicative view to a dedicated, master control interface.

---

## 4. Asymmetric Screen Layouts & UI Mapping
The game relies entirely on asymmetric distribution of information: what is visible on the television is public, while what is visible on individual phone screens is completely private.

### 4.1 The TV Screen (Public View)
The TV displays the shared world that all players watch simultaneously. It is highly animated and contains zero private player data.
* **The Game Lobby:** Displays the room joining status, showing connected character avatars as players join the Host’s network room.
* **The Mini-Game Selector:** A horizontally scrolling menu of available mini-games. While the selection action is controlled by the Host, the scrolling animation is rendered beautifully on the big screen for everyone to track.
* **Gameplay Arena:** Renders the active mini-games (e.g., a 3D golf course, physics-based racing, or platforming challenges) including character movements, scores, timers, and environmental animations.
* **Public Announcements:** Displays round outcomes, final rankings, and public tie-breaker conclusions.

### 4.2 The iPhone Screens (Private Views)
The individual phone screens are stripped of heavy graphics and act purely as tactical, uncluttered controllers. The interface changes dynamically depending on the active game state:
* **The Host Phone:** Features unique master control overlays. During setup, it displays touch-interactive horizontally scrolling menus to select the three mini-games, start the match, or manage player slots.
* **Player Phones (General Controllers):** The UI dynamically updates based on the active mini-game requirements. For example, during a golf mini-game, the phone displays simple touch scrollers for power adjustments or arrow buttons for aiming.
* **Secret Task Overlays:** If a player receives a "special secret task" to earn extra coins, this assignment is pushed exclusively to that specific player's phone screen, ensuring no opponents looking at the TV can see it.

---

## 5. Game Loop & Bidding Economy
A single gaming session progresses through a structured, highly competitive loop designed to balance mechanical skill with psychological strategy.

```
[Lobby Setup] ➔ [Host Picks 3 Mini-Games] ➔ [Mini-Game 1] ➔ [Secret Bidding Phase]
                                                  ▲                    │
                                                  │                    ▼
                                          [Final Results] ◀─── [Mini-Game 2 & 3]
```

### 5.1 The Initialization & Coin Reset
* At the absolute beginning of a new game session, all players start with exactly **zero coins**.
* There is no financial advantage, bidding, or monetization-based equity available at startup. Everyone enters the first match on a completely level playing field.

### 5.2 Wealth Accumulation (In-Game Economy)
Coins are the core currency of the session and can only be obtained actively during live gameplay through three explicit methods:
1.  **Direct Gameplay Collection:** Coins are distributed randomly across the mini-game maps (e.g., floating on a golf course or dropped in an arena), allowing players to physically gather them during a match.
2.  **Match Placement:** Winning a mini-game or placing in top tiers awards a fixed coin payout at the conclusion of the round.
3.  **Special Secret Tasks:** Random or targeted secret assignments are pushed directly to a player's phone controller screen. Successfully executing this hidden task during the chaotic public match awards a substantial coin bonus.

### 5.3 The Hidden Bidding Phase
* **Timing:** The bidding economy remains completely locked and unavailable until a mini-game round successfully concludes. 
* **Asymmetric Privacy:** Between mini-game rounds, a blind bidding window opens. Each player has a different amount of accumulated money depending on their performance. The exact financial balance of each player is **kept entirely secret**—it is hidden from the TV screen and cannot be viewed by opponents on any interface, ensuring complete strategic surprise.
* **Mechanic:** Players secretly allocate their hidden coins via their phone controllers to bid on distinct advantages for the upcoming match or to purchase explicit sabotage tools directed at leading opponents.

### 5.4 Victory & Tie-Breaker Conditions
* The primary victory condition is determined by **total match wins** across the selected mini-games.
* In the event of a tie where multiple players hold an equal number of mini-game victories, the system executes a secondary evaluation: the player who holds the **highest total number of coins accumulated** throughout the entire game wins the match.

---

## 6. Monetization Framework & Gating Logic
The game utilizes a friction-free, host-centric freemium model that maximizes download volumes while cleanly incentivizing conversion to a premium tier.

* **Free-to-Play Tier (The Baseline):**
    * The app is entirely free to download from the App Store.
    * Free sessions are limited to a maximum of **two (2) players** and a rotation of **three (3) specific mini-games**.
    * To monetize non-paying users, programmatic advertisements are served exclusively **between each game match**.
* **Premium In-App Subscription:**
    * Unlocks the ability to host games with more than two players (expanded party limits).
    * Grants full access to the complete library of available mini-games.
    * Completely removes all interstitial advertisements between matches.
* **Subscription Architecture & Gating Rule:**
    * **Host-Centric Gating:** Only the Host iPhone needs an active premium subscription to unlock the full room capacity and premium games for the entire group. Client players joining a premium host do not need to purchase a subscription to enjoy the expanded session content.
    * **Account-Free Persistence:** Users playing on the free tier or hosting standard games are not subjected to any mandatory registration or profile creation. The application only requires an account sign-in when a user purchases a subscription and subsequently needs to **restore a purchase** on a new device or following a factory reset.