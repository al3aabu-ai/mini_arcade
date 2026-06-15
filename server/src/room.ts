import { randomUUID } from "./ids.js";
import {
  CONST,
  SABOTAGE_ITEMS,
  type AuctionStage,
  type AuctionState,
  type BombState,
  type Debuff,
  type GameType,
  type GolfMap,
  type GolfState,
  type Phase,
  type PlayerState,
  type PodiumState,
  type RoomState,
  type SabotageItem,
  type ServerMessage,
  type Socket,
} from "./protocol.js";

interface Player {
  id: string;
  token: string;
  name: string;
  avatar: string;
  color: string;
  /** public mini-game wins */
  trophies: number;
  /** private spendable wallet (masked from everyone else) */
  coins: number;
  isHost: boolean;
  debuff: Debuff | null;
  ws: Socket | null;
  /** secret current-auction bid; null = not locked in yet */
  bid: number | null;
  bidLockedAt: number;
}

interface AuctionInternal {
  round: number;
  stage: AuctionStage;
  item: SabotageItem;
  endsAt: number;
  winnerId: string | null;
  winningBid: number | null;
  targetId: string | null;
  /** which mini-game this intermission precedes — launched when the auction ends */
  forGame: GameType;
}

interface GolfInternal {
  endsAt: number;
  debuffs: Record<string, Debuff>;
  turnId: string | null;
  sunk: string[];
  results: { order: string[]; awarded: Record<string, number> } | null;
  round: number;
  map: GolfMap;
  /** strokes banked from completed rounds (carried into later rounds) */
  priorStrokes: Record<string, number>;
  /** strokes taken this round, counted server-side from on-turn fires */
  roundStrokes: Record<string, number>;
}

interface BombInternal {
  stage: "ticking" | "exploded" | "done";
  alive: string[];
  eliminated: string[];
  holderId: string | null;
  multiplier: number;
  earnings: Record<string, number>;
  jamUntil: number | null;
  lastExplodedId: string | null;
  survivors: string[] | null;
}

export class Room {
  readonly code: string;
  private players: Player[] = [];
  private phase: Phase = "lobby";
  /** Ordered mini-games for this match, and where we are in it. */
  private lineup: GameType[] = [];
  private lineupIndex = 0;
  private auction: AuctionInternal | null = null;
  private golf: GolfInternal | null = null;
  private bomb: BombInternal | null = null;
  private replayVotes = new Set<string>();
  private rev = 0;
  /** bumped on every phase/stage change so stale timer callbacks no-op */
  private gen = 0;
  private timers: NodeJS.Timeout[] = [];
  lastActivity = Date.now();

  constructor(code: string, private readonly onEmpty: (room: Room) => void) {
    this.code = code;
  }

  // ------------------------------ lifecycle --------------------------------

  addPlayer(opts: { name: string; avatar: string; color: string; isHost: boolean; ws: Socket }):
    | { ok: true; player: Player }
    | { ok: false; reason: string } {
    if (this.phase !== "lobby") return { ok: false, reason: "Game already in progress" };
    if (this.players.length >= CONST.MAX_PLAYERS) return { ok: false, reason: "Room is full" };
    const name = opts.name.trim().slice(0, 14);
    if (!name) return { ok: false, reason: "Name required" };
    if (this.players.some((p) => p.name.toLowerCase() === name.toLowerCase()))
      return { ok: false, reason: "That name is taken" };
    const player: Player = {
      id: randomUUID(),
      token: randomUUID(),
      name,
      avatar: opts.avatar || "🙂",
      color: opts.color || "#FF2E88",
      trophies: 0,
      coins: CONST.START_COINS,
      isHost: opts.isHost,
      debuff: null,
      ws: opts.ws,
      bid: null,
      bidLockedAt: 0,
    };
    this.players.push(player);
    this.touch();
    this.broadcast();
    return { ok: true, player };
  }

  rejoin(playerId: string, token: string, ws: Socket): Player | null {
    const p = this.players.find((x) => x.id === playerId && x.token === token);
    if (!p) return null;
    if (p.ws && p.ws !== ws) {
      try { p.ws.close(4000, "Replaced by reconnect"); } catch { /* already gone */ }
    }
    p.ws = ws;
    this.touch();
    this.broadcast();
    return p;
  }

  handleDisconnect(playerId: string, ws: Socket) {
    const p = this.players.find((x) => x.id === playerId);
    if (!p || p.ws !== ws) return;
    p.ws = null;
    if (this.phase === "lobby" && !p.isHost) {
      // In the lobby, dropping the connection means leaving the party.
      this.players = this.players.filter((x) => x.id !== playerId);
    }
    this.touch();
    this.broadcast();
    if (this.players.every((x) => !x.ws)) this.scheduleEmptyCheck();
  }

  get isAbandoned(): boolean {
    return (
      this.players.every((p) => !p.ws) &&
      Date.now() - this.lastActivity > CONST.ROOM_MAX_IDLE_MS
    );
  }

  private scheduleEmptyCheck() {
    setTimeout(() => {
      if (this.isAbandoned) this.onEmpty(this);
    }, CONST.ROOM_MAX_IDLE_MS + 1000).unref?.();
  }

  private touch() {
    this.lastActivity = Date.now();
  }

  // ------------------------------ messaging --------------------------------

  private send(p: Player, msg: ServerMessage) {
    if (p.ws && p.ws.readyState === p.ws.OPEN) {
      p.ws.send(JSON.stringify(msg));
    }
  }

  private sendToHost(msg: ServerMessage) {
    const host = this.players.find((p) => p.isHost);
    if (host) this.send(host, msg);
  }

  broadcast() {
    // Per-recipient snapshots: each socket gets a state where ONLY its own
    // coins are real and every other wallet is masked to 0. The TV/board shares
    // the host's socket, so this is also what guarantees no wallet reaches the
    // big screen. rev bumps once per change, not once per recipient.
    this.rev += 1;
    for (const p of this.players) {
      if (p.ws && p.ws.readyState === p.ws.OPEN) {
        const msg: ServerMessage = { t: "room_state", state: this.viewState(p.id) };
        p.ws.send(JSON.stringify(msg));
      }
    }
  }

  sendError(playerId: string, message: string) {
    const p = this.players.find((x) => x.id === playerId);
    if (p) this.send(p, { t: "error", message });
  }

  /** Snapshot for a player who just (re)joined — goes in their room_joined. */
  snapshotFor(viewerId: string): RoomState {
    this.rev += 1;
    return this.viewState(viewerId);
  }

  /**
   * Build the room snapshot from `viewerId`'s perspective. PRIVACY RULE: every
   * player's `coins` is masked to 0 except the viewer's own, so a wallet never
   * travels to a device that shouldn't see it — and since the TV shares the
   * host's socket, coins never reach the big screen. Trophies are public.
   * Does NOT bump `rev` (callers bump it once per change).
   */
  private viewState(viewerId: string | null): RoomState {
    const players: PlayerState[] = this.players.map((p) => ({
      id: p.id,
      name: p.name,
      avatar: p.avatar,
      color: p.color,
      trophies: p.trophies,
      coins: p.id === viewerId ? p.coins : 0, // mask everyone else's wallet
      connected: !!p.ws,
      isHost: p.isHost,
      debuff: p.debuff,
    }));
    let auction: AuctionState | null = null;
    if (this.phase === "auction" && this.auction) {
      auction = {
        round: this.auction.round,
        stage: this.auction.stage,
        item: this.auction.item,
        endsAt: this.auction.endsAt,
        lockedIn: this.players.filter((p) => p.bid !== null).map((p) => p.id),
        winnerId: this.auction.winnerId,
        winningBid: this.auction.winningBid,
        targetId: this.auction.targetId,
      };
    }
    let golf: GolfState | null = null;
    if (this.phase === "golf" && this.golf) {
      const strokes: Record<string, number> = {};
      for (const p of this.players) {
        strokes[p.id] = (this.golf.priorStrokes[p.id] ?? 0) + (this.golf.roundStrokes[p.id] ?? 0);
      }
      golf = {
        endsAt: this.golf.endsAt,
        debuffs: this.golf.debuffs,
        turnId: this.golf.turnId,
        sunk: this.golf.sunk,
        results: this.golf.results,
        round: this.golf.round,
        map: this.golf.map,
        strokes,
      };
    }
    let bomb: BombState | null = null;
    if (this.phase === "bomb" && this.bomb) {
      const pot = Object.values(this.bomb.earnings).reduce((a, b) => a + b, 0);
      bomb = {
        stage: this.bomb.stage,
        alive: this.bomb.alive,
        eliminated: this.bomb.eliminated,
        holderId: this.bomb.holderId,
        pot,
        multiplier: this.bomb.multiplier,
        earnings: this.bomb.earnings,
        jamUntil: this.bomb.jamUntil,
        lastExplodedId: this.bomb.lastExplodedId,
        survivors: this.bomb.survivors,
      };
    }
    let podium: PodiumState | null = null;
    if (this.phase === "podium") {
      podium = {
        // Rank by most trophies; the hidden coin wallet is the absolute
        // tiebreaker (computed from the TRUE values, never the masked ones).
        ranking: this.rankedPlayerIds(),
        replayVotes: [...this.replayVotes],
      };
    }
    return {
      code: this.code,
      phase: this.phase,
      players,
      lineup: this.lineup,
      currentLineupIndex: this.lineupIndex,
      auction,
      golf,
      bomb,
      podium,
      rev: this.rev,
    };
  }

  /** Standings: most trophies first, hidden coins as the absolute tiebreaker. */
  private rankedPlayerIds(): string[] {
    return [...this.players]
      .sort((a, b) => b.trophies - a.trophies || b.coins - a.coins)
      .map((p) => p.id);
  }

  // ------------------------------ timers -----------------------------------

  /** Schedule a callback that silently dies if the room moved on (gen changed). */
  private after(ms: number, fn: () => void) {
    const gen = this.gen;
    const handle = setTimeout(() => {
      if (this.gen === gen) fn();
    }, ms);
    handle.unref?.();
    this.timers.push(handle);
  }

  private every(ms: number, fn: () => void) {
    const gen = this.gen;
    const handle = setInterval(() => {
      if (this.gen === gen) fn();
      else clearInterval(handle);
    }, ms);
    handle.unref?.();
    this.timers.push(handle);
  }

  private newGen() {
    this.gen += 1;
    for (const t of this.timers) clearTimeout(t);
    this.timers = [];
  }

  // ------------------------------ lobby ------------------------------------

  startGame(playerId: string) {
    const p = this.players.find((x) => x.id === playerId);
    if (!p?.isHost) return this.sendError(playerId, "Only the host can start the game");
    if (this.phase !== "lobby") return;
    const connected = this.players.filter((x) => x.ws).length;
    const min = process.env.ALLOW_SOLO === "1" ? 1 : CONST.MIN_PLAYERS;
    if (connected < min)
      return this.sendError(playerId, `Need at least ${CONST.MIN_PLAYERS} players`);
    this.touch();
    // TEMP: until the host picker UI lands, every match runs a fixed lineup.
    this.lineup = this.defaultLineup();
    this.lineupIndex = 0;
    this.advanceLineup();
  }

  // --------------------------- lineup flow ---------------------------------

  /** Placeholder lineup; the host will choose these in the next milestone. */
  private defaultLineup(): GameType[] {
    return ["golf", "bomb", "golf"].slice(0, CONST.LINEUP_SIZE) as GameType[];
  }

  /**
   * Generic match driver: run the bidding intermission for the next game in the
   * lineup, or finish at the podium once every game has been played.
   */
  private advanceLineup() {
    if (this.lineupIndex >= this.lineup.length) {
      this.startPodium();
      return;
    }
    this.startAuction(this.lineup[this.lineupIndex]);
  }

  /** Launch a mini-game by type (golf begins at its first round). */
  private launchGame(game: GameType) {
    if (game === "golf") this.startGolf(1);
    else this.startBomb();
  }

  // ------------------------------ auction ----------------------------------

  private startAuction(forGame: GameType) {
    this.newGen();
    this.phase = "auction";
    for (const p of this.players) {
      p.bid = null;
      p.bidLockedAt = 0;
    }
    // The sabotage on offer is the one that bites the game it precedes.
    const item = SABOTAGE_ITEMS.find((s) => s.appliesTo === forGame) ?? SABOTAGE_ITEMS[0];
    this.auction = {
      round: this.lineupIndex + 1, // 1-based position in the lineup, for display
      stage: "bidding",
      item,
      endsAt: Date.now() + CONST.AUCTION_BID_MS,
      winnerId: null,
      winningBid: null,
      targetId: null,
      forGame,
    };
    this.after(CONST.AUCTION_BID_MS, () => this.resolveAuction());
    this.broadcast();
  }

  submitBid(playerId: string, amount: number) {
    if (this.phase !== "auction" || !this.auction || this.auction.stage !== "bidding") return;
    const p = this.players.find((x) => x.id === playerId);
    if (!p) return;
    if (p.bid !== null) return this.sendError(playerId, "Bid already locked in");
    // Bids are paid from the private coin wallet — you can't bid what you don't have.
    const clamped = Math.max(0, Math.min(p.coins, Math.floor(amount)));
    p.bid = clamped;
    p.bidLockedAt = Date.now();
    this.touch();
    if (this.players.every((x) => x.bid !== null || !x.ws)) {
      this.resolveAuction();
    } else {
      this.broadcast();
    }
  }

  private resolveAuction() {
    if (!this.auction || this.auction.stage !== "bidding") return;
    const bidders = this.players
      .filter((p) => (p.bid ?? 0) > 0)
      .sort((a, b) => (b.bid! - a.bid!) || (a.bidLockedAt - b.bidLockedAt));
    const winner = bidders[0] ?? null;
    if (!winner) {
      // Nobody wanted it — short reveal of the unsold item, then move on.
      this.auction.stage = "reveal";
      this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
      this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
      this.broadcast();
      return;
    }
    winner.coins -= winner.bid!;
    this.auction.winnerId = winner.id;
    this.auction.winningBid = winner.bid!;
    this.auction.stage = "targeting";
    this.auction.endsAt = Date.now() + CONST.AUCTION_TARGET_MS;
    this.after(CONST.AUCTION_TARGET_MS, () => {
      if (this.auction?.stage !== "targeting") return; // already chosen
      // Winner dawdled — pick a victim for them.
      const others = this.players.filter((p) => p.id !== winner.id);
      const target = others[Math.floor(Math.random() * others.length)];
      if (target) this.applyTarget(winner.id, target.id);
    });
    this.broadcast();
  }

  chooseTarget(playerId: string, targetId: string) {
    if (this.phase !== "auction" || !this.auction) return;
    if (this.auction.stage !== "targeting" || this.auction.winnerId !== playerId)
      return this.sendError(playerId, "You did not win the auction");
    if (targetId === playerId) return this.sendError(playerId, "Pick someone else, not yourself");
    if (!this.players.some((p) => p.id === targetId))
      return this.sendError(playerId, "Unknown target");
    this.applyTarget(playerId, targetId);
  }

  private applyTarget(_winnerId: string, targetId: string) {
    if (!this.auction || this.auction.stage !== "targeting") return;
    const target = this.players.find((p) => p.id === targetId);
    if (target) target.debuff = this.auction.item.debuff;
    this.auction.targetId = targetId;
    this.auction.stage = "reveal";
    this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
    this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
    this.touch();
    this.broadcast();
  }

  private afterAuction() {
    if (!this.auction) return;
    this.launchGame(this.auction.forGame);
  }

  // ------------------------------ golf -------------------------------------

  /**
   * Golf is played over two rounds: Round 1 on Guerilla Golf, Round 2 on the
   * Tiki Jungle Adventure map. `priorStrokes` carries each player's running
   * stroke total into the next round so the leaderboard is cumulative.
   */
  private startGolf(round: number, priorStrokes: Record<string, number> = {}) {
    this.newGen();
    this.phase = "golf";
    const debuffs: Record<string, Debuff> = {};
    const prior: Record<string, number> = {};
    const round0: Record<string, number> = {};
    for (const p of this.players) {
      if (p.debuff === "anvil") debuffs[p.id] = "anvil";
      prior[p.id] = priorStrokes[p.id] ?? 0;
      round0[p.id] = 0;
    }
    this.golf = {
      endsAt: Date.now() + CONST.GOLF_TIME_LIMIT_MS,
      debuffs,
      turnId: null,
      sunk: [],
      results: null,
      round,
      map: round >= 3 ? "runway" : round === 2 ? "tiki" : "guerilla",
      priorStrokes: prior,
      roundStrokes: round0,
    };
    // Backstop: if the host board never reports (e.g. host died), finish with no finishers.
    this.after(CONST.GOLF_TIME_LIMIT_MS + 5000, () => this.finishGolf([]));
    this.broadcast();
  }

  /** Turn-based: only the active player's inputs reach the board. */
  private isOnTurn(playerId: string): boolean {
    const turn = this.golf?.turnId;
    return !turn || turn === playerId;
  }

  relayAim(playerId: string, angle: number, power: number) {
    if (this.phase !== "golf" || !this.isOnTurn(playerId)) return;
    this.sendToHost({ t: "aim", playerId, angle, power });
  }

  relayAimClear(playerId: string) {
    if (this.phase !== "golf") return;
    this.sendToHost({ t: "aim_clear", playerId });
  }

  relayFire(playerId: string, angle: number, power: number) {
    if (this.phase !== "golf" || !this.isOnTurn(playerId)) return;
    // Count a stroke for the active shooter. Strict turnId match avoids the
    // settling window (turnId === null), where isOnTurn() is permissive.
    let strokeCounted = false;
    if (this.golf && this.golf.turnId === playerId) {
      this.golf.roundStrokes[playerId] = (this.golf.roundStrokes[playerId] ?? 0) + 1;
      strokeCounted = true;
    }
    this.touch();
    this.sendToHost({
      t: "fire",
      playerId,
      angle,
      power: Math.max(0, Math.min(1, power)),
    });
    // Push the updated stroke leaderboard to every client (fire is infrequent).
    if (strokeCounted) this.broadcast();
  }

  /** Host board reports whose turn it is and who has sunk so far. */
  golfProgress(reporterId: string, turnId: string | null, sunk: string[]) {
    const reporter = this.players.find((p) => p.id === reporterId);
    if (!reporter?.isHost) return;
    if (this.phase !== "golf" || !this.golf || this.golf.results) return;
    this.golf.turnId =
      turnId && this.players.some((p) => p.id === turnId) ? turnId : null;
    this.golf.sunk = sunk.filter((id) => this.players.some((p) => p.id === id));
    this.touch();
    this.broadcast();
  }

  golfFinished(reporterId: string, order: string[]) {
    const reporter = this.players.find((p) => p.id === reporterId);
    if (!reporter?.isHost) return this.sendError(reporterId, "Only the host board reports results");
    this.finishGolf(order);
  }

  private finishGolf(order: string[]) {
    if (this.phase !== "golf" || !this.golf || this.golf.results) return;
    const golf = this.golf;
    const sinkers = order.filter((id) => this.players.some((p) => p.id === id));

    // Cumulative strokes across rounds so far (this round folded in).
    const totals: Record<string, number> = {};
    for (const p of this.players) {
      totals[p.id] = (golf.priorStrokes[p.id] ?? 0) + (golf.roundStrokes[p.id] ?? 0);
    }
    // Standings = sinkers ranked by fewest total strokes; ties broken by who
    // sank first. Players who never sank don't place (you can't win by not playing).
    const ranking = [...sinkers].sort((a, b) => {
      const sa = totals[a], sb = totals[b];
      if (sa !== sb) return sa - sb;
      return sinkers.indexOf(a) - sinkers.indexOf(b);
    });

    const awarded: Record<string, number> = {};
    for (const p of this.players) awarded[p.id] = 0;

    if (golf.round < 3) {
      // Rounds 1 & 2 — record standings, carry total strokes into the next round
      // (Guerilla → Tiki Jungle → Tiki Runway). No trophy yet; the segment runs on.
      golf.results = { order: ranking, awarded };
      this.newGen();
      this.after(CONST.GOLF_RESULTS_MS, () => this.startGolf(golf.round + 1, totals));
    } else {
      // Final golf round — the outright winner (fewest total strokes) takes ONE
      // trophy. Golf banks no coins yet (coin pickups arrive in a later milestone).
      const winnerId = ranking[0];
      if (winnerId) {
        awarded[winnerId] = CONST.TROPHY;
        const winner = this.players.find((x) => x.id === winnerId);
        if (winner) winner.trophies += CONST.TROPHY;
      }
      // The anvil is consumed once the golf segment ends.
      for (const p of this.players) if (p.debuff === "anvil") p.debuff = null;
      golf.results = { order: ranking, awarded };
      this.newGen();
      this.lineupIndex += 1; // this golf segment is done — on to the next game
      this.after(CONST.GOLF_RESULTS_MS, () => this.advanceLineup());
    }
    this.touch();
    this.broadcast();
  }

  // ------------------------------ bomb -------------------------------------

  private startBomb() {
    this.newGen();
    this.phase = "bomb";
    const earnings: Record<string, number> = {};
    for (const p of this.players) earnings[p.id] = 0;
    this.bomb = {
      stage: "ticking",
      alive: this.players.map((p) => p.id),
      eliminated: [],
      holderId: null,
      multiplier: 1,
      earnings,
      jamUntil: null,
      lastExplodedId: null,
      survivors: null,
    };
    this.startBombRound();
  }

  private startBombRound() {
    const bomb = this.bomb;
    if (!bomb) return;
    this.newGen();
    bomb.stage = "ticking";
    bomb.multiplier = 1;
    const holder = bomb.alive[Math.floor(Math.random() * bomb.alive.length)];
    this.setBombHolder(holder);
    const fuse =
      CONST.BOMB_FUSE_MIN_MS +
      Math.random() * (CONST.BOMB_FUSE_MAX_MS - CONST.BOMB_FUSE_MIN_MS);
    this.after(fuse, () => this.explodeBomb());
    this.every(CONST.BOMB_TICK_MS, () => {
      if (!bomb.holderId) return;
      bomb.earnings[bomb.holderId] =
        (bomb.earnings[bomb.holderId] ?? 0) +
        Math.round(CONST.BOMB_CASH_PER_TICK * bomb.multiplier);
      bomb.multiplier = Math.round((bomb.multiplier + CONST.BOMB_MULT_STEP) * 100) / 100;
      this.broadcast();
    });
    this.broadcast();
  }

  private setBombHolder(playerId: string) {
    const bomb = this.bomb;
    if (!bomb) return;
    bomb.holderId = playerId;
    bomb.multiplier = 1;
    const holder = this.players.find((p) => p.id === playerId);
    bomb.jamUntil = holder?.debuff === "jammed" ? Date.now() + CONST.BOMB_JAM_MS : null;
  }

  passBomb(playerId: string, direction: "left" | "right") {
    const bomb = this.bomb;
    if (this.phase !== "bomb" || !bomb || bomb.stage !== "ticking") return;
    if (bomb.holderId !== playerId) return this.sendError(playerId, "You are not holding the bomb");
    if (bomb.jamUntil && Date.now() < bomb.jamUntil)
      return this.sendError(playerId, "Butter fingers! The button is jammed");
    const idx = bomb.alive.indexOf(playerId);
    if (idx === -1) return;
    const step = direction === "left" ? -1 : 1;
    const next = bomb.alive[(idx + step + bomb.alive.length) % bomb.alive.length];
    if (next === playerId) return; // alone in the circle, nowhere to pass
    this.setBombHolder(next);
    this.touch();
    this.broadcast();
  }

  private explodeBomb() {
    const bomb = this.bomb;
    if (!bomb || bomb.stage !== "ticking" || !bomb.holderId) return;
    const victim = bomb.holderId;
    this.newGen();
    bomb.stage = "exploded";
    bomb.lastExplodedId = victim;
    bomb.earnings[victim] = 0; // greed punished: accrued cash burns with you
    bomb.alive = bomb.alive.filter((id) => id !== victim);
    bomb.eliminated.push(victim);
    bomb.holderId = null;
    bomb.jamUntil = null;
    this.broadcast();
    this.after(CONST.BOMB_ROUND_BREAK_MS, () => {
      if (bomb.alive.length <= 2) this.finishBomb();
      else this.startBombRound();
    });
  }

  private finishBomb() {
    const bomb = this.bomb;
    if (!bomb) return;
    this.newGen();
    bomb.stage = "done";
    bomb.holderId = null;
    bomb.survivors = [...bomb.alive];
    for (const p of this.players) {
      // Cash greedily accrued this game banks straight into the private wallet.
      p.coins += bomb.earnings[p.id] ?? 0;
      if (bomb.survivors.includes(p.id)) {
        p.trophies += CONST.TROPHY;           // surviving the bomb is a win
        p.coins += CONST.BOMB_SURVIVOR_BONUS; // plus a cash survival bonus
      }
      if (p.debuff === "jammed") p.debuff = null;
    }
    this.broadcast();
    this.lineupIndex += 1; // bomb segment done — advance the lineup
    this.after(CONST.BOMB_ROUND_BREAK_MS, () => this.advanceLineup());
  }

  // ------------------------------ podium -----------------------------------

  private startPodium() {
    this.newGen();
    this.phase = "podium";
    this.replayVotes.clear();
    this.touch();
    this.broadcast();
  }

  voteReplay(playerId: string) {
    if (this.phase !== "podium") return;
    if (!this.players.some((p) => p.id === playerId)) return;
    this.replayVotes.add(playerId);
    this.touch();
    const connected = this.players.filter((p) => p.ws);
    const everyoneIn =
      connected.length > 0 && connected.every((p) => this.replayVotes.has(p.id));
    if (everyoneIn) {
      for (const p of this.players) {
        p.trophies = 0;
        p.coins = CONST.START_COINS;
        p.debuff = null;
      }
      this.golf = null;
      this.bomb = null;
      this.replayVotes.clear();
      // Fresh match: rebuild the lineup and drive it from the top.
      this.lineup = this.defaultLineup();
      this.lineupIndex = 0;
      this.advanceLineup();
    } else {
      this.broadcast();
    }
  }
}

// ----------------------------- room manager ---------------------------------

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I/O — avoids 1/0 confusion

export class RoomManager {
  private rooms = new Map<string, Room>();

  constructor() {
    setInterval(() => {
      for (const [code, room] of this.rooms) {
        if (room.isAbandoned) {
          this.rooms.delete(code);
          console.log(`[room ${code}] swept (abandoned)`);
        }
      }
    }, CONST.ROOM_IDLE_SWEEP_MS).unref?.();
  }

  create(): Room {
    let code: string;
    do {
      code = Array.from(
        { length: 4 },
        () => CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)],
      ).join("");
    } while (this.rooms.has(code));
    const room = new Room(code, (r) => this.rooms.delete(r.code));
    this.rooms.set(code, room);
    return room;
  }

  get(code: string): Room | undefined {
    return this.rooms.get(code.trim().toUpperCase());
  }

  get stats() {
    return { rooms: this.rooms.size };
  }
}
