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
    START_POINTS: 1e3,
    AUCTION_BID_MS: FAST ? 600 : 15e3,
    AUCTION_TARGET_MS: FAST ? 600 : 12e3,
    AUCTION_REVEAL_MS: FAST ? 400 : 5e3,
    GOLF_TIME_LIMIT_MS: FAST ? 1500 : 15e4,
    // turn-based: everyone needs shots
    GOLF_RESULTS_MS: FAST ? 400 : 6e3,
    GOLF_BOUNTIES: [500, 300, 200],
    GOLF_FINISH_POINTS: 100,
    BOMB_TICK_MS: FAST ? 100 : 1e3,
    BOMB_CASH_PER_TICK: 25,
    BOMB_MULT_STEP: 0.25,
    BOMB_FUSE_MIN_MS: FAST ? 500 : 1e4,
    BOMB_FUSE_MAX_MS: FAST ? 1200 : 25e3,
    BOMB_ROUND_BREAK_MS: FAST ? 400 : 4e3,
    BOMB_SURVIVOR_BONUS: 250,
    BOMB_JAM_MS: FAST ? 300 : 2e3,
    ROOM_IDLE_SWEEP_MS: 6e4,
    ROOM_MAX_IDLE_MS: 10 * 6e4
  };
  var SABOTAGE_ITEMS = [
    {
      id: "anvil",
      name: "The Heavy Anvil",
      emoji: "\u{1FAA8}",
      blurb: "Crush a rival! Their golf shots launch 30% weaker.",
      appliesTo: "golf",
      debuff: "anvil"
    },
    {
      id: "butter",
      name: "Butter Fingers",
      emoji: "\u{1F9C8}",
      blurb: "Grease a rival! Their PASS button jams for 2s every time they catch the bomb.",
      appliesTo: "bomb",
      debuff: "jammed"
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
      __publicField(this, "auction", null);
      __publicField(this, "golf", null);
      __publicField(this, "bomb", null);
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
        score: CONST.START_POINTS,
        isHost: opts.isHost,
        debuff: null,
        ws: opts.ws,
        bid: null,
        bidLockedAt: 0
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
      const msg = { t: "room_state", state: this.snapshot() };
      const raw = JSON.stringify(msg);
      for (const p of this.players) {
        if (p.ws && p.ws.readyState === p.ws.OPEN) p.ws.send(raw);
      }
    }
    sendError(playerId, message) {
      const p = this.players.find((x) => x.id === playerId);
      if (p) this.send(p, { t: "error", message });
    }
    snapshot() {
      var _a, _b;
      this.rev += 1;
      const players = this.players.map((p) => ({
        id: p.id,
        name: p.name,
        avatar: p.avatar,
        color: p.color,
        score: p.score,
        connected: !!p.ws,
        isHost: p.isHost,
        debuff: p.debuff
      }));
      let auction = null;
      if (this.phase === "auction" && this.auction) {
        auction = {
          round: this.auction.round,
          stage: this.auction.stage,
          item: this.auction.item,
          endsAt: this.auction.endsAt,
          lockedIn: this.players.filter((p) => p.bid !== null).map((p) => p.id),
          winnerId: this.auction.winnerId,
          winningBid: this.auction.winningBid,
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
          debuffs: this.golf.debuffs,
          turnId: this.golf.turnId,
          sunk: this.golf.sunk,
          results: this.golf.results,
          round: this.golf.round,
          map: this.golf.map,
          strokes
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
          survivors: this.bomb.survivors
        };
      }
      let podium = null;
      if (this.phase === "podium") {
        podium = {
          ranking: [...this.players].sort((a, b) => b.score - a.score).map((p) => p.id),
          replayVotes: [...this.replayVotes]
        };
      }
      return { code: this.code, phase: this.phase, players, auction, golf, bomb, podium, rev: this.rev };
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
      this.startAuction(1);
    }
    // ------------------------------ auction ----------------------------------
    startAuction(round) {
      this.newGen();
      this.phase = "auction";
      for (const p of this.players) {
        p.bid = null;
        p.bidLockedAt = 0;
      }
      const item = SABOTAGE_ITEMS[(round - 1) % SABOTAGE_ITEMS.length];
      this.auction = {
        round,
        stage: "bidding",
        item,
        endsAt: Date.now() + CONST.AUCTION_BID_MS,
        winnerId: null,
        winningBid: null,
        targetId: null
      };
      this.after(CONST.AUCTION_BID_MS, () => this.resolveAuction());
      this.broadcast();
    }
    submitBid(playerId, amount) {
      if (this.phase !== "auction" || !this.auction || this.auction.stage !== "bidding") return;
      const p = this.players.find((x) => x.id === playerId);
      if (!p) return;
      if (p.bid !== null) return this.sendError(playerId, "Bid already locked in");
      const clamped = Math.max(0, Math.min(p.score, Math.floor(amount)));
      p.bid = clamped;
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
        return ((_a2 = p.bid) != null ? _a2 : 0) > 0;
      }).sort((a, b) => b.bid - a.bid || a.bidLockedAt - b.bidLockedAt);
      const winner = (_a = bidders[0]) != null ? _a : null;
      if (!winner) {
        this.auction.stage = "reveal";
        this.auction.endsAt = Date.now() + CONST.AUCTION_REVEAL_MS;
        this.after(CONST.AUCTION_REVEAL_MS, () => this.afterAuction());
        this.broadcast();
        return;
      }
      winner.score -= winner.bid;
      this.auction.winnerId = winner.id;
      this.auction.winningBid = winner.bid;
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
    afterAuction() {
      if (!this.auction) return;
      if (this.auction.round === 1) this.startGolf(1);
      else this.startBomb();
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
      const debuffs = {};
      const prior = {};
      const round0 = {};
      for (const p of this.players) {
        if (p.debuff === "anvil") debuffs[p.id] = "anvil";
        prior[p.id] = (_a = priorStrokes[p.id]) != null ? _a : 0;
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
        roundStrokes: round0
      };
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
        ranking.forEach((id, i) => {
          var _a2;
          const points = (_a2 = CONST.GOLF_BOUNTIES[i]) != null ? _a2 : CONST.GOLF_FINISH_POINTS;
          awarded[id] = points;
          const p = this.players.find((x) => x.id === id);
          if (p) p.score += points;
        });
        for (const p of this.players) if (p.debuff === "anvil") p.debuff = null;
        golf.results = { order: ranking, awarded };
        this.newGen();
        this.after(CONST.GOLF_RESULTS_MS, () => this.startAuction(2));
      }
      this.touch();
      this.broadcast();
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
        survivors: null
      };
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
      bomb.holderId = playerId;
      bomb.multiplier = 1;
      const holder = this.players.find((p) => p.id === playerId);
      bomb.jamUntil = (holder == null ? void 0 : holder.debuff) === "jammed" ? Date.now() + CONST.BOMB_JAM_MS : null;
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
      this.setBombHolder(next);
      this.touch();
      this.broadcast();
    }
    explodeBomb() {
      const bomb = this.bomb;
      if (!bomb || bomb.stage !== "ticking" || !bomb.holderId) return;
      const victim = bomb.holderId;
      this.newGen();
      bomb.stage = "exploded";
      bomb.lastExplodedId = victim;
      bomb.earnings[victim] = 0;
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
    finishBomb() {
      var _a;
      const bomb = this.bomb;
      if (!bomb) return;
      this.newGen();
      bomb.stage = "done";
      bomb.holderId = null;
      bomb.survivors = [...bomb.alive];
      for (const p of this.players) {
        p.score += (_a = bomb.earnings[p.id]) != null ? _a : 0;
        if (bomb.survivors.includes(p.id)) p.score += CONST.BOMB_SURVIVOR_BONUS;
        if (p.debuff === "jammed") p.debuff = null;
      }
      this.broadcast();
      this.after(CONST.BOMB_ROUND_BREAK_MS, () => this.startPodium());
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
          p.score = CONST.START_POINTS;
          p.debuff = null;
        }
        this.golf = null;
        this.bomb = null;
        this.replayVotes.clear();
        this.startAuction(1);
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
            state: room.snapshot()
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
            state: room.snapshot()
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
            state: room.snapshot()
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
            case "submit_bid":
              room.submitBid(playerId, Number(msg.amount));
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
