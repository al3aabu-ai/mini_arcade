// Full-game end-to-end smoke test.
//
//   FAST_GAME=1 tsx scripts/smoke.ts
//
// Spins up the real server on a test port, then drives a host (who is also
// the TV board) and three phones through: lobby -> auction 1 (anvil) ->
// golf -> auction 2 (butter) -> bomb (down to 2 survivors) -> podium ->
// replay -> back to auction 1. Exits 0 on success, 1 on any failed assertion.

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

  score(state: RoomState, id: string): number {
    return state.players.find((p) => p.id === id)?.score ?? -1;
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
  ok(host.state!.players.every((p) => p.score === 1000), "everyone starts with 1000 points");

  console.log("\n— auction round 1 (anvil) —");
  host.send({ t: "start_game" });
  await Promise.all(
    all.map((c) => c.waitForState((s) => s.phase === "auction" && s.auction?.round === 1, "auction 1")),
  );
  ok(host.state!.auction!.item.debuff === "anvil", "round 1 item is the Heavy Anvil");

  host.send({ t: "submit_bid", amount: 100 });
  alice.send({ t: "submit_bid", amount: 250 });
  bob.send({ t: "submit_bid", amount: 50 });
  cara.send({ t: "submit_bid", amount: 0 });
  const targeting = await alice.waitForState(
    (s) => s.auction?.stage === "targeting",
    "auction targeting stage",
  );
  ok(targeting.auction!.winnerId === alice.playerId, "Alice (250) wins the auction");
  ok(alice.score(targeting, alice.playerId) === 750, "Alice paid her 250-point bid");
  ok(alice.score(targeting, host.playerId) === 1000, "losing bidders pay nothing");

  alice.send({ t: "choose_target", targetId: bob.playerId });
  const reveal = await host.waitForState((s) => s.auction?.stage === "reveal", "auction reveal");
  ok(reveal.auction!.targetId === bob.playerId, "Bob is the anvil target");
  ok(reveal.players.find((p) => p.id === bob.playerId)?.debuff === "anvil", "Bob carries the anvil debuff");

  console.log("\n— guerilla golf —");
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "golf", "golf phase")));
  ok(host.state!.golf!.debuffs[bob.playerId] === "anvil", "board is told about Bob's anvil");

  alice.send({ t: "aim", angle: 0.9, power: 0.5 });
  const aimRelay = await host.waitForMsg((m) => m.t === "aim" && m.playerId === alice.playerId, "aim relay");
  ok(Math.abs(aimRelay.power - 0.5) < 1e-9, "host board receives Alice's aim relay");
  alice.send({ t: "fire", angle: 0.9, power: 1.0 });
  await host.waitForMsg((m) => m.t === "fire" && m.playerId === alice.playerId, "fire relay");
  ok(true, "host board receives Alice's fire relay");

  // The host board's physics decides the finish order and reports it.
  host.send({ t: "golf_finished", order: [alice.playerId, host.playerId, bob.playerId] });
  const golfDone = await cara.waitForState((s) => !!s.golf?.results, "golf results");
  ok(golfDone.golf!.results!.awarded[alice.playerId] === 500, "1st place bounty is 500");
  ok(alice.score(golfDone, alice.playerId) === 1250, "Alice: 750 + 500 = 1250");
  ok(alice.score(golfDone, host.playerId) === 1300, "Host: 1000 + 300 = 1300");
  ok(alice.score(golfDone, bob.playerId) === 1200, "Bob: 1000 + 200 = 1200");
  ok(golfDone.players.find((p) => p.id === bob.playerId)?.debuff === null, "anvil consumed after golf");

  console.log("\n— auction round 2 (butter fingers) —");
  await Promise.all(
    all.map((c) => c.waitForState((s) => s.phase === "auction" && s.auction?.round === 2, "auction 2")),
  );
  ok(host.state!.auction!.item.debuff === "jammed", "round 2 item is Butter Fingers");
  host.send({ t: "submit_bid", amount: 0 });
  alice.send({ t: "submit_bid", amount: 0 });
  bob.send({ t: "submit_bid", amount: 0 });
  cara.send({ t: "submit_bid", amount: 300 });
  await cara.waitForState((s) => s.auction?.stage === "targeting", "cara wins targeting");
  cara.send({ t: "choose_target", targetId: alice.playerId });
  const reveal2 = await host.waitForState((s) => s.auction?.stage === "reveal", "auction 2 reveal");
  ok(reveal2.players.find((p) => p.id === alice.playerId)?.debuff === "jammed", "Alice is butter-fingered");
  ok(cara.score(reveal2, cara.playerId) === 700, "Cara paid 300");

  console.log("\n— the billionaire's bomb —");
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "bomb", "bomb phase")));

  // Every client plays hot-potato: whenever it holds the bomb, it tries to
  // pass right every 150 ms (jam errors are simply retried).
  const passLoops = all.map((c) => {
    const timer = setInterval(() => {
      const b = c.state?.bomb;
      if (c.state?.phase === "bomb" && b?.stage === "ticking" && b.holderId === c.playerId) {
        c.send({ t: "pass_bomb", direction: "right" });
      }
    }, 150);
    return timer;
  });

  const firstBoom = await host.waitForState((s) => (s.bomb?.eliminated.length ?? 0) >= 1, "first explosion", 20_000);
  ok(firstBoom.bomb!.eliminated.length >= 1, "someone got exploded");
  const done = await host.waitForState((s) => s.bomb?.stage === "done", "bomb finishes at 2 survivors", 30_000);
  passLoops.forEach(clearInterval);
  ok(done.bomb!.survivors!.length === 2, "exactly two players survive");
  ok(done.bomb!.eliminated.length === 2, "exactly two players were eliminated");
  const survivorsScoredBonus = done.bomb!.survivors!.every((id) => {
    const before = golfDone.players.find((p) => p.id === id)!.score;
    const after = done.players.find((p) => p.id === id)!.score;
    const paid = id === cara.playerId ? 300 : 0;
    return after >= before - paid + 250; // bonus + whatever they greedily accrued
  });
  ok(survivorsScoredBonus, "survivors banked earnings + 250 bonus");

  console.log("\n— podium & replay —");
  await Promise.all(all.map((c) => c.waitForState((s) => s.phase === "podium", "podium")));
  const podium = host.state!.podium!;
  ok(podium.ranking.length === 4, "podium ranks all 4 players");
  const scores = host.state!.players;
  const sorted = [...scores].sort((a, b) => b.score - a.score).map((p) => p.id);
  ok(JSON.stringify(podium.ranking) === JSON.stringify(sorted), "ranking matches scores");

  all.forEach((c) => c.send({ t: "replay" }));
  const restarted = await host.waitForState(
    (s) => s.phase === "auction" && s.auction?.round === 1,
    "replay loops back to auction 1",
  );
  ok(restarted.players.every((p) => p.score === 1000), "scores reset to 1000 on replay");

  console.log("");
  all.forEach((c) => c.ws.close());
  server.close();

  if (failures > 0) {
    console.error(`SMOKE FAILED — ${failures} assertion(s) failed`);
    process.exit(1);
  }
  console.log("SMOKE PASSED — full game loop works end to end 🎉");
  process.exit(0);
}

main().catch((err) => {
  console.error("SMOKE FAILED —", err.message ?? err);
  process.exit(1);
});
