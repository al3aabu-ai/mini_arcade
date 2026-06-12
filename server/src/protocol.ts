// ---------------------------------------------------------------------------
// Frantics wire protocol.
//
// Every WebSocket frame is a JSON object with a `t` discriminator field.
// The iOS app mirrors these shapes in Core/Models.swift — keep them in sync.
//
// Realtime relays (`aim` / `fire`) are forwarded only to the host device,
// whose external-display scene runs the physics. Everything else is the
// authoritative `room_state` snapshot, broadcast to every device on change.
// ---------------------------------------------------------------------------

const FAST = process.env.FAST_GAME === "1";

/** Tunable game constants. FAST_GAME=1 shrinks all timers for tests. */
export const CONST = {
  MIN_PLAYERS: 2,
  MAX_PLAYERS: 8,
  START_POINTS: 1000,

  AUCTION_BID_MS: FAST ? 600 : 15_000,
  AUCTION_TARGET_MS: FAST ? 600 : 12_000,
  AUCTION_REVEAL_MS: FAST ? 400 : 5_000,

  GOLF_TIME_LIMIT_MS: FAST ? 1_500 : 150_000, // turn-based: everyone needs shots
  GOLF_RESULTS_MS: FAST ? 400 : 6_000,
  GOLF_BOUNTIES: [500, 300, 200],
  GOLF_FINISH_POINTS: 100,

  BOMB_TICK_MS: FAST ? 100 : 1_000,
  BOMB_CASH_PER_TICK: 25,
  BOMB_MULT_STEP: 0.25,
  BOMB_FUSE_MIN_MS: FAST ? 500 : 10_000,
  BOMB_FUSE_MAX_MS: FAST ? 1_200 : 25_000,
  BOMB_ROUND_BREAK_MS: FAST ? 400 : 4_000,
  BOMB_SURVIVOR_BONUS: 250,
  BOMB_JAM_MS: FAST ? 300 : 2_000,

  ROOM_IDLE_SWEEP_MS: 60_000,
  ROOM_MAX_IDLE_MS: 10 * 60_000,
} as const;

export type Phase = "lobby" | "auction" | "golf" | "bomb" | "podium";

export type Debuff = "anvil" | "jammed";

export interface SabotageItem {
  id: string;
  name: string;
  emoji: string;
  blurb: string;
  appliesTo: "golf" | "bomb";
  debuff: Debuff;
}

export const SABOTAGE_ITEMS: SabotageItem[] = [
  {
    id: "anvil",
    name: "The Heavy Anvil",
    emoji: "🪨",
    blurb: "Crush a rival! Their golf shots launch 30% weaker.",
    appliesTo: "golf",
    debuff: "anvil",
  },
  {
    id: "butter",
    name: "Butter Fingers",
    emoji: "🧈",
    blurb: "Grease a rival! Their PASS button jams for 2s every time they catch the bomb.",
    appliesTo: "bomb",
    debuff: "jammed",
  },
];

// --------------------------- snapshot shapes -------------------------------

export interface PlayerState {
  id: string;
  name: string;
  avatar: string; // emoji
  color: string; // hex like "#FF2E88"
  score: number;
  connected: boolean;
  isHost: boolean;
  debuff: Debuff | null;
}

export type AuctionStage = "bidding" | "targeting" | "reveal";

export interface AuctionState {
  round: number; // 1 = before golf, 2 = before bomb
  stage: AuctionStage;
  item: SabotageItem;
  /** epoch ms when the current stage auto-resolves */
  endsAt: number;
  /** players whose bids are locked in (amounts stay secret) */
  lockedIn: string[];
  winnerId: string | null;
  winningBid: number | null;
  targetId: string | null;
}

export interface GolfResults {
  /** player ids in hole-arrival order (finishers only) */
  order: string[];
  /** points awarded this game, per player id */
  awarded: Record<string, number>;
}

export interface GolfState {
  /** epoch ms deadline; the board shows the countdown from this */
  endsAt: number;
  /** playerId -> debuff applying to this game */
  debuffs: Record<string, Debuff>;
  /** whose shot it is right now (host board drives the rotation) */
  turnId: string | null;
  /** players already in the cup, in sink order */
  sunk: string[];
  results: GolfResults | null;
}

export type BombStage = "ticking" | "exploded" | "done";

export interface BombState {
  stage: BombStage;
  /** ids still alive, in seating order around the TV circle */
  alive: string[];
  eliminated: string[];
  holderId: string | null;
  /** total cash accrued by everyone this game (the rising pot on the TV) */
  pot: number;
  /** current holder's greed multiplier */
  multiplier: number;
  /** cash each player has accrued and not yet lost/banked */
  earnings: Record<string, number>;
  /** epoch ms until which the current holder's PASS is jammed (butter) */
  jamUntil: number | null;
  lastExplodedId: string | null;
  survivors: string[] | null;
}

export interface PodiumState {
  /** player ids, best score first */
  ranking: string[];
  replayVotes: string[];
}

export interface RoomState {
  code: string;
  phase: Phase;
  players: PlayerState[];
  auction: AuctionState | null;
  golf: GolfState | null;
  bomb: BombState | null;
  podium: PodiumState | null;
  /** monotonically increasing, lets clients drop stale snapshots */
  rev: number;
}

// --------------------------- client -> server ------------------------------

export type ClientMessage =
  | { t: "create_room"; name: string; avatar: string; color: string }
  | { t: "join_room"; code: string; name: string; avatar: string; color: string }
  | { t: "rejoin"; code: string; playerId: string; token: string }
  | { t: "start_game" }
  | { t: "submit_bid"; amount: number }
  | { t: "choose_target"; targetId: string }
  | { t: "aim"; angle: number; power: number } // power 0..1, angle radians (0 = right, pi/2 = up)
  | { t: "aim_clear" }
  | { t: "fire"; angle: number; power: number }
  | { t: "golf_finished"; order: string[] } // host board only
  | { t: "golf_progress"; turnId: string | null; sunk: string[] } // host board only
  | { t: "pass_bomb"; direction: "left" | "right" }
  | { t: "replay" }
  | { t: "leave" };

// --------------------------- server -> client ------------------------------

export type ServerMessage =
  | { t: "room_joined"; playerId: string; token: string; state: RoomState }
  | { t: "room_state"; state: RoomState }
  | { t: "aim"; playerId: string; angle: number; power: number }
  | { t: "aim_clear"; playerId: string }
  | { t: "fire"; playerId: string; angle: number; power: number }
  | { t: "error"; message: string };

export function parseClientMessage(raw: unknown): ClientMessage | null {
  if (typeof raw !== "object" || raw === null) return null;
  const m = raw as Record<string, unknown>;
  if (typeof m.t !== "string") return null;
  return m as unknown as ClientMessage;
}
