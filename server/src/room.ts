import { randomUUID } from "./ids.js";
import {
  CONST,
  AUCTION_ITEMS,
  SECRET_TASKS,
  type AuctionItem,
  type AuctionStage,
  type AuctionState,
  type BombState,
  type BumperState,
  type Coin,
  type GameType,
  type Modifier,
  type GolfMap,
  type GolfState,
  type Phase,
  type PlayerState,
  type PodiumState,
  type RoomState,
  type SecretTask,
  type SelectionState,
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
  /** active buff/debuff for the upcoming game (public), cleared at game end */
  modifier: Modifier | null;
  ws: Socket | null;
  /** secret current-auction bid; null = not locked in yet */
  bid: number | null;
  /** which auction lot this bid is for (sabotage vs advantage) */
  bidItemId: Modifier | null;
  bidLockedAt: number;
  /** this player's hidden objective for the current mini-game (private) */
  secretTask: SecretTask | null;
  // Secret-task telemetry, reset at each mini-game start:
  taskMaxPower: boolean;      // golf: took a full-power shot
  taskCoins: number;          // golf: coins grabbed this game
  taskReset: boolean;         // golf: fell in water / reset this game
  taskBombHoldMs: number;     // bomb: cumulative time holding the bomb
  taskBombHotPotato: boolean; // bomb: passed within 1s of receiving at least once
  taskBumperAggressor: boolean; // bumper: knocked another player off the slab
  taskBumperSurvived: boolean;  // bumper: won or survived 30s without falling (set at finish)
}

interface AuctionInternal {
  round: number;
  stage: AuctionStage;
  items: AuctionItem[]; // the two lots (sabotage + advantage) for forGame
  endsAt: number;
  winnerId: string | null;
  winningBid: number | null;
  winningItemId: Modifier | null;
  targetId: string | null;
  /** which mini-game this intermission precedes — launched when the auction ends */
  forGame: GameType;
}

interface GolfInternal {
  endsAt: number;
  turnId: string | null;
  sunk: string[];
  results: { order: string[]; awarded: Record<string, number> } | null;
  round: number;
  map: GolfMap;
  /** strokes banked from completed rounds (carried into later rounds) */
  priorStrokes: Record<string, number>;
  /** strokes taken this round, counted server-side from on-turn fires */
  roundStrokes: Record<string, number>;
  /** loose coins on the course this round, registered by the host board */
  spawnedCoins: Coin[];
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
  spawnedCoins: Coin[];
  /** epoch ms the current holder picked up the bomb (for hold-time telemetry) */
  holderSince: number | null;
}

interface BumperInternal {
  endsAt: number;
  alive: string[];
  eliminated: string[];
  winnerId: string | null;
  startedAt: number;
}

export class Room {
  readonly code: string;
  private players: Player[] = [];
  private phase: Phase = "lobby";
  /** Ordered mini-games for this match, and where we are in it. */
  private lineup: GameType[] = [];
  private lineupIndex = 0;
  /** Host's in-progress game-picker (non-null only while phase === "selection"). */
  private selection: { picks: GameType[] } | null = null;
  private auction: AuctionInternal | null = null;
  private golf: GolfInternal | null = null;
  private bomb: BombInternal | null = null;
  private bumper: BumperInternal | null = null;
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
      modifier: null,
      ws: opts.ws,
      bid: null,
      bidItemId: null,
      bidLockedAt: 0,
      secretTask: null,
      taskMaxPower: false,
      taskCoins: 0,
      taskReset: false,
      taskBombHoldMs: 0,
      taskBombHotPotato: false,
      taskBumperAggressor: false,
      taskBumperSurvived: false,
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
      modifier: p.modifier, // public buff/debuff (the boards read it to apply effects)
      // PRIVACY: a secret task only ever reaches its own owner (never the TV).
      secretTask: p.id === viewerId ? p.secretTask : null,
    }));
    let selection: SelectionState | null = null;
    if (this.phase === "selection" && this.selection) {
      selection = { picks: this.selection.picks, size: CONST.LINEUP_SIZE };
    }
    let auction: AuctionState | null = null;
    if (this.phase === "auction" && this.auction) {
      auction = {
        round: this.auction.round,
        stage: this.auction.stage,
        items: this.auction.items,
        endsAt: this.auction.endsAt,
        lockedIn: this.players.filter((p) => p.bid !== null).map((p) => p.id),
        winnerId: this.auction.winnerId,
        winningBid: this.auction.winningBid,
        winningItemId: this.auction.winningItemId,
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
        turnId: this.golf.turnId,
        sunk: this.golf.sunk,
        results: this.golf.results,
        round: this.golf.round,
        map: this.golf.map,
        strokes,
        spawnedCoins: this.golf.spawnedCoins,
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
        spawnedCoins: this.bomb.spawnedCoins,
      };
    }
    let bumper: BumperState | null = null;
    if (this.phase === "bumper" && this.bumper) {
      bumper = {
        endsAt: this.bumper.endsAt,
        alive: this.bumper.alive,
        eliminated: this.bumper.eliminated,
        winnerId: this.bumper.winnerId,
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
      selection,
      auction,
      golf,
      bomb,
      bumper,
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
    this.startSelection();
  }

  // --------------------------- game selection ------------------------------

  /** Open the host's game picker; the match lineup is built here. */
  private startSelection() {
    this.newGen();
    this.phase = "selection";
    this.selection = { picks: [] };
    this.lineup = [];
    this.lineupIndex = 0;
    this.clearSecretTasks();
    this.broadcast();
  }

  /** Keep only valid game types, capped at the lineup size. */
  private sanitizeLineup(lineup: unknown): GameType[] {
    const valid: GameType[] = ["golf", "bomb", "bumper"];
    if (!Array.isArray(lineup)) return [];
    return lineup
      .filter((g): g is GameType => valid.includes(g as GameType))
      .slice(0, CONST.LINEUP_SIZE);
  }

  /** Host live-updates the in-progress picks so the TV can mirror the slots. */
  previewLineup(playerId: string, lineup: GameType[]) {
    const p = this.players.find((x) => x.id === playerId);
    if (!p?.isHost) return;
    if (this.phase !== "selection" || !this.selection) return;
    this.selection.picks = this.sanitizeLineup(lineup);
    this.touch();
    this.broadcast();
  }

  /** Host commits exactly LINEUP_SIZE games → overrides the lineup and starts. */
  selectLineup(playerId: string, lineup: GameType[]) {
    const p = this.players.find((x) => x.id === playerId);
    if (!p?.isHost) return this.sendError(playerId, "Only the host picks the games");
    if (this.phase !== "selection") return;
    const clean = this.sanitizeLineup(lineup);
    if (clean.length !== CONST.LINEUP_SIZE)
      return this.sendError(playerId, `Pick exactly ${CONST.LINEUP_SIZE} games`);
    this.lineup = clean;
    this.lineupIndex = 0;
    this.selection = null;
    this.touch();
    this.advanceLineup();
  }

  // --------------------------- lineup flow ---------------------------------

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
    else if (game === "bumper") this.startBumper();
    else this.startBomb();
  }

  // ------------------------------ auction ----------------------------------

  private startAuction(forGame: GameType) {
    this.newGen();
    this.phase = "auction";
    // The previous game's task result has had its on-phone moment — wipe it so
    // the intermission and the next game start clean.
    this.clearSecretTasks();
    for (const p of this.players) {
      p.bid = null;
      p.bidItemId = null;
      p.bidLockedAt = 0;
    }
    // Put up both lots for the upcoming game — one sabotage, one self-advantage.
    const items = AUCTION_ITEMS.filter((it) => it.appliesTo === forGame);
    this.auction = {
      round: this.lineupIndex + 1, // 1-based position in the lineup, for display
      stage: "bidding",
      items,
      endsAt: Date.now() + CONST.AUCTION_BID_MS,
      winnerId: null,
      winningBid: null,
      winningItemId: null,
      targetId: null,
      forGame,
    };
    this.after(CONST.AUCTION_BID_MS, () => this.resolveAuction());
    this.broadcast();
  }

  submitBid(playerId: string, amount: number, itemId: Modifier) {
    if (this.phase !== "auction" || !this.auction || this.auction.stage !== "bidding") return;
    const p = this.players.find((x) => x.id === playerId);
    if (!p) return;
    if (p.bid !== null) return this.sendError(playerId, "Bid already locked in");
    // You bid on a specific lot; a zero bid just sits this auction out.
    const clamped = Math.max(0, Math.min(p.coins, Math.floor(amount)));
    const validItem = this.auction.items.some((it) => it.id === itemId);
    p.bid = clamped;
    p.bidItemId = clamped > 0 && validItem ? itemId : null;
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
      .filter((p) => (p.bid ?? 0) > 0 && p.bidItemId !== null)
      .sort((a, b) => (b.bid! - a.bid!) || (a.bidLockedAt - b.bidLockedAt));
    const winner = bidders[0] ?? null;
    const item = winner ? this.auction.items.find((it) => it.id === winner.bidItemId) : undefined;
    if (!winner || !item) {
      // Nobody wanted anything — short reveal of the unsold lots, then move on.
      this.auction.stage = "reveal";
      this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
      this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
      this.broadcast();
      return;
    }
    winner.coins -= winner.bid!;
    this.auction.winnerId = winner.id;
    this.auction.winningBid = winner.bid!;
    this.auction.winningItemId = item.id;

    if (item.type === "advantage") {
      // Self-buff: applied straight to the winner, no target needed.
      winner.modifier = item.id;
      this.auction.stage = "reveal";
      this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
      this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
      this.broadcast();
      return;
    }

    // Sabotage: the winner picks a rival to receive the debuff.
    this.auction.stage = "targeting";
    this.auction.endsAt = Date.now() + CONST.AUCTION_TARGET_MS;
    this.after(CONST.AUCTION_TARGET_MS, () => {
      if (this.auction?.stage !== "targeting") return; // already chosen
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
    if (!this.auction || this.auction.stage !== "targeting" || !this.auction.winningItemId) return;
    const target = this.players.find((p) => p.id === targetId);
    if (target) target.modifier = this.auction.winningItemId; // the won sabotage effect
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
    const prior: Record<string, number> = {};
    const round0: Record<string, number> = {};
    for (const p of this.players) {
      prior[p.id] = priorStrokes[p.id] ?? 0;
      round0[p.id] = 0;
    }
    this.golf = {
      endsAt: Date.now() + CONST.GOLF_TIME_LIMIT_MS,
      turnId: null,
      sunk: [],
      results: null,
      round,
      map: round >= 3 ? "runway" : round === 2 ? "tiki" : "guerilla",
      priorStrokes: prior,
      roundStrokes: round0,
      spawnedCoins: [], // the host board registers this round's layout once it builds
    };
    // A golf "mini-game" is the whole 3-round segment — assign tasks once, at the
    // start, and let telemetry accumulate across the rounds.
    if (round === 1) this.assignSecretTasks("golf");
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
      // Secret-task telemetry: a near-max-power shot satisfies "The Long Shot".
      if (power >= 0.95) {
        const shooter = this.players.find((p) => p.id === playerId);
        if (shooter) shooter.taskMaxPower = true;
      }
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
      // Golf modifiers (anvil / golden club) are consumed once the segment ends.
      for (const p of this.players) p.modifier = null;
      // Settle secret tasks against this segment's telemetry (quiet coin payouts).
      for (const p of this.players) this.evaluateSecretTask(p);
      golf.results = { order: ranking, awarded };
      this.newGen();
      this.lineupIndex += 1; // this golf segment is done — on to the next game
      this.after(CONST.GOLF_RESULTS_MS, () => this.advanceLineup());
    }
    this.touch();
    this.broadcast();
  }

  // ------------------------------ coins ------------------------------------

  /** Keep only well-formed coins (id + finite x/y/z), capped to a sane count. */
  private sanitizeCoins(coins: unknown): Coin[] {
    if (!Array.isArray(coins)) return [];
    const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
    return coins
      .filter((c): c is Record<string, unknown> => typeof c === "object" && c !== null && typeof (c as any).id === "string")
      .slice(0, 8)
      .map((c) => ({ id: String(c.id), x: num(c.x), y: num(c.y), z: num(c.z) }));
  }

  /** Host board registers the loose coins it placed on this golf round's course. */
  registerCoins(reporterId: string, coins: Coin[]) {
    const reporter = this.players.find((p) => p.id === reporterId);
    if (!reporter?.isHost) return; // only the authoritative board places coins
    if (this.phase !== "golf" || !this.golf) return;
    this.golf.spawnedCoins = this.sanitizeCoins(coins);
    this.touch();
    this.broadcast();
  }

  /**
   * A ball ran into a coin (reported by the host board). Validate the coin still
   * exists, remove it from the map, and credit the flat COIN_VALUE to the player
   * whose ball grabbed it. Host-only — the board owns the physics.
   */
  collectCoin(reporterId: string, coinId: string, collectorId: string) {
    const reporter = this.players.find((p) => p.id === reporterId);
    if (!reporter?.isHost) return;
    if (this.phase !== "golf" || !this.golf) return;
    const idx = this.golf.spawnedCoins.findIndex((c) => c.id === coinId);
    if (idx === -1) return; // already collected or unknown
    this.golf.spawnedCoins.splice(idx, 1);
    const collector = this.players.find((p) => p.id === collectorId);
    if (collector) {
      collector.coins += CONST.COIN_VALUE;
      collector.taskCoins += 1; // telemetry for "Greedy Golfer"
    }
    this.touch();
    this.broadcast();
  }

  // --------------------------- secret tasks --------------------------------

  /** Assign each player ONE random hidden objective and reset its telemetry. */
  private assignSecretTasks(game: GameType) {
    const pool = SECRET_TASKS[game];
    for (const p of this.players) {
      const pick = pool[Math.floor(Math.random() * pool.length)];
      p.secretTask = { ...pick, isCompleted: false }; // per-player copy
      p.taskMaxPower = false;
      p.taskCoins = 0;
      p.taskReset = false;
      p.taskBombHoldMs = 0;
      p.taskBombHotPotato = false;
      p.taskBumperAggressor = false;
      p.taskBumperSurvived = false;
    }
  }

  /** Drop the current tasks (between games / on a fresh match). */
  private clearSecretTasks() {
    for (const p of this.players) p.secretTask = null;
  }

  /** Host board reports a ball fell in water / out of bounds (fails Safe Play). */
  reportBallReset(reporterId: string, playerId: string) {
    const reporter = this.players.find((p) => p.id === reporterId);
    if (!reporter?.isHost || this.phase !== "golf") return;
    const p = this.players.find((x) => x.id === playerId);
    if (p) p.taskReset = true; // telemetry only — no snapshot change to broadcast
  }

  /** Check one player's task against the game's telemetry and pay out if met. */
  private evaluateSecretTask(p: Player) {
    const task = p.secretTask;
    if (!task || task.isCompleted) return;
    let done = false;
    switch (task.id) {
      case "long_shot": done = p.taskMaxPower; break;
      case "greedy_golfer": done = p.taskCoins >= 2; break;
      case "safe_play": done = !p.taskReset; break;
      case "hot_potato": done = p.taskBombHotPotato; break;
      case "survivor": done = p.taskBombHoldMs <= 5000; break;
      case "aggressor": done = p.taskBumperAggressor; break;
      case "pacifist": done = p.taskBumperSurvived; break;
    }
    if (done) {
      task.isCompleted = true;
      p.coins += task.rewardCoins; // quiet credit to the private wallet
    }
  }

  /** Scatter 2–3 coins around the 2-D bomb arena (fractional screen coords). */
  private generateBombCoins(): Coin[] {
    const count = 2 + Math.floor(Math.random() * 2); // 2 or 3
    const coins: Coin[] = [];
    for (let i = 0; i < count; i++) {
      // Keep them off the central pot and away from the very edges.
      const x = 0.16 + Math.random() * 0.68;
      const y = 0.24 + Math.random() * 0.42;
      coins.push({ id: `bcoin-${i}`, x, y, z: 0 });
    }
    return coins;
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
      spawnedCoins: this.generateBombCoins(),
      holderSince: null,
    };
    this.assignSecretTasks("bomb");
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
    const now = Date.now();
    // Bank the outgoing holder's elapsed time (hold-time telemetry for "Survivor").
    if (bomb.holderId && bomb.holderSince != null) {
      const prev = this.players.find((p) => p.id === bomb.holderId);
      if (prev) prev.taskBombHoldMs += now - bomb.holderSince;
    }
    bomb.holderId = playerId;
    bomb.holderSince = now;
    bomb.multiplier = 1;
    const holder = this.players.find((p) => p.id === playerId);
    bomb.jamUntil = holder?.modifier === "butter" ? now + CONST.BOMB_JAM_MS : null;
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
    // "Hot Potato": passing within 1s of receiving completes that secret task.
    if (bomb.holderSince != null && Date.now() - bomb.holderSince <= 1000) {
      const passer = this.players.find((p) => p.id === playerId);
      if (passer) passer.taskBombHotPotato = true;
    }
    this.setBombHolder(next); // also banks playerId's hold time
    // Pick-up-while-passing: the passer snatches one loose coin, if any remain.
    // (The bomb is a 2-D arena, so this is the pass-to-collect analog of the
    // golf ball's physics pickup — no spatial collision to detect.)
    const coin = bomb.spawnedCoins.shift();
    if (coin) {
      const passer = this.players.find((p) => p.id === playerId);
      if (passer) passer.coins += CONST.COIN_VALUE;
    }
    this.touch();
    this.broadcast();
  }

  private explodeBomb() {
    const bomb = this.bomb;
    if (!bomb || bomb.stage !== "ticking" || !bomb.holderId) return;
    const victim = bomb.holderId;
    this.newGen();
    // Bank the victim's final hold time before they leave the circle.
    if (bomb.holderSince != null) {
      const v = this.players.find((p) => p.id === victim);
      if (v) v.taskBombHoldMs += Date.now() - bomb.holderSince;
    }
    const victimP = this.players.find((p) => p.id === victim);
    bomb.holderId = null;
    bomb.holderSince = null;
    bomb.jamUntil = null;
    bomb.stage = "exploded";
    bomb.lastExplodedId = victim;
    // Hazmat advantage: shrug off this ONE blast and stay in (modifier consumed).
    // The victim stays in `alive`, so the board shows "saved!" instead of "OUT".
    if (victimP?.modifier === "hazmat") {
      victimP.modifier = null;
    } else {
      bomb.earnings[victim] = 0; // greed punished: accrued cash burns with you
      bomb.alive = bomb.alive.filter((id) => id !== victim);
      bomb.eliminated.push(victim);
    }
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
    // Bank whoever is still holding (no explosion ended this) before tallying.
    if (bomb.holderId && bomb.holderSince != null) {
      const h = this.players.find((p) => p.id === bomb.holderId);
      if (h) h.taskBombHoldMs += Date.now() - bomb.holderSince;
    }
    bomb.stage = "done";
    bomb.holderId = null;
    bomb.holderSince = null;
    bomb.survivors = [...bomb.alive];
    for (const p of this.players) {
      // Cash greedily accrued this game banks straight into the private wallet.
      p.coins += bomb.earnings[p.id] ?? 0;
      if (bomb.survivors.includes(p.id)) {
        p.trophies += CONST.TROPHY;           // surviving the bomb is a win
        p.coins += CONST.BOMB_SURVIVOR_BONUS; // plus a cash survival bonus
      }
      p.modifier = null; // bomb modifiers (butter / hazmat) are consumed at game end
      this.evaluateSecretTask(p); // settle the hidden objective (quiet coin payout)
    }
    this.broadcast();
    this.lineupIndex += 1; // bomb segment done — advance the lineup
    this.after(CONST.BOMB_ROUND_BREAK_MS, () => this.advanceLineup());
  }

  // ------------------------------ bumper -----------------------------------

  private startBumper() {
    this.newGen();
    this.phase = "bumper";
    const now = Date.now();
    this.bumper = {
      endsAt: now + CONST.BUMPER_TIME_MS,
      alive: this.players.map((p) => p.id),
      eliminated: [],
      winnerId: null,
      startedAt: now,
    };
    this.assignSecretTasks("bumper");
    // Survival buzzer — whoever's still on the slab when it sounds wins.
    this.after(CONST.BUMPER_TIME_MS, () => this.finishBumper());
    this.broadcast();
  }

  /** Stream a player's joystick vector to the host board, which runs the physics. */
  updateJoystick(playerId: string, x: number, y: number) {
    if (this.phase !== "bumper" || !this.bumper) return;
    if (!this.bumper.alive.includes(playerId)) return; // the dead don't drive
    this.sendToHost({ t: "joystick", playerId, x, y });
  }

  /** Host board reports a player splashed off the slab; `byPlayerId` shoved them. */
  bumperKnockout(reporterId: string, playerId: string, byPlayerId: string | null) {
    const reporter = this.players.find((p) => p.id === reporterId);
    if (!reporter?.isHost) return; // only the authoritative board calls knockouts
    const bumper = this.bumper;
    if (this.phase !== "bumper" || !bumper) return;
    if (!bumper.alive.includes(playerId)) return; // already out
    bumper.alive = bumper.alive.filter((id) => id !== playerId);
    bumper.eliminated.push(playerId);
    // Credit the shover for "The Aggressor".
    if (byPlayerId) {
      const aggressor = this.players.find((p) => p.id === byPlayerId);
      if (aggressor && byPlayerId !== playerId) aggressor.taskBumperAggressor = true;
    }
    this.touch();
    if (bumper.alive.length <= 1) {
      this.finishBumper(); // last one standing — end early
    } else {
      this.broadcast();
    }
  }

  private finishBumper() {
    const bumper = this.bumper;
    if (this.phase !== "bumper" || !bumper) return;
    this.newGen();
    bumper.winnerId = bumper.alive.length === 1 ? bumper.alive[0] : null;
    const elapsed = Date.now() - bumper.startedAt;
    for (const p of this.players) {
      const survived = bumper.alive.includes(p.id);
      if (survived) p.trophies += CONST.TROPHY; // everyone still on the slab wins
      // "Pacifist": didn't fall, and either won or lasted the distance.
      p.taskBumperSurvived =
        survived && (bumper.winnerId === p.id || elapsed >= CONST.BUMPER_PACIFIST_MS);
      this.evaluateSecretTask(p);
      p.modifier = null; // bumper modifiers (flat tire / nitro) are consumed at game end
    }
    this.broadcast();
    this.lineupIndex += 1;
    this.after(CONST.BUMPER_RESULTS_MS, () => this.advanceLineup());
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
        p.modifier = null;
      }
      this.golf = null;
      this.bomb = null;
      this.bumper = null;
      this.replayVotes.clear();
      // Fresh match: the host curates a brand-new lineup from the picker.
      this.startSelection();
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
