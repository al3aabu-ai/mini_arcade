"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

  // src/protocol.ts
  var FAST = false;
  var CONST = {
    MIN_PLAYERS: 2,
    MAX_PLAYERS: 8,
    /** Spendable wallet every player starts with — coins fund the secret auction bids. */
    START_COINS: 1e3,
    /** How many mini-games one match runs (the host will pick these next milestone). */
    LINEUP_SIZE: 3,
    AUCTION_BID_MS: FAST ? 600 : 15e3,
    AUCTION_TARGET_MS: FAST ? 600 : 12e3,
    AUCTION_REVEAL_MS: FAST ? 400 : 5e3,
    GOLF_TIME_LIMIT_MS: FAST ? 1500 : 15e4,
    // turn-based: everyone needs shots
    GOLF_RESULTS_MS: FAST ? 400 : 6e3,
    /** A mini-game win is worth one trophy — trophies decide the match. */
    TROPHY: 1,
    /** Flat coins credited for grabbing a loose coin on the field. */
    COIN_VALUE: 50,
    BOMB_TICK_MS: FAST ? 100 : 1e3,
    BOMB_CASH_PER_TICK: 25,
    BOMB_MULT_STEP: 0.25,
    BOMB_FUSE_MIN_MS: FAST ? 500 : 1e4,
    BOMB_FUSE_MAX_MS: FAST ? 1200 : 25e3,
    BOMB_ROUND_BREAK_MS: FAST ? 400 : 4e3,
    BOMB_SURVIVOR_BONUS: 250,
    BOMB_JAM_MS: FAST ? 300 : 2e3,
    BUMPER_TIME_MS: FAST ? 1500 : 45e3,
    // survival timer
    BUMPER_PACIFIST_MS: FAST ? 600 : 3e4,
    // "Pacifist" survival threshold
    BUMPER_RESULTS_MS: FAST ? 400 : 5e3,
    ROOM_IDLE_SWEEP_MS: 6e4,
    ROOM_MAX_IDLE_MS: 10 * 6e4
  };
  var SECRET_TASKS = {
    golf: [
      {
        id: "long_shot",
        descriptionEN: "The Long Shot \u2014 smack the ball at full power at least once.",
        descriptionAR: "\u0627\u0644\u0636\u0631\u0628\u0629 \u0627\u0644\u0637\u0648\u064A\u0644\u0629 \u2014 \u0627\u0636\u0631\u0628 \u0627\u0644\u0643\u0631\u0629 \u0628\u0623\u0642\u0635\u0649 \u0642\u0648\u0629 \u0645\u0631\u0629 \u0648\u062D\u062F\u0629 \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644.",
        rewardCoins: 150,
        isCompleted: false
      },
      {
        id: "greedy_golfer",
        descriptionEN: "Greedy Golfer \u2014 grab at least 2 coins this game.",
        descriptionAR: "\u0637\u0645\u0651\u0627\u0639 \u0627\u0644\u0630\u0647\u0628 \u2014 \u0644\u0650\u0645 \u0662 \u0639\u0645\u0644\u0627\u062A \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644 \u0641\u064A \u0647\u0627\u0644\u0644\u0639\u0628\u0629.",
        rewardCoins: 150,
        isCompleted: false
      },
      {
        id: "safe_play",
        descriptionEN: "Safe Play \u2014 finish without landing in water or resetting.",
        descriptionAR: "\u0644\u0639\u0628 \u0622\u0645\u0646 \u2014 \u062E\u0644\u0651\u0635 \u0628\u062F\u0648\u0646 \u0645\u0627 \u062A\u0637\u064A\u062D \u0628\u0627\u0644\u0645\u0627\u064A \u0623\u0648 \u062A\u062A\u0631\u062C\u0651\u0639 \u0644\u0644\u0628\u062F\u0627\u064A\u0629.",
        rewardCoins: 150,
        isCompleted: false
      }
    ],
    bomb: [
      {
        id: "hot_potato",
        descriptionEN: "Hot Potato \u2014 pass the bomb within 1 second of getting it.",
        descriptionAR: "\u0628\u0637\u0627\u0637\u0633 \u062D\u0627\u0631\u0629 \u2014 \u0645\u0631\u0651\u0631 \u0627\u0644\u0642\u0646\u0628\u0644\u0629 \u062E\u0644\u0627\u0644 \u062B\u0627\u0646\u064A\u0629 \u0645\u0646 \u0645\u0627 \u062A\u0648\u0635\u0644\u0643.",
        rewardCoins: 150,
        isCompleted: false
      },
      {
        id: "survivor",
        descriptionEN: "The Survivor \u2014 never hold the bomb more than 5 seconds total.",
        descriptionAR: "\u0627\u0644\u0646\u0627\u062C\u064A \u2014 \u0644\u0627 \u062A\u0645\u0633\u0643 \u0627\u0644\u0642\u0646\u0628\u0644\u0629 \u0623\u0643\u062B\u0631 \u0645\u0646 \u0665 \u062B\u0648\u0627\u0646\u064A \u0628\u0627\u0644\u0645\u062C\u0645\u0648\u0639.",
        rewardCoins: 150,
        isCompleted: false
      }
    ],
    bumper: [
      {
        id: "aggressor",
        descriptionEN: "The Aggressor \u2014 shove another player off the edge yourself.",
        descriptionAR: "\u0627\u0644\u0645\u0647\u0627\u062C\u0645 \u2014 \u0637\u0650\u064A\u062D \u0644\u0627\u0639\u0628 \u062B\u0627\u0646\u064A \u0639\u0646 \u0627\u0644\u062D\u0644\u0628\u0629 \u0628\u0646\u0641\u0633\u0643.",
        rewardCoins: 150,
        isCompleted: false
      },
      {
        id: "pacifist",
        descriptionEN: "Pacifist \u2014 win, or survive 30 seconds without falling in.",
        descriptionAR: "\u0627\u0644\u0645\u0633\u0627\u0644\u0645 \u2014 \u0627\u0641\u0648\u0632\u060C \u0623\u0648 \u0627\u0635\u0645\u062F \u0663\u0660 \u062B\u0627\u0646\u064A\u0629 \u0628\u062F\u0648\u0646 \u0645\u0627 \u062A\u0637\u064A\u062D \u0628\u0627\u0644\u0645\u0627\u064A.",
        rewardCoins: 150,
        isCompleted: false
      }
    ]
  };
  var AUCTION_ITEMS = [
    // --- Golf ---
    {
      id: "anvil",
      nameEN: "The Heavy Anvil",
      nameAR: "\u0627\u0644\u0633\u0646\u062F\u0627\u0646 \u0627\u0644\u062B\u0642\u064A\u0644",
      emoji: "\u{1FAA8}",
      blurbEN: "Crush a rival \u2014 their golf shots launch 30% weaker.",
      blurbAR: "\u0627\u0633\u062D\u0642 \u062E\u0635\u0645 \u2014 \u0636\u0631\u0628\u0627\u062A\u0647 \u0641\u064A \u0627\u0644\u0642\u0648\u0644\u0641 \u062A\u0637\u0644\u0639 \u0623\u0636\u0639\u0641 \u0663\u0660\u066A.",
      appliesTo: "golf",
      type: "sabotage",
      cost: 200
    },
    {
      id: "golden_club",
      nameEN: "Golden Club",
      nameAR: "\u0627\u0644\u0645\u0636\u0631\u0628 \u0627\u0644\u0630\u0647\u0628\u064A",
      emoji: "\u{1F3CC}\uFE0F",
      blurbEN: "Your own golf shots launch at DOUBLE power.",
      blurbAR: "\u0636\u0631\u0628\u0627\u062A\u0643 \u0641\u064A \u0627\u0644\u0642\u0648\u0644\u0641 \u062A\u0637\u0644\u0639 \u0628\u0636\u0639\u0641 \u0627\u0644\u0642\u0648\u0629.",
      appliesTo: "golf",
      type: "advantage",
      cost: 250
    },
    // --- Bomb ---
    {
      id: "butter",
      nameEN: "Butter Fingers",
      nameAR: "\u0623\u0635\u0627\u0628\u0639 \u0627\u0644\u0632\u0628\u062F\u0629",
      emoji: "\u{1F9C8}",
      blurbEN: "Grease a rival \u2014 their PASS jams for 2s on every catch.",
      blurbAR: "\u0632\u064A\u0651\u062A \u062E\u0635\u0645 \u2014 \u0632\u0631 \u0627\u0644\u062A\u0645\u0631\u064A\u0631 \u064A\u0639\u0644\u0651\u0642 \u062B\u0627\u0646\u064A\u062A\u064A\u0646 \u0643\u0644 \u0645\u0627 \u064A\u0645\u0633\u0643 \u0627\u0644\u0642\u0646\u0628\u0644\u0629.",
      appliesTo: "bomb",
      type: "sabotage",
      cost: 200
    },
    {
      id: "hazmat",
      nameEN: "Hazmat Suit",
      nameAR: "\u0628\u062F\u0644\u0629 \u0627\u0644\u0648\u0642\u0627\u064A\u0629",
      emoji: "\u{1F9EA}",
      blurbEN: "Shrug off ONE explosion \u2014 survive the first blast you hold.",
      blurbAR: "\u0627\u0637\u0644\u0639 \u0633\u0627\u0644\u0645 \u0645\u0646 \u0623\u0648\u0644 \u0627\u0646\u0641\u062C\u0627\u0631 \u064A\u0635\u064A\u0628\u0643.",
      appliesTo: "bomb",
      type: "advantage",
      cost: 250
    },
    // --- Bumper ---
    {
      id: "flat_tire",
      nameEN: "Flat Tire",
      nameAR: "\u0625\u0637\u0627\u0631 \u0645\u062B\u0642\u0648\u0628",
      emoji: "\u{1F6DE}",
      blurbEN: "Sap a rival \u2014 their push force is halved.",
      blurbAR: "\u0627\u0636\u0639\u0641 \u062E\u0635\u0645 \u2014 \u0642\u0648\u0629 \u062F\u0641\u0639\u0647 \u062A\u0646\u0635.",
      appliesTo: "bumper",
      type: "sabotage",
      cost: 200
    },
    {
      id: "nitro",
      nameEN: "Nitro Engine",
      nameAR: "\u0645\u062D\u0631\u0643 \u0646\u064A\u062A\u0631\u0648",
      emoji: "\u{1F525}",
      blurbEN: "+40% mass & shove impact \u2014 bully everyone off the slab.",
      blurbAR: "+\u0664\u0660\u066A \u0648\u0632\u0646 \u0648\u0642\u0648\u0629 \u062F\u0641\u0639 \u2014 \u0643\u0634\u0651\u062E\u0647\u0645 \u0628\u0631\u0647 \u0627\u0644\u062D\u0644\u0628\u0629.",
      appliesTo: "bumper",
      type: "advantage",
      cost: 250
    }
  ];
  function parseClientMessage(raw) {
    if (typeof raw !== "object" || raw === null) return null;
    const m = raw;
    if (typeof m.t !== "string") return null;
    return m;
  }

  // src/ids.ts
  function randomUUID() {
    var _a;
    const g = globalThis;
    if (typeof ((_a = g.crypto) == null ? void 0 : _a.randomUUID) === "function") return g.crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      const v = c === "x" ? r : r & 3 | 8;
      return v.toString(16);
    });
  }

  // src/room.ts
  var Room = class {
    constructor(code, onEmpty) {
      __publicField(this, "onEmpty", onEmpty);
      __publicField(this, "code");
      __publicField(this, "players", []);
      __publicField(this, "phase", "lobby");
      /** Ordered mini-games for this match, and where we are in it. */
      __publicField(this, "lineup", []);
      __publicField(this, "lineupIndex", 0);
      /** Host's in-progress game-picker (non-null only while phase === "selection"). */
      __publicField(this, "selection", null);
      __publicField(this, "auction", null);
      __publicField(this, "golf", null);
      __publicField(this, "bomb", null);
      __publicField(this, "bumper", null);
      __publicField(this, "replayVotes", /* @__PURE__ */ new Set());
      __publicField(this, "rev", 0);
      /** bumped on every phase/stage change so stale timer callbacks no-op */
      __publicField(this, "gen", 0);
      __publicField(this, "timers", []);
      __publicField(this, "lastActivity", Date.now());
      this.code = code;
    }
    // ------------------------------ lifecycle --------------------------------
    addPlayer(opts) {
      if (this.phase !== "lobby") return { ok: false, reason: "Game already in progress" };
      if (this.players.length >= CONST.MAX_PLAYERS) return { ok: false, reason: "Room is full" };
      const name = opts.name.trim().slice(0, 14);
      if (!name) return { ok: false, reason: "Name required" };
      if (this.players.some((p) => p.name.toLowerCase() === name.toLowerCase()))
        return { ok: false, reason: "That name is taken" };
      const player = {
        id: randomUUID(),
        token: randomUUID(),
        name,
        avatar: opts.avatar || "\u{1F642}",
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
        taskBumperSurvived: false
      };
      this.players.push(player);
      this.touch();
      this.broadcast();
      return { ok: true, player };
    }
    rejoin(playerId, token, ws) {
      const p = this.players.find((x) => x.id === playerId && x.token === token);
      if (!p) return null;
      if (p.ws && p.ws !== ws) {
        try {
          p.ws.close(4e3, "Replaced by reconnect");
        } catch (e) {
        }
      }
      p.ws = ws;
      this.touch();
      this.broadcast();
      return p;
    }
    handleDisconnect(playerId, ws) {
      const p = this.players.find((x) => x.id === playerId);
      if (!p || p.ws !== ws) return;
      p.ws = null;
      if (this.phase === "lobby" && !p.isHost) {
        this.players = this.players.filter((x) => x.id !== playerId);
      }
      this.touch();
      this.broadcast();
      if (this.players.every((x) => !x.ws)) this.scheduleEmptyCheck();
    }
    get isAbandoned() {
      return this.players.every((p) => !p.ws) && Date.now() - this.lastActivity > CONST.ROOM_MAX_IDLE_MS;
    }
    scheduleEmptyCheck() {
      var _a, _b;
      (_b = (_a = setTimeout(() => {
        if (this.isAbandoned) this.onEmpty(this);
      }, CONST.ROOM_MAX_IDLE_MS + 1e3)).unref) == null ? void 0 : _b.call(_a);
    }
    touch() {
      this.lastActivity = Date.now();
    }
    // ------------------------------ messaging --------------------------------
    send(p, msg) {
      if (p.ws && p.ws.readyState === p.ws.OPEN) {
        p.ws.send(JSON.stringify(msg));
      }
    }
    sendToHost(msg) {
      const host = this.players.find((p) => p.isHost);
      if (host) this.send(host, msg);
    }
    broadcast() {
      this.rev += 1;
      for (const p of this.players) {
        if (p.ws && p.ws.readyState === p.ws.OPEN) {
          const msg = { t: "room_state", state: this.viewState(p.id) };
          p.ws.send(JSON.stringify(msg));
        }
      }
    }
    sendError(playerId, message) {
      const p = this.players.find((x) => x.id === playerId);
      if (p) this.send(p, { t: "error", message });
    }
    /** Snapshot for a player who just (re)joined — goes in their room_joined. */
    snapshotFor(viewerId) {
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
    viewState(viewerId) {
      var _a, _b;
      const players = this.players.map((p) => ({
        id: p.id,
        name: p.name,
        avatar: p.avatar,
        color: p.color,
        trophies: p.trophies,
        coins: p.id === viewerId ? p.coins : 0,
        // mask everyone else's wallet
        connected: !!p.ws,
        isHost: p.isHost,
        modifier: p.modifier,
        // public buff/debuff (the boards read it to apply effects)
        // PRIVACY: a secret task only ever reaches its own owner (never the TV).
        secretTask: p.id === viewerId ? p.secretTask : null
      }));
      let selection = null;
      if (this.phase === "selection" && this.selection) {
        selection = { picks: this.selection.picks, size: CONST.LINEUP_SIZE };
      }
      let auction = null;
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
          targetId: this.auction.targetId
        };
      }
      let golf = null;
      if (this.phase === "golf" && this.golf) {
        const strokes = {};
        for (const p of this.players) {
          strokes[p.id] = ((_a = this.golf.priorStrokes[p.id]) != null ? _a : 0) + ((_b = this.golf.roundStrokes[p.id]) != null ? _b : 0);
        }
        golf = {
          endsAt: this.golf.endsAt,
          turnId: this.golf.turnId,
          sunk: this.golf.sunk,
          results: this.golf.results,
          round: this.golf.round,
          map: this.golf.map,
          strokes,
          spawnedCoins: this.golf.spawnedCoins
        };
      }
      let bomb = null;
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
          spawnedCoins: this.bomb.spawnedCoins
        };
      }
      let bumper = null;
      if (this.phase === "bumper" && this.bumper) {
        bumper = {
          endsAt: this.bumper.endsAt,
          alive: this.bumper.alive,
          eliminated: this.bumper.eliminated,
          winnerId: this.bumper.winnerId
        };
      }
      let podium = null;
      if (this.phase === "podium") {
        podium = {
          // Rank by most trophies; the hidden coin wallet is the absolute
          // tiebreaker (computed from the TRUE values, never the masked ones).
          ranking: this.rankedPlayerIds(),
          replayVotes: [...this.replayVotes]
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
        rev: this.rev
      };
    }
    /** Standings: most trophies first, hidden coins as the absolute tiebreaker. */
    rankedPlayerIds() {
      return [...this.players].sort((a, b) => b.trophies - a.trophies || b.coins - a.coins).map((p) => p.id);
    }
    // ------------------------------ timers -----------------------------------
    /** Schedule a callback that silently dies if the room moved on (gen changed). */
    after(ms, fn) {
      var _a;
      const gen = this.gen;
      const handle = setTimeout(() => {
        if (this.gen === gen) fn();
      }, ms);
      (_a = handle.unref) == null ? void 0 : _a.call(handle);
      this.timers.push(handle);
    }
    every(ms, fn) {
      var _a;
      const gen = this.gen;
      const handle = setInterval(() => {
        if (this.gen === gen) fn();
        else clearInterval(handle);
      }, ms);
      (_a = handle.unref) == null ? void 0 : _a.call(handle);
      this.timers.push(handle);
    }
    newGen() {
      this.gen += 1;
      for (const t of this.timers) clearTimeout(t);
      this.timers = [];
    }
    // ------------------------------ lobby ------------------------------------
    startGame(playerId) {
      const p = this.players.find((x) => x.id === playerId);
      if (!(p == null ? void 0 : p.isHost)) return this.sendError(playerId, "Only the host can start the game");
      if (this.phase !== "lobby") return;
      const connected = this.players.filter((x) => x.ws).length;
      const min = true ? 1 : CONST.MIN_PLAYERS;
      if (connected < min)
        return this.sendError(playerId, `Need at least ${CONST.MIN_PLAYERS} players`);
      this.touch();
      this.startSelection();
    }
    // --------------------------- game selection ------------------------------
    /** Open the host's game picker; the match lineup is built here. */
    startSelection() {
      this.newGen();
      this.phase = "selection";
      this.selection = { picks: [] };
      this.lineup = [];
      this.lineupIndex = 0;
      this.clearSecretTasks();
      this.broadcast();
    }
    /** Keep only valid game types, capped at the lineup size. */
    sanitizeLineup(lineup) {
      const valid = ["golf", "bomb", "bumper"];
      if (!Array.isArray(lineup)) return [];
      return lineup.filter((g) => valid.includes(g)).slice(0, CONST.LINEUP_SIZE);
    }
    /** Host live-updates the in-progress picks so the TV can mirror the slots. */
    previewLineup(playerId, lineup) {
      const p = this.players.find((x) => x.id === playerId);
      if (!(p == null ? void 0 : p.isHost)) return;
      if (this.phase !== "selection" || !this.selection) return;
      this.selection.picks = this.sanitizeLineup(lineup);
      this.touch();
      this.broadcast();
    }
    /** Host commits exactly LINEUP_SIZE games → overrides the lineup and starts. */
    selectLineup(playerId, lineup) {
      const p = this.players.find((x) => x.id === playerId);
      if (!(p == null ? void 0 : p.isHost)) return this.sendError(playerId, "Only the host picks the games");
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
    advanceLineup() {
      if (this.lineupIndex >= this.lineup.length) {
        this.startPodium();
        return;
      }
      this.startAuction(this.lineup[this.lineupIndex]);
    }
    /** Launch a mini-game by type (golf begins at its first round). */
    launchGame(game) {
      if (game === "golf") this.startGolf(1);
      else if (game === "bumper") this.startBumper();
      else this.startBomb();
    }
    // ------------------------------ auction ----------------------------------
    startAuction(forGame) {
      this.newGen();
      this.phase = "auction";
      this.clearSecretTasks();
      for (const p of this.players) {
        p.bid = null;
        p.bidItemId = null;
        p.bidLockedAt = 0;
      }
      const items = AUCTION_ITEMS.filter((it) => it.appliesTo === forGame);
      this.auction = {
        round: this.lineupIndex + 1,
        // 1-based position in the lineup, for display
        stage: "bidding",
        items,
        endsAt: Date.now() + CONST.AUCTION_BID_MS,
        winnerId: null,
        winningBid: null,
        winningItemId: null,
        targetId: null,
        forGame
      };
      this.after(CONST.AUCTION_BID_MS, () => this.resolveAuction());
      this.broadcast();
    }
    submitBid(playerId, amount, itemId) {
      if (this.phase !== "auction" || !this.auction || this.auction.stage !== "bidding") return;
      const p = this.players.find((x) => x.id === playerId);
      if (!p) return;
      if (p.bid !== null) return this.sendError(playerId, "Bid already locked in");
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
    resolveAuction() {
      var _a;
      if (!this.auction || this.auction.stage !== "bidding") return;
      const bidders = this.players.filter((p) => {
        var _a2;
        return ((_a2 = p.bid) != null ? _a2 : 0) > 0 && p.bidItemId !== null;
      }).sort((a, b) => b.bid - a.bid || a.bidLockedAt - b.bidLockedAt);
      const winner = (_a = bidders[0]) != null ? _a : null;
      const item = winner ? this.auction.items.find((it) => it.id === winner.bidItemId) : void 0;
      if (!winner || !item) {
        this.auction.stage = "reveal";
        this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
        this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
        this.broadcast();
        return;
      }
      winner.coins -= winner.bid;
      this.auction.winnerId = winner.id;
      this.auction.winningBid = winner.bid;
      this.auction.winningItemId = item.id;
      if (item.type === "advantage") {
        winner.modifier = item.id;
        this.auction.stage = "reveal";
        this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
        this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
        this.broadcast();
        return;
      }
      this.auction.stage = "targeting";
      this.auction.endsAt = Date.now() + CONST.AUCTION_TARGET_MS;
      this.after(CONST.AUCTION_TARGET_MS, () => {
        var _a2;
        if (((_a2 = this.auction) == null ? void 0 : _a2.stage) !== "targeting") return;
        const others = this.players.filter((p) => p.id !== winner.id);
        const target = others[Math.floor(Math.random() * others.length)];
        if (target) this.applyTarget(winner.id, target.id);
      });
      this.broadcast();
    }
    chooseTarget(playerId, targetId) {
      if (this.phase !== "auction" || !this.auction) return;
      if (this.auction.stage !== "targeting" || this.auction.winnerId !== playerId)
        return this.sendError(playerId, "You did not win the auction");
      if (targetId === playerId) return this.sendError(playerId, "Pick someone else, not yourself");
      if (!this.players.some((p) => p.id === targetId))
        return this.sendError(playerId, "Unknown target");
      this.applyTarget(playerId, targetId);
    }
    applyTarget(_winnerId, targetId) {
      if (!this.auction || this.auction.stage !== "targeting" || !this.auction.winningItemId) return;
      const target = this.players.find((p) => p.id === targetId);
      if (target) target.modifier = this.auction.winningItemId;
      this.auction.targetId = targetId;
      this.auction.stage = "reveal";
      this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
      this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
      this.touch();
      this.broadcast();
    }
    afterAuction() {
      if (!this.auction) return;
      this.launchGame(this.auction.forGame);
    }
    // ------------------------------ golf -------------------------------------
    /**
     * Golf is played over two rounds: Round 1 on Guerilla Golf, Round 2 on the
     * Tiki Jungle Adventure map. `priorStrokes` carries each player's running
     * stroke total into the next round so the leaderboard is cumulative.
     */
    startGolf(round, priorStrokes = {}) {
      var _a;
      this.newGen();
      this.phase = "golf";
      const prior = {};
      const round0 = {};
      for (const p of this.players) {
        prior[p.id] = (_a = priorStrokes[p.id]) != null ? _a : 0;
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
        spawnedCoins: []
        // the host board registers this round's layout once it builds
      };
      if (round === 1) this.assignSecretTasks("golf");
      this.after(CONST.GOLF_TIME_LIMIT_MS + 5e3, () => this.finishGolf([]));
      this.broadcast();
    }
    /** Turn-based: only the active player's inputs reach the board. */
    isOnTurn(playerId) {
      var _a;
      const turn = (_a = this.golf) == null ? void 0 : _a.turnId;
      return !turn || turn === playerId;
    }
    relayAim(playerId, angle, power) {
      if (this.phase !== "golf" || !this.isOnTurn(playerId)) return;
      this.sendToHost({ t: "aim", playerId, angle, power });
    }
    relayAimClear(playerId) {
      if (this.phase !== "golf") return;
      this.sendToHost({ t: "aim_clear", playerId });
    }
    relayFire(playerId, angle, power) {
      var _a;
      if (this.phase !== "golf" || !this.isOnTurn(playerId)) return;
      let strokeCounted = false;
      if (this.golf && this.golf.turnId === playerId) {
        this.golf.roundStrokes[playerId] = ((_a = this.golf.roundStrokes[playerId]) != null ? _a : 0) + 1;
        strokeCounted = true;
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
        power: Math.max(0, Math.min(1, power))
      });
      if (strokeCounted) this.broadcast();
    }
    /** Host board reports whose turn it is and who has sunk so far. */
    golfProgress(reporterId, turnId, sunk) {
      const reporter = this.players.find((p) => p.id === reporterId);
      if (!(reporter == null ? void 0 : reporter.isHost)) return;
      if (this.phase !== "golf" || !this.golf || this.golf.results) return;
      this.golf.turnId = turnId && this.players.some((p) => p.id === turnId) ? turnId : null;
      this.golf.sunk = sunk.filter((id) => this.players.some((p) => p.id === id));
      this.touch();
      this.broadcast();
    }
    golfFinished(reporterId, order) {
      const reporter = this.players.find((p) => p.id === reporterId);
      if (!(reporter == null ? void 0 : reporter.isHost)) return this.sendError(reporterId, "Only the host board reports results");
      this.finishGolf(order);
    }
    finishGolf(order) {
      var _a, _b;
      if (this.phase !== "golf" || !this.golf || this.golf.results) return;
      const golf = this.golf;
      const sinkers = order.filter((id) => this.players.some((p) => p.id === id));
      const totals = {};
      for (const p of this.players) {
        totals[p.id] = ((_a = golf.priorStrokes[p.id]) != null ? _a : 0) + ((_b = golf.roundStrokes[p.id]) != null ? _b : 0);
      }
      const ranking = [...sinkers].sort((a, b) => {
        const sa = totals[a], sb = totals[b];
        if (sa !== sb) return sa - sb;
        return sinkers.indexOf(a) - sinkers.indexOf(b);
      });
      const awarded = {};
      for (const p of this.players) awarded[p.id] = 0;
      if (golf.round < 3) {
        golf.results = { order: ranking, awarded };
        this.newGen();
        this.after(CONST.GOLF_RESULTS_MS, () => this.startGolf(golf.round + 1, totals));
      } else {
        const winnerId = ranking[0];
        if (winnerId) {
          awarded[winnerId] = CONST.TROPHY;
          const winner = this.players.find((x) => x.id === winnerId);
          if (winner) winner.trophies += CONST.TROPHY;
        }
        for (const p of this.players) p.modifier = null;
        for (const p of this.players) this.evaluateSecretTask(p);
        golf.results = { order: ranking, awarded };
        this.newGen();
        this.lineupIndex += 1;
        this.after(CONST.GOLF_RESULTS_MS, () => this.advanceLineup());
      }
      this.touch();
      this.broadcast();
    }
    // ------------------------------ coins ------------------------------------
    /** Keep only well-formed coins (id + finite x/y/z), capped to a sane count. */
    sanitizeCoins(coins) {
      if (!Array.isArray(coins)) return [];
      const num = (v) => typeof v === "number" && Number.isFinite(v) ? v : 0;
      return coins.filter((c) => typeof c === "object" && c !== null && typeof c.id === "string").slice(0, 8).map((c) => ({ id: String(c.id), x: num(c.x), y: num(c.y), z: num(c.z) }));
    }
    /** Host board registers the loose coins it placed on this golf round's course. */
    registerCoins(reporterId, coins) {
      const reporter = this.players.find((p) => p.id === reporterId);
      if (!(reporter == null ? void 0 : reporter.isHost)) return;
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
    collectCoin(reporterId, coinId, collectorId) {
      const reporter = this.players.find((p) => p.id === reporterId);
      if (!(reporter == null ? void 0 : reporter.isHost)) return;
      if (this.phase !== "golf" || !this.golf) return;
      const idx = this.golf.spawnedCoins.findIndex((c) => c.id === coinId);
      if (idx === -1) return;
      this.golf.spawnedCoins.splice(idx, 1);
      const collector = this.players.find((p) => p.id === collectorId);
      if (collector) {
        collector.coins += CONST.COIN_VALUE;
        collector.taskCoins += 1;
      }
      this.touch();
      this.broadcast();
    }
    // --------------------------- secret tasks --------------------------------
    /** Assign each player ONE random hidden objective and reset its telemetry. */
    assignSecretTasks(game) {
      const pool = SECRET_TASKS[game];
      for (const p of this.players) {
        const pick = pool[Math.floor(Math.random() * pool.length)];
        p.secretTask = { ...pick, isCompleted: false };
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
    clearSecretTasks() {
      for (const p of this.players) p.secretTask = null;
    }
    /** Host board reports a ball fell in water / out of bounds (fails Safe Play). */
    reportBallReset(reporterId, playerId) {
      const reporter = this.players.find((p2) => p2.id === reporterId);
      if (!(reporter == null ? void 0 : reporter.isHost) || this.phase !== "golf") return;
      const p = this.players.find((x) => x.id === playerId);
      if (p) p.taskReset = true;
    }
    /** Check one player's task against the game's telemetry and pay out if met. */
    evaluateSecretTask(p) {
      const task = p.secretTask;
      if (!task || task.isCompleted) return;
      let done = false;
      switch (task.id) {
        case "long_shot":
          done = p.taskMaxPower;
          break;
        case "greedy_golfer":
          done = p.taskCoins >= 2;
          break;
        case "safe_play":
          done = !p.taskReset;
          break;
        case "hot_potato":
          done = p.taskBombHotPotato;
          break;
        case "survivor":
          done = p.taskBombHoldMs <= 5e3;
          break;
        case "aggressor":
          done = p.taskBumperAggressor;
          break;
        case "pacifist":
          done = p.taskBumperSurvived;
          break;
      }
      if (done) {
        task.isCompleted = true;
        p.coins += task.rewardCoins;
      }
    }
    /** Scatter 2–3 coins around the 2-D bomb arena (fractional screen coords). */
    generateBombCoins() {
      const count = 2 + Math.floor(Math.random() * 2);
      const coins = [];
      for (let i = 0; i < count; i++) {
        const x = 0.16 + Math.random() * 0.68;
        const y = 0.24 + Math.random() * 0.42;
        coins.push({ id: `bcoin-${i}`, x, y, z: 0 });
      }
      return coins;
    }
    // ------------------------------ bomb -------------------------------------
    startBomb() {
      this.newGen();
      this.phase = "bomb";
      const earnings = {};
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
        holderSince: null
      };
      this.assignSecretTasks("bomb");
      this.startBombRound();
    }
    startBombRound() {
      const bomb = this.bomb;
      if (!bomb) return;
      this.newGen();
      bomb.stage = "ticking";
      bomb.multiplier = 1;
      const holder = bomb.alive[Math.floor(Math.random() * bomb.alive.length)];
      this.setBombHolder(holder);
      const fuse = CONST.BOMB_FUSE_MIN_MS + Math.random() * (CONST.BOMB_FUSE_MAX_MS - CONST.BOMB_FUSE_MIN_MS);
      this.after(fuse, () => this.explodeBomb());
      this.every(CONST.BOMB_TICK_MS, () => {
        var _a;
        if (!bomb.holderId) return;
        bomb.earnings[bomb.holderId] = ((_a = bomb.earnings[bomb.holderId]) != null ? _a : 0) + Math.round(CONST.BOMB_CASH_PER_TICK * bomb.multiplier);
        bomb.multiplier = Math.round((bomb.multiplier + CONST.BOMB_MULT_STEP) * 100) / 100;
        this.broadcast();
      });
      this.broadcast();
    }
    setBombHolder(playerId) {
      const bomb = this.bomb;
      if (!bomb) return;
      const now = Date.now();
      if (bomb.holderId && bomb.holderSince != null) {
        const prev = this.players.find((p) => p.id === bomb.holderId);
        if (prev) prev.taskBombHoldMs += now - bomb.holderSince;
      }
      bomb.holderId = playerId;
      bomb.holderSince = now;
      bomb.multiplier = 1;
      const holder = this.players.find((p) => p.id === playerId);
      bomb.jamUntil = (holder == null ? void 0 : holder.modifier) === "butter" ? now + CONST.BOMB_JAM_MS : null;
    }
    passBomb(playerId, direction) {
      const bomb = this.bomb;
      if (this.phase !== "bomb" || !bomb || bomb.stage !== "ticking") return;
      if (bomb.holderId !== playerId) return this.sendError(playerId, "You are not holding the bomb");
      if (bomb.jamUntil && Date.now() < bomb.jamUntil)
        return this.sendError(playerId, "Butter fingers! The button is jammed");
      const idx = bomb.alive.indexOf(playerId);
      if (idx === -1) return;
      const step = direction === "left" ? -1 : 1;
      const next = bomb.alive[(idx + step + bomb.alive.length) % bomb.alive.length];
      if (next === playerId) return;
      if (bomb.holderSince != null && Date.now() - bomb.holderSince <= 1e3) {
        const passer = this.players.find((p) => p.id === playerId);
        if (passer) passer.taskBombHotPotato = true;
      }
      this.setBombHolder(next);
      const coin = bomb.spawnedCoins.shift();
      if (coin) {
        const passer = this.players.find((p) => p.id === playerId);
        if (passer) passer.coins += CONST.COIN_VALUE;
      }
      this.touch();
      this.broadcast();
    }
    explodeBomb() {
      const bomb = this.bomb;
      if (!bomb || bomb.stage !== "ticking" || !bomb.holderId) return;
      const victim = bomb.holderId;
      this.newGen();
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
      if ((victimP == null ? void 0 : victimP.modifier) === "hazmat") {
        victimP.modifier = null;
      } else {
        bomb.earnings[victim] = 0;
        bomb.alive = bomb.alive.filter((id) => id !== victim);
        bomb.eliminated.push(victim);
      }
      this.broadcast();
      this.after(CONST.BOMB_ROUND_BREAK_MS, () => {
        if (bomb.alive.length <= 2) this.finishBomb();
        else this.startBombRound();
      });
    }
    finishBomb() {
      var _a;
      const bomb = this.bomb;
      if (!bomb) return;
      this.newGen();
      if (bomb.holderId && bomb.holderSince != null) {
        const h = this.players.find((p) => p.id === bomb.holderId);
        if (h) h.taskBombHoldMs += Date.now() - bomb.holderSince;
      }
      bomb.stage = "done";
      bomb.holderId = null;
      bomb.holderSince = null;
      bomb.survivors = [...bomb.alive];
      for (const p of this.players) {
        p.coins += (_a = bomb.earnings[p.id]) != null ? _a : 0;
        if (bomb.survivors.includes(p.id)) {
          p.trophies += CONST.TROPHY;
          p.coins += CONST.BOMB_SURVIVOR_BONUS;
        }
        p.modifier = null;
        this.evaluateSecretTask(p);
      }
      this.broadcast();
      this.lineupIndex += 1;
      this.after(CONST.BOMB_ROUND_BREAK_MS, () => this.advanceLineup());
    }
    // ------------------------------ bumper -----------------------------------
    startBumper() {
      this.newGen();
      this.phase = "bumper";
      const now = Date.now();
      this.bumper = {
        endsAt: now + CONST.BUMPER_TIME_MS,
        alive: this.players.map((p) => p.id),
        eliminated: [],
        winnerId: null,
        startedAt: now
      };
      this.assignSecretTasks("bumper");
      this.after(CONST.BUMPER_TIME_MS, () => this.finishBumper());
      this.broadcast();
    }
    /** Stream a player's joystick vector to the host board, which runs the physics. */
    updateJoystick(playerId, x, y) {
      if (this.phase !== "bumper" || !this.bumper) return;
      if (!this.bumper.alive.includes(playerId)) return;
      this.sendToHost({ t: "joystick", playerId, x, y });
    }
    /** Host board reports a player splashed off the slab; `byPlayerId` shoved them. */
    bumperKnockout(reporterId, playerId, byPlayerId) {
      const reporter = this.players.find((p) => p.id === reporterId);
      if (!(reporter == null ? void 0 : reporter.isHost)) return;
      const bumper = this.bumper;
      if (this.phase !== "bumper" || !bumper) return;
      if (!bumper.alive.includes(playerId)) return;
      bumper.alive = bumper.alive.filter((id) => id !== playerId);
      bumper.eliminated.push(playerId);
      if (byPlayerId) {
        const aggressor = this.players.find((p) => p.id === byPlayerId);
        if (aggressor && byPlayerId !== playerId) aggressor.taskBumperAggressor = true;
      }
      this.touch();
      if (bumper.alive.length <= 1) {
        this.finishBumper();
      } else {
        this.broadcast();
      }
    }
    finishBumper() {
      const bumper = this.bumper;
      if (this.phase !== "bumper" || !bumper) return;
      this.newGen();
      bumper.winnerId = bumper.alive.length === 1 ? bumper.alive[0] : null;
      const elapsed = Date.now() - bumper.startedAt;
      for (const p of this.players) {
        const survived = bumper.alive.includes(p.id);
        if (survived) p.trophies += CONST.TROPHY;
        p.taskBumperSurvived = survived && (bumper.winnerId === p.id || elapsed >= CONST.BUMPER_PACIFIST_MS);
        this.evaluateSecretTask(p);
        p.modifier = null;
      }
      this.broadcast();
      this.lineupIndex += 1;
      this.after(CONST.BUMPER_RESULTS_MS, () => this.advanceLineup());
    }
    // ------------------------------ podium -----------------------------------
    startPodium() {
      this.newGen();
      this.phase = "podium";
      this.replayVotes.clear();
      this.touch();
      this.broadcast();
    }
    voteReplay(playerId) {
      if (this.phase !== "podium") return;
      if (!this.players.some((p) => p.id === playerId)) return;
      this.replayVotes.add(playerId);
      this.touch();
      const connected = this.players.filter((p) => p.ws);
      const everyoneIn = connected.length > 0 && connected.every((p) => this.replayVotes.has(p.id));
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
        this.startSelection();
      } else {
        this.broadcast();
      }
    }
  };
  var CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  var RoomManager = class {
    constructor() {
      __publicField(this, "rooms", /* @__PURE__ */ new Map());
      var _a, _b;
      (_b = (_a = setInterval(() => {
        for (const [code, room] of this.rooms) {
          if (room.isAbandoned) {
            this.rooms.delete(code);
            console.log(`[room ${code}] swept (abandoned)`);
          }
        }
      }, CONST.ROOM_IDLE_SWEEP_MS)).unref) == null ? void 0 : _b.call(_a);
    }
    create() {
      let code;
      do {
        code = Array.from(
          { length: 4 },
          () => CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]
        ).join("");
      } while (this.rooms.has(code));
      const room = new Room(code, (r) => this.rooms.delete(r.code));
      this.rooms.set(code, room);
      return room;
    }
    get(code) {
      return this.rooms.get(code.trim().toUpperCase());
    }
    get stats() {
      return { rooms: this.rooms.size };
    }
  };

  // src/dispatch.ts
  function handleClientMessage(manager2, conn, ws, msg) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const reply = (m) => ws.send(JSON.stringify(m));
    const fail = (message) => reply({ t: "error", message });
    try {
      switch (msg.t) {
        case "create_room": {
          if (conn.room) return fail("Already in a room");
          const room = manager2.create();
          const res = room.addPlayer({
            name: String((_a = msg.name) != null ? _a : ""),
            avatar: String((_b = msg.avatar) != null ? _b : ""),
            color: String((_c = msg.color) != null ? _c : ""),
            isHost: true,
            ws
          });
          if (!res.ok) return fail(res.reason);
          conn.room = room;
          conn.playerId = res.player.id;
          reply({
            t: "room_joined",
            playerId: res.player.id,
            token: res.player.token,
            state: room.snapshotFor(res.player.id)
          });
          break;
        }
        case "join_room": {
          if (conn.room) return fail("Already in a room");
          const room = manager2.get(String((_d = msg.code) != null ? _d : ""));
          if (!room) return fail("Room not found \u2014 check the code");
          const res = room.addPlayer({
            name: String((_e = msg.name) != null ? _e : ""),
            avatar: String((_f = msg.avatar) != null ? _f : ""),
            color: String((_g = msg.color) != null ? _g : ""),
            isHost: false,
            ws
          });
          if (!res.ok) return fail(res.reason);
          conn.room = room;
          conn.playerId = res.player.id;
          reply({
            t: "room_joined",
            playerId: res.player.id,
            token: res.player.token,
            state: room.snapshotFor(res.player.id)
          });
          break;
        }
        case "rejoin": {
          const room = manager2.get(String((_h = msg.code) != null ? _h : ""));
          if (!room) return fail("Room not found");
          const player = room.rejoin(String(msg.playerId), String(msg.token), ws);
          if (!player) return fail("Could not rejoin \u2014 seat not found");
          conn.room = room;
          conn.playerId = player.id;
          reply({
            t: "room_joined",
            playerId: player.id,
            token: player.token,
            state: room.snapshotFor(player.id)
          });
          break;
        }
        default: {
          const { room, playerId } = conn;
          if (!room || !playerId) return fail("Join a room first");
          switch (msg.t) {
            case "start_game":
              room.startGame(playerId);
              break;
            case "preview_lineup":
              room.previewLineup(playerId, msg.lineup);
              break;
            case "select_lineup":
              room.selectLineup(playerId, msg.lineup);
              break;
            case "register_coins":
              room.registerCoins(playerId, msg.coins);
              break;
            case "collect_coin":
              room.collectCoin(playerId, String(msg.coinId), String(msg.playerId));
              break;
            case "ball_reset":
              room.reportBallReset(playerId, String(msg.playerId));
              break;
            case "submit_bid":
              room.submitBid(playerId, Number(msg.amount), msg.itemId);
              break;
            case "choose_target":
              room.chooseTarget(playerId, String(msg.targetId));
              break;
            case "aim":
              room.relayAim(playerId, Number(msg.angle), Number(msg.power));
              break;
            case "aim_clear":
              room.relayAimClear(playerId);
              break;
            case "fire":
              room.relayFire(playerId, Number(msg.angle), Number(msg.power));
              break;
            case "golf_finished":
              room.golfFinished(playerId, Array.isArray(msg.order) ? msg.order.map(String) : []);
              break;
            case "golf_progress":
              room.golfProgress(
                playerId,
                typeof msg.turnId === "string" ? msg.turnId : null,
                Array.isArray(msg.sunk) ? msg.sunk.map(String) : []
              );
              break;
            case "pass_bomb":
              room.passBomb(playerId, msg.direction === "left" ? "left" : "right");
              break;
            case "update_joystick":
              room.updateJoystick(playerId, Number(msg.x), Number(msg.y));
              break;
            case "bumper_knockout":
              room.bumperKnockout(
                playerId,
                String(msg.playerId),
                typeof msg.byPlayerId === "string" ? msg.byPlayerId : null
              );
              break;
            case "replay":
              room.voteReplay(playerId);
              break;
            case "leave":
              room.handleDisconnect(playerId, ws);
              conn.room = null;
              conn.playerId = null;
              break;
          }
        }
      }
    } catch (err) {
      console.error("message handling error:", err);
      fail("Server error");
    }
  }

  // src/embedded.ts
  var NativeSocket = class {
    constructor(connId) {
      __publicField(this, "connId", connId);
      __publicField(this, "OPEN", 1);
      __publicField(this, "readyState", 1);
    }
    send(text) {
      if (this.readyState === this.OPEN) __frantics_send(this.connId, text);
    }
    close() {
      if (this.readyState !== 3) {
        this.readyState = 3;
        __frantics_close(this.connId);
      }
    }
  };
  var manager = new RoomManager();
  var conns = /* @__PURE__ */ new Map();
  var FranticsEngine = {
    /** A new WebSocket connection opened. */
    open(connId) {
      conns.set(connId, { conn: { room: null, playerId: null }, ws: new NativeSocket(connId) });
    },
    /** A text frame arrived on a connection. */
    message(connId, text) {
      const entry = conns.get(connId);
      if (!entry) return;
      let parsed;
      try {
        parsed = JSON.parse(text);
      } catch (e) {
        return entry.ws.send(JSON.stringify({ t: "error", message: "Malformed JSON" }));
      }
      const msg = parseClientMessage(parsed);
      if (!msg) return entry.ws.send(JSON.stringify({ t: "error", message: "Missing message type" }));
      handleClientMessage(manager, entry.conn, entry.ws, msg);
    },
    /** A connection closed (or dropped). Free the seat's socket. */
    close(connId) {
      const entry = conns.get(connId);
      if (!entry) return;
      const { conn, ws } = entry;
      ws.readyState = 3;
      if (conn.room && conn.playerId) conn.room.handleDisconnect(conn.playerId, ws);
      conns.delete(connId);
    }
  };
  globalThis.FranticsEngine = FranticsEngine;
})();
