// Full-game end-to-end smoke test.
//
//   FAST_GAME=1 tsx scripts/smoke.ts
//
// Spins up the real server on a test port, then drives a host (who is also the
// TV board) and three phones through the data-driven lineup:
//   lobby -> auction(golf/anvil) -> golf -> auction(bomb/butter) -> bomb
//         -> auction(golf/anvil) -> golf -> podium -> replay -> back to start.
// It also verifies the NEW hidden-economy rules:
//   - score is gone; players have public `trophies` + private `coins`,
//   - a client only ever sees its OWN real coins (everyone else's are masked 0),
//   - mini-games award trophies (+ bank coins), and the podium ranks by trophies.
// Exits 0 on success, 1 on any failed assertion.

import WebSocket from "ws";
import { startServer } from "../src/server.js";
import type { RoomState } from "../src/protocol.js";

const PORT = 8090;
const URL = `ws://127.0.0.1:${PORT}`;

let failures = 0;
function ok(cond: boolean, label: string) {
  if (cond) {
    console.log(`  ✓ ${label}`);
  } else {
    failures += 1;
    console.error(`  ✗ ${label}`);
  }
}

type Json = Record<string, any>;

class TestClient {
  ws!: WebSocket;
  state: RoomState | null = null;
  playerId = "";
  token = "";
  inbox: Json[] = [];
  private waiters: { pred: (m: Json) => boolean; resolve: (m: Json) => void }[] = [];
  private stateWaiters: { pred: (s: RoomState) => boolean; resolve: (s: RoomState) => void }[] = [];

  constructor(public label: string) {}

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(URL);
      this.ws.on("open", () => resolve());
      this.ws.on("error", reject);
      this.ws.on("message", (data) => {
        const msg: Json = JSON.parse(data.toString());
        if (msg.t === "room_joined") {
          this.playerId = msg.playerId;
          this.token = msg.token;
          this.applyState(msg.state);
        } else if (msg.t === "room_state") {
          this.applyState(msg.state);
        }
        this.inbox.push(msg);
        this.waiters = this.waiters.filter((w) => {
          if (w.pred(msg)) {
            w.resolve(msg);
            return false;
          }
          return true;
        });
      });
    });
  }

  private applyState(s: RoomState) {
    this.state = s;
    this.stateWaiters = this.stateWaiters.filter((w) => {
      if (w.pred(s)) {
        w.resolve(s);
        return false;
      }
      return true;
    });
  }

  send(msg: Json) {
    this.ws.send(JSON.stringify(msg));
  }

  waitForMsg(pred: (m: Json) => boolean, what: string, timeoutMs = 10_000): Promise<Json> {
    const hit = this.inbox.find(pred);
    if (hit) return Promise.resolve(hit);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`${this.label}: timed out waiting for ${what}`)),
        timeoutMs,
      );
      this.waiters.push({
        pred,
        resolve: (m) => {
          clearTimeout(timer);
          resolve(m);
        },
      });
    });
  }

  waitForState(pred: (s: RoomState) => boolean, what: string, timeoutMs = 10_000): Promise<RoomState> {
    if (this.state && pred(this.state)) return Promise.resolve(this.state);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`${this.label}: timed out waiting for ${what}`)),
        timeoutMs,
      );
      this.stateWaiters.push({
        pred,
        resolve: (s) => {
          clearTimeout(timer);
          resolve(s);
        },
      });
    });
  }

  /** Public trophy count for `id` (visible to everyone). */
  trophies(state: RoomState, id: string): number {
    return state.players.find((p) => p.id === id)?.trophies ?? -1;
  }

  /**
   * Coins for `id` AS SEEN in `state`. Only meaningful for the viewer's own id —
   * every other player's coins are masked to 0 by the server.
   */
  coins(state: RoomState, id: string): number {
    return state.players.find((p) => p.id === id)?.coins ?? -1;
  }

  /** This client's own real coin wallet, from its latest snapshot. */
  myCoins(): number {
    return this.coins(this.state!, this.playerId);
  }
}

async function main() {
  const server = startServer(PORT);
  const host = new TestClient("host");
  const alice = new TestClient("alice");
  const bob = new TestClient("bob");
  const cara = new TestClient("cara");
  const all = [host, alice, bob, cara];

  await Promise.all(all.map((c) => c.connect()));

  // ---- reusable: drive a full 3-round golf segment; `order` is the sink order ----
  async function playGolfSegment(tag: string): Promise<RoomState> {
    for (let round = 1; round <= 3; round++) {
      await host.waitForState((s) => s.phase === "golf" && s.golf?.round === round, `${tag}: round ${round}`);
      for (const shooter of [alice, host, bob]) {
        host.send({ t: "golf_progress", turnId: shooter.playerId, sunk: [] });
        await shooter.waitForState(
          (s) => s.golf?.turnId === shooter.playerId,
          `${tag}: ${shooter.label}'s turn (r${round})`,
        );
        const before = shooter.state!.golf!.strokes[shooter.playerId] ?? 0;
        shooter.send({ t: "fire", angle: 0.7, power: 1.0 }); // full power → satisfies "The Long Shot"
        await shooter.waitForState(
          (s) => (s.golf!.strokes[shooter.playerId] ?? 0) > before,
          `${tag}: ${shooter.label} stroke counted (r${round})`,
        );
      }
      host.send({ t: "golf_finished", order: [alice.playerId, bob.playerId, host.playerId] });
      if (round < 3) {
        await host.waitForState((s) => s.golf?.round === round + 1, `${tag}: → round ${round + 1}`);
      }
    }
    return host.waitForState((s) => !!s.golf?.results, `${tag}: final results`);
  }

  // ---- reusable: everyone passes the bomb right until it finishes at 2 survivors ----
  async function playBombSegment(): Promise<RoomState> {
    await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "bomb", "bomb phase")));
    const loops = all.map((c) =>
      setInterval(() => {
        const b = c.state?.bomb;
        if (c.state?.phase === "bomb" && b?.stage === "ticking" && b.holderId === c.playerId) {
          c.send({ t: "pass_bomb", direction: "right" });
        }
      }, 80),
    );
    const done = await host.waitForState((s) => s.bomb?.stage === "done", "bomb finishes", 30_000);
    // The "done" broadcast is the one that banks coins — wait for EVERY client to
    // process it before anyone reads their own wallet (avoids a propagation race).
    await Promise.all(all.map((c) => c.waitForState((s) => s.bomb?.stage === "done", `${c.label} sees bomb done`)));
    loops.forEach(clearInterval);
    return done;
  }

  // ---- reusable: a no-sale auction (everyone bids 0) that just advances the lineup ----
  async function passAuction(round: number, sabotageId: string) {
    await Promise.all(
      all.map((c) => c.waitForState((s) => s.phase === "auction" && s.auction?.round === round, `auction ${round}`)),
    );
    ok(host.state!.auction!.items.length === 2, `auction ${round} puts up two lots (sabotage + advantage)`);
    ok(
      host.state!.auction!.items.some((it) => it.id === sabotageId && it.type === "sabotage"),
      `auction ${round} offers the ${sabotageId} sabotage`,
    );
    all.forEach((c) => c.send({ t: "submit_bid", amount: 0, itemId: sabotageId }));
  }

  console.log("\n— lobby —");
  host.send({ t: "create_room", name: "Host", avatar: "🦊", color: "#FF2E88" });
  await host.waitForMsg((m) => m.t === "room_joined", "room_joined");
  const code = host.state!.code;
  ok(/^[A-Z]{4}$/.test(code), `room code looks right (${code})`);

  alice.send({ t: "join_room", code, name: "Alice", avatar: "🐸", color: "#00F5D4" });
  bob.send({ t: "join_room", code, name: "Bob", avatar: "🐼", color: "#FEE440" });
  cara.send({ t: "join_room", code, name: "Cara", avatar: "🦄", color: "#9B5DE5" });
  await Promise.all([alice, bob, cara].map((c) => c.waitForMsg((m) => m.t === "room_joined", "join")));
  await host.waitForState((s) => s.players.length === 4, "4 players in lobby");
  ok(host.state!.players.length === 4, "host sees 4 players");
  ok(host.state!.players.every((p) => p.trophies === 0), "everyone starts with 0 trophies");
  ok(all.every((c) => c.myCoins() === 1000), "each player starts with a private 1000-coin wallet");
  ok(alice.coins(alice.state!, bob.playerId) === 0, "PRIVACY: other players' coins are masked to 0 on every client");

  console.log("\n— game selection (host curates the lineup) —");
  host.send({ t: "start_game" });
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "selection", "selection phase")));
  ok(host.state!.selection!.size === 3, "the host must pick 3 games");
  // A non-host cannot commit a lineup.
  alice.send({ t: "select_lineup", lineup: ["golf", "bomb", "bumper"] });
  await new Promise((r) => setTimeout(r, 150));
  ok(host.state!.phase === "selection", "a non-host cannot start the match");
  // Host live-previews picks — the TV mirrors the slots filling up.
  host.send({ t: "preview_lineup", lineup: ["golf"] });
  await host.waitForState((s) => (s.selection?.picks.length ?? 0) === 1, "first pick mirrors to the room");
  ok(host.state!.selection!.picks[0] === "golf", "slot 1 shows golf on every device");
  // An over-long or invalid submit is rejected.
  host.send({ t: "select_lineup", lineup: ["golf", "bomb"] });
  await new Promise((r) => setTimeout(r, 100));
  ok(host.state!.phase === "selection", "a lineup that isn't exactly 3 games is rejected");
  // Host commits the full lineup → the match begins.
  host.send({ t: "select_lineup", lineup: ["golf", "bomb", "bumper"] });

  console.log("\n— auction 1 (golf): SABOTAGE lot wins, picks a target —");
  await Promise.all(
    all.map((c) => c.waitForState((s) => s.phase === "auction" && s.auction?.round === 1, "auction 1")),
  );
  ok(host.state!.auction!.items.length === 2, "the auction puts up two lots");
  ok(host.state!.auction!.items.some((it) => it.id === "anvil" && it.type === "sabotage"), "a golf sabotage (Heavy Anvil) is on offer");
  ok(host.state!.auction!.items.some((it) => it.id === "golden_club" && it.type === "advantage"), "a golf advantage (Golden Club) is on offer");
  ok(host.state!.lineup.length === 3, "the committed lineup holds 3 games");

  host.send({ t: "submit_bid", amount: 100, itemId: "golden_club" }); // wants the buff
  alice.send({ t: "submit_bid", amount: 250, itemId: "anvil" });       // wants to sabotage
  bob.send({ t: "submit_bid", amount: 50, itemId: "anvil" });
  cara.send({ t: "submit_bid", amount: 0, itemId: "anvil" });
  const targeting = await alice.waitForState((s) => s.auction?.stage === "targeting", "auction targeting");
  ok(targeting.auction!.winnerId === alice.playerId, "Alice (250) wins the auction");
  ok(targeting.auction!.winningItemId === "anvil", "she won the sabotage lot → must pick a target");
  ok(alice.myCoins() === 750, "Alice paid her 250-coin bid out of her private wallet");
  ok(host.myCoins() === 1000, "losing bidders pay nothing");

  alice.send({ t: "choose_target", targetId: bob.playerId });
  const reveal = await host.waitForState((s) => s.auction?.stage === "reveal", "auction reveal");
  ok(reveal.players.find((p) => p.id === bob.playerId)?.modifier === "anvil", "Bob carries the anvil debuff");

  console.log("\n— golf segment 1 (Guerilla → Tiki → Runway) —");
  await host.waitForState((s) => s.phase === "golf" && s.golf?.round === 1, "golf round 1");
  ok(host.state!.golf!.map === "guerilla", "round 1 is the Guerilla map");
  ok(host.state!.players.find((p) => p.id === bob.playerId)?.modifier === "anvil", "Bob's anvil modifier is public for the board");

  // Off-turn fire must be ignored by the server (not relayed, no stroke counted).
  host.send({ t: "golf_progress", turnId: alice.playerId, sunk: [] });
  await bob.waitForState((s) => s.golf?.turnId === alice.playerId, "phones learn it's Alice's turn");
  bob.send({ t: "fire", angle: 1.2, power: 0.9 });
  await new Promise((r) => setTimeout(r, 200));
  ok(
    !host.inbox.some((m) => m.t === "fire" && m.playerId === bob.playerId),
    "off-turn fire is blocked by the server",
  );
  ok((bob.state!.golf!.strokes[bob.playerId] ?? 0) === 0, "off-turn fire never counts a stroke");

  // Coin pickups — the host board registers the round's loose coins, then
  // reports a ball running into one.
  host.send({ t: "register_coins", coins: [{ id: "coin-0", x: 0, y: 0.6, z: 6 }, { id: "coin-1", x: 1.2, y: 0.6, z: -3 }] });
  await host.waitForState((s) => (s.golf?.spawnedCoins?.length ?? 0) === 2, "coins registered on the course");
  bob.send({ t: "collect_coin", coinId: "coin-0", playerId: bob.playerId }); // non-host
  await new Promise((r) => setTimeout(r, 120));
  ok((host.state!.golf?.spawnedCoins?.length ?? 0) === 2, "a non-host cannot collect coins");
  const aliceCoinsBeforePickup = alice.myCoins();
  host.send({ t: "collect_coin", coinId: "coin-0", playerId: alice.playerId });
  await alice.waitForState((s) => (s.golf?.spawnedCoins?.length ?? 0) === 1, "collected coin removed from the course");
  ok(alice.myCoins() === aliceCoinsBeforePickup + 50, "collecting a coin credits +50 to that player's PRIVATE wallet");
  host.send({ t: "collect_coin", coinId: "coin-1", playerId: alice.playerId }); // 2nd coin → "Greedy Golfer"
  await alice.waitForState((s) => (s.golf?.spawnedCoins?.length ?? 0) === 0, "alice grabbed both coins");

  // Secret tasks — one assigned per player at golf start, PRIVATE to each phone.
  const task = alice.state!.players.find((p) => p.id === alice.playerId)?.secretTask;
  ok(!!task, "alice was assigned a private secret task at golf start");
  ok(
    alice.state!.players.find((p) => p.id === bob.playerId)?.secretTask == null,
    "PRIVACY: a player can't see anyone else's secret task",
  );
  ok(
    host.state!.players.find((p) => p.id === alice.playerId)?.secretTask == null,
    "PRIVACY: the TV/host snapshot never carries a player's task",
  );
  const aliceCoinsBeforeTask = alice.myCoins();

  const golf1 = await playGolfSegment("golf 1");
  await alice.waitForState((s) => !!s.golf?.results, "alice sees the golf results");
  const doneTask = alice.state!.players.find((p) => p.id === alice.playerId)?.secretTask;
  ok(doneTask?.isCompleted === true, "alice completed her task (full-power shot + 2 coins + no reset all hold)");
  ok(alice.myCoins() === aliceCoinsBeforeTask + 150, "completing the task quietly credited +150 to alice's wallet");
  ok(golf1.golf!.results!.order[0] === alice.playerId, "fewest total strokes (Alice) wins the match");
  ok(golf1.golf!.results!.awarded[alice.playerId] === 1, "the golf winner is awarded exactly 1 trophy");
  ok(golf1.golf!.results!.awarded[bob.playerId] === undefined || golf1.golf!.results!.awarded[bob.playerId] === 0, "non-winners get no trophy from golf");
  ok(host.trophies(host.state!, alice.playerId) === 1, "Alice's trophy is public on every client");
  ok(golf1.players.find((p) => p.id === bob.playerId)?.modifier === null, "anvil consumed after the golf segment");

  console.log("\n— auction 2 (bomb): ADVANTAGE lot wins, self-applied —");
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "auction" && s.auction?.round === 2, "auction 2")));
  ok(host.state!.auction!.items.some((it) => it.id === "hazmat" && it.type === "advantage"), "a bomb advantage (Hazmat Suit) is on offer");
  host.send({ t: "submit_bid", amount: 0, itemId: "butter" });
  alice.send({ t: "submit_bid", amount: 0, itemId: "butter" });
  bob.send({ t: "submit_bid", amount: 0, itemId: "butter" });
  cara.send({ t: "submit_bid", amount: 300, itemId: "hazmat" }); // buys the buff for herself
  const advReveal = await host.waitForState((s) => s.auction?.stage === "reveal" && s.auction?.winnerId === cara.playerId, "advantage reveal");
  ok(advReveal.auction!.winningItemId === "hazmat", "Cara won the advantage lot");
  ok(advReveal.auction!.targetId === null, "an advantage skips target selection entirely");
  ok(advReveal.players.find((p) => p.id === cara.playerId)?.modifier === "hazmat", "the buff is applied directly to Cara");

  console.log("\n— the billionaire's bomb (cash → private coins) —");
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "bomb", "bomb phase")));
  // Fresh secret tasks for the bomb, still private per player.
  ok(!!alice.state!.players.find((p) => p.id === alice.playerId)?.secretTask, "bomb: alice has a private secret task");
  ok(
    alice.state!.players.find((p) => p.id === bob.playerId)?.secretTask == null,
    "bomb: other players' secret tasks stay masked",
  );
  const coinsBeforeBomb = Object.fromEntries(all.map((c) => [c.playerId, c.myCoins()]));
  const bombDone = await playBombSegment();
  ok(bombDone.bomb!.survivors!.length === 2, "exactly two players survive the bomb");
  ok(bombDone.bomb!.eliminated.length === 2, "exactly two players are eliminated");
  // Golf gave out 1 trophy; the bomb gives 1 to each of the 2 survivors → 3 total.
  const totalTrophiesAfterBomb = host.state!.players.reduce((n, p) => n + p.trophies, 0);
  ok(totalTrophiesAfterBomb === 3, "trophies total 3 (1 golf winner + 2 bomb survivors)");
  const survivorsBanked = bombDone.bomb!.survivors!.every((id) => {
    const client = all.find((c) => c.playerId === id)!;
    return client.myCoins() >= coinsBeforeBomb[id] + 250; // survival bonus + greedy earnings, into their wallet
  });
  ok(survivorsBanked, "survivors banked their bomb cash + 250 bonus into their PRIVATE coins");

  console.log("\n— auction 3 (bumper): dedicated lots, no sale —");
  await passAuction(3, "flat_tire"); // bumper now has its own sabotage + advantage

  console.log("\n— bumper sumo arena (real-time joystick + knockouts) —");
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "bumper", "bumper phase")));
  ok(host.state!.bumper!.alive.length === 4, "all four players start on the slab");
  ok(!!alice.state!.players.find((p) => p.id === alice.playerId)?.secretTask, "bumper: alice has a private secret task");
  ok(
    alice.state!.players.find((p) => p.id === bob.playerId)?.secretTask == null,
    "bumper: other players' tasks stay masked",
  );
  // Joystick vectors stream to the host board (relay, not broadcast).
  alice.send({ t: "update_joystick", x: 0.5, y: -0.5 });
  const relay = await host.waitForMsg((m) => m.t === "joystick" && m.playerId === alice.playerId, "joystick relay");
  ok(Math.abs(relay.x - 0.5) < 1e-9, "the host board receives the streamed joystick vector");
  const aliceCoinsBeforeBumper = alice.myCoins();
  // Host board shoves everyone else off — alice is the last one standing.
  host.send({ t: "bumper_knockout", playerId: bob.playerId, byPlayerId: alice.playerId });
  await host.waitForState((s) => s.bumper?.eliminated.includes(bob.playerId) ?? false, "bob splashed");
  host.send({ t: "bumper_knockout", playerId: cara.playerId, byPlayerId: alice.playerId });
  host.send({ t: "bumper_knockout", playerId: host.playerId, byPlayerId: alice.playerId });
  await alice.waitForState(
    (s) => s.players.find((p) => p.id === alice.playerId)?.secretTask?.isCompleted === true,
    "alice completed her bumper task (aggressor + last standing)",
  );
  ok(alice.myCoins() === aliceCoinsBeforeBumper + 150, "bumper task reward (+150) credited to alice");

  console.log("\n— podium —");
  const podiumState = await host.waitForState((s) => s.phase === "podium", "podium");
  const podium = podiumState.podium!;
  ok(podium.ranking.length === 4, "podium ranks all 4 players");
  const totalTrophies = podiumState.players.reduce((n, p) => n + p.trophies, 0);
  ok(totalTrophies === 4, "trophies total 4 across the match (golf winner + 2 bomb survivors + bumper winner)");
  const rankTrophies = podium.ranking.map((id) => host.trophies(podiumState, id));
  ok(
    rankTrophies.every((t, i) => i === 0 || rankTrophies[i - 1] >= t),
    "podium is ordered by trophies (descending) — coins are the hidden tiebreak",
  );

  console.log("\n— replay —");
  all.forEach((c) => c.send({ t: "replay" }));
  const restarted = await host.waitForState(
    (s) => s.phase === "selection",
    "replay loops back to game selection",
  );
  // Wait for every client to receive the reset (selection) broadcast before
  // reading their own wallet.
  await Promise.all(
    all.map((c) => c.waitForState((s) => s.phase === "selection", `${c.label} sees replay`)),
  );
  ok(restarted.players.every((p) => p.trophies === 0), "trophies reset to 0 on replay");
  ok(all.every((c) => c.myCoins() === 1000), "coin wallets reset to 1000 on replay");

  console.log("");
  all.forEach((c) => c.ws.close());
  server.close();

  if (failures > 0) {
    console.error(`SMOKE FAILED — ${failures} assertion(s) failed`);
    process.exit(1);
  }
  console.log("SMOKE PASSED — hidden-economy + data-driven lineup work end to end 🎉");
  process.exit(0);
}

main().catch((err) => {
  console.error("SMOKE FAILED —", err.message ?? err);
  process.exit(1);
});
