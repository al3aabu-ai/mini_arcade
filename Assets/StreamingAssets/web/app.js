/* Mini Arcade — phone controller web app.
   Faithful to the Claude Design screens; client-side navigation now, with a
   WebSocket hook to the Unity host (wired in Stage 2). */
(function () {
  "use strict";

  var el = function (id) { return document.getElementById(id); };
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]; }); }
  function toast(msg) {
    var t = el("toast"); t.textContent = msg; t.classList.add("show");
    clearTimeout(toast._t); toast._t = setTimeout(function () { t.classList.remove("show"); }, 1700);
  }

  // ---- shared art ----
  var FACES = [
    '<circle cx="18" cy="20" r="3" fill="#3b0d73"/><circle cx="30" cy="20" r="3" fill="#3b0d73"/><path d="M16 29q8 8 16 0" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round"/>',
    '<rect x="11" y="16" width="26" height="8" rx="3" fill="#3b0d73"/><rect x="22" y="18" width="4" height="2" fill="#3b0d73"/><path d="M18 30q6 5 12 0" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round"/>',
    '<circle cx="18" cy="20" r="3" fill="#3b0d73"/><path d="M27 20h6" stroke="#3b0d73" stroke-width="3" stroke-linecap="round"/><path d="M16 29q8 7 16 0" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round"/>',
    '<circle cx="18" cy="19" r="3" fill="#3b0d73"/><circle cx="30" cy="19" r="3" fill="#3b0d73"/><circle cx="24" cy="31" r="4" stroke="#3b0d73" stroke-width="3" fill="none"/>',
    '<circle cx="18" cy="19" r="3" fill="#3b0d73"/><circle cx="30" cy="19" r="3" fill="#3b0d73"/><path d="M15 27q9 11 18 0z" fill="#3b0d73"/>',
    '<path d="M18 14l1.6 4L24 19l-4.4 1L18 24l-1.6-4L12 19l4.4-1z"/><path d="M30 14l1.6 4L36 19l-4.4 1L30 24l-1.6-4L24.8 19 30 18z"/><path d="M16 30q8 7 16 0" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round"/>',
    '<path d="M14 21l4-4 4 4" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M26 21l4-4 4 4" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M16 29q8 7 16 0" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round"/>',
    '<circle cx="18" cy="19" r="3" fill="#3b0d73"/><circle cx="30" cy="19" r="3" fill="#3b0d73"/><path d="M16 28q8 7 16 0" stroke="#3b0d73" stroke-width="3" fill="none" stroke-linecap="round"/><path d="M21 33h6v3a3 3 0 0 1-6 0z" fill="#FF5DA2"/>'
  ];
  function faceSvg(i, size) {
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 48 48" fill="#3b0d73">' + (FACES[i] || FACES[0]) + '</svg>';
  }
  var COLORS = ["#FF5DA2", "#FFD23F", "#38E1FF", "#B6FF4B", "#fb923c", "#a855f7"];

  var GAMES = [
    { key: "golf", name: "Mini Golf", short: "Golf", sub: "Precision · sink the trickiest shots", bg: "linear-gradient(160deg,#34d399,#059669)",
      svg: '<svg width="110" height="120" viewBox="0 0 76 84" fill="none"><ellipse cx="38" cy="68" rx="30" ry="8" fill="rgba(0,0,0,0.18)"/><rect x="36" y="10" width="4.5" height="54" rx="2" fill="#fff"/><path d="M40 12h22l-7 8 7 8H40z" fill="#FF5DA2"/><circle cx="20" cy="64" r="8" fill="#fff"/></svg>' },
    { key: "sumo", name: "Sumo Smash", short: "Sumo", sub: "Brawl · shove rivals off the ring", bg: "linear-gradient(160deg,#fb923c,#ea580c)",
      svg: '<svg width="130" height="96" viewBox="0 0 96 70" fill="none"><circle cx="34" cy="40" r="24" fill="#3b0d73"/><circle cx="64" cy="40" r="24" fill="#fff"/><circle cx="27" cy="35" r="3.5" fill="#fff"/><circle cx="71" cy="35" r="3.5" fill="#3b0d73"/></svg>' },
    { key: "bomb", name: "Hot Bomb", short: "Bomb", sub: "Chaos · don't be holding it at zero", bg: "linear-gradient(160deg,#f472b6,#db2777)",
      svg: '<svg width="112" height="120" viewBox="0 0 78 84" fill="none"><circle cx="34" cy="50" r="24" fill="#1a1a22"/><rect x="40" y="20" width="8" height="14" rx="3" fill="#1a1a22"/><path d="M46 22c8-4 6-12 12-14" stroke="#1a1a22" stroke-width="3.5" fill="none" stroke-linecap="round"/><circle cx="61" cy="7" r="6" fill="#FFD23F"/><circle cx="26" cy="44" r="6" fill="rgba(255,255,255,0.28)"/></svg>' },
    { key: "kart", name: "Kart Dash", sub: "Racing · unlock with Premium", locked: true,
      svg: '<svg width="120" height="90" viewBox="0 0 120 90" fill="none"><circle cx="32" cy="62" r="16" fill="#1a1a22"/><circle cx="88" cy="62" r="16" fill="#1a1a22"/><rect x="24" y="32" width="72" height="22" rx="8" fill="#fff"/></svg>' },
    { key: "sky", name: "Sky Hop", sub: "Platformer · unlock with Premium", locked: true,
      svg: '<svg width="100" height="100" viewBox="0 0 100 100" fill="none"><rect x="20" y="64" width="60" height="14" rx="4" fill="#fff"/><path d="M50 20l16 28H34z" fill="#fff"/></svg>' }
  ];

  // ---- state ----
  var state = {
    screen: "home", role: "player", name: "Player", avatar: 0, color: "#FF5DA2",
    code: "", hostName: "Host", isPremium: false, myId: null,
    players: [], selected: ["golf", "sumo", "bomb"], mode: "wins",
    bidAmount: 0, bidMax: 0, bidSubmitted: false
  };
  var ws = null;

  // ---- router ----
  function go(name) {
    state.screen = name;
    var list = document.querySelectorAll(".screen");
    for (var i = 0; i < list.length; i++) list[i].classList.remove("active");
    el("screen-" + name).classList.add("active");
    if (name === "setup") applySetupMode();
    if (name === "lobby") renderLobby();
    if (name === "pick") renderPick();
  }

  // ---- setup (join / host) ----
  function applySetupMode() {
    var host = state.role === "host";
    el("setup-title").textContent = host ? "Host a Game" : "Join a Game";
    el("setup-badge").innerHTML = host
      ? '<div style="display:flex;align-items:center;gap:5px;padding:6px 11px;border-radius:999px;background:rgba(255,210,63,0.16);border:1px solid rgba(255,210,63,0.4);"><svg width="12" height="12" viewBox="0 0 24 24" fill="#FFD23F"><path d="M12 2l2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4z"/></svg><span style="font-size:11px;font-weight:700;color:#FFD23F;letter-spacing:0.5px;">HOST</span></div>'
      : "";
    el("setup-codewrap").style.display = host ? "none" : "block";
    el("setup-confirm-label").textContent = host ? "Create Room" : "That's me — Join!";
    el("setup-name").value = state.name;
    renderAvatar(); renderChars(); renderColors();
  }
  function renderAvatar() {
    var a = el("setup-avatar");
    a.style.background = state.color;
    a.innerHTML = faceSvg(state.avatar, 58);
  }
  function renderChars() {
    var box = el("setup-chars"); box.innerHTML = "";
    for (var i = 0; i < FACES.length; i++) {
      var sel = i === state.avatar;
      var d = document.createElement("div");
      d.style.cssText = "aspect-ratio:1;border-radius:18px;background:rgba(255,255,255,0.92);display:flex;align-items:center;justify-content:center;cursor:pointer;"
        + (sel ? "box-shadow:0 0 0 3px #FFD23F, 0 4px 10px rgba(0,0,0,0.2);" : "");
      d.innerHTML = faceSvg(i, 38);
      (function (idx) { d.addEventListener("click", function () { state.avatar = idx; renderChars(); renderAvatar(); sendProfile(); }); })(i);
      box.appendChild(d);
    }
  }
  function renderColors() {
    var box = el("setup-colors"); box.innerHTML = "";
    COLORS.forEach(function (c) {
      var sel = c === state.color;
      var d = document.createElement("div");
      d.style.cssText = "flex:1;aspect-ratio:1;border-radius:50%;cursor:pointer;background:" + c + ";"
        + (sel ? "box-shadow:0 0 0 3px #fff, 0 0 0 6px rgba(255,255,255,0.25);" : "");
      d.addEventListener("click", function () { state.color = c; renderColors(); renderAvatar(); sendProfile(); });
      box.appendChild(d);
    });
  }
  function readCode() {
    return (["code0", "code1", "code2", "code3"].map(function (id) { return (el(id).value || "").toUpperCase(); }).join("")).replace(/[^A-Z0-9]/g, "");
  }
  function randomCode() {
    var a = "ABCDEFGHJKLMNPQRSTUVWXYZ", s = "";
    for (var i = 0; i < 4; i++) s += a.charAt(Math.floor(Math.random() * a.length));
    return s;
  }
  function onSetupConfirm() {
    var nm = (el("setup-name").value || "").trim() || "Player";
    state.name = nm;
    if (state.role === "host") {
      state.code = randomCode();
      state.hostName = nm;
      state.players = [{ name: nm, color: state.color, isHost: true, you: true }];
      send({ t: "createRoom", name: nm, avatar: state.avatar, color: state.color });
      go("lobby");
    } else {
      var code = readCode();
      if (code.length < 4) { toast("Enter the 4-character room code"); return; }
      state.code = code;
      state.players = [{ name: state.hostName || "Host", isHost: true, color: "#FFD23F" }, { name: nm, color: state.color, you: true }];
      send({ t: "join", code: code, name: nm, avatar: state.avatar, color: state.color });
      go("lobby");
    }
  }

  // ---- lobby ----
  function avatarHtml(p, size, fs) {
    var bg = p.isHost ? "linear-gradient(150deg,#FFE27A,#FFB300)" : p.color;
    var lc = (p.isHost || p.color === "#FFD23F" || p.color === "#B6FF4B") ? "#3b0d73" : "#fff";
    var letter = esc((p.name || "?").charAt(0).toUpperCase());
    var star = p.isHost
      ? '<div style="position:absolute;top:-6px;right:-4px;width:22px;height:22px;border-radius:50%;background:#3b0d73;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 5px rgba(0,0,0,0.3);"><svg width="13" height="13" viewBox="0 0 24 24" fill="#FFD23F"><path d="M12 2l2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4z"/></svg></div>'
      : "";
    return '<div style="position:relative;width:' + size + 'px;height:' + size + 'px;"><div style="width:' + size + 'px;height:' + size + 'px;border-radius:50%;background:' + bg + ';display:flex;align-items:center;justify-content:center;color:' + lc + ';font-size:' + fs + 'px;font-weight:700;box-shadow:0 6px 14px rgba(0,0,0,0.25), inset 0 0 0 2px rgba(255,255,255,0.28);">' + letter + "</div>" + star + "</div>";
  }
  function renderLobby() {
    var host = state.role === "host";
    el("lobby-host").style.display = host ? "flex" : "none";
    el("lobby-player").style.display = host ? "none" : "flex";
    el("lobby-title").textContent = host ? "Game Lobby" : "Lobby";
    el("lobby-code").textContent = state.code || "----";
    el("lobby-code2").textContent = state.code || "----";
    el("lobby-hostname").textContent = state.hostName || "Host";
    renderPlayers();
  }
  function renderPlayers() {
    var maxP = state.isPremium ? 8 : 2;
    el("lobby-count").textContent = state.players.length + " / " + maxP + " joined";

    var html = "";
    state.players.forEach(function (p) {
      html += '<div style="display:flex;flex-direction:column;align-items:center;gap:7px;">' + avatarHtml(p, 60, 24)
        + '<div style="text-align:center;line-height:1.1;"><div style="font-size:13px;font-weight:600;color:#fff;">' + esc(p.name) + "</div>"
        + '<div style="font-size:10.5px;font-weight:600;color:' + (p.isHost ? "#FFD23F" : "#B6FF4B") + ';letter-spacing:0.5px;">' + (p.isHost ? "HOST" : "Connected") + "</div></div></div>";
    });
    var locked = Math.max(0, 6 - state.players.length);
    for (var i = 0; i < locked; i++) {
      html += '<div style="display:flex;flex-direction:column;align-items:center;gap:7px;"><div style="width:60px;height:60px;border-radius:50%;background:rgba(255,255,255,0.05);border:1.5px dashed rgba(255,255,255,0.22);display:flex;align-items:center;justify-content:center;"><svg width="20" height="20" viewBox="0 0 22 22" fill="none"><rect x="4.5" y="9.5" width="13" height="9" rx="2" stroke="rgba(255,255,255,0.4)" stroke-width="1.8"/><path d="M7 9.5V7a4 4 0 0 1 8 0v2.5" stroke="rgba(255,255,255,0.4)" stroke-width="1.8" stroke-linecap="round"/></svg></div><div style="font-size:11px;font-weight:500;color:rgba(255,255,255,0.4);">Premium</div></div>';
    }
    el("lobby-players").innerHTML = html;

    var room = "";
    state.players.forEach(function (p) {
      var role = p.isHost ? "HOST" : (p.you ? "YOU" : "");
      room += '<div style="display:flex;flex-direction:column;align-items:center;gap:7px;">' + avatarHtml(p, 58, 23)
        + '<div style="text-align:center;line-height:1.1;"><div style="font-size:13px;font-weight:600;color:#fff;">' + esc(p.name) + "</div>"
        + (role ? '<div style="font-size:10.5px;font-weight:600;color:' + (p.isHost ? "#FFD23F" : "#B6FF4B") + ';">' + role + "</div>" : "") + "</div></div>";
    });
    el("lobby-player-room").innerHTML = room;
  }

  // ---- pick games ----
  var SEL_BADGE = "width:38px;height:38px;border-radius:50%;background:#FFD23F;display:flex;align-items:center;justify-content:center;color:#3b0d73;font-size:19px;font-weight:700;box-shadow:0 3px 8px rgba(0,0,0,0.25);";
  var ADD_BADGE = "width:38px;height:38px;border-radius:50%;background:rgba(255,255,255,0.18);border:1.5px solid rgba(255,255,255,0.45);display:flex;align-items:center;justify-content:center;color:#fff;font-size:24px;font-weight:600;";
  var RING_ON = "0 14px 28px rgba(0,0,0,0.3), 0 0 0 3px #FFD23F";
  var RING_OFF = "0 14px 28px rgba(0,0,0,0.25)";
  var pickBuilt = false;

  function buildPickCards() {
    var car = el("pick-carousel"); car.innerHTML = "";
    GAMES.forEach(function (g) {
      var card = document.createElement("div");
      card.className = "card";
      card.setAttribute("data-key", g.key);
      if (g.locked) {
        card.setAttribute("data-locked", "1");
        card.style.cssText = "background:linear-gradient(160deg,#6b6480,#4a4458);box-shadow:0 14px 28px rgba(0,0,0,0.25);cursor:default;";
        card.innerHTML =
          '<div style="position:absolute;inset:0;background:rgba(20,16,30,0.4);"></div>'
          + '<div style="position:absolute;top:14px;right:14px;width:38px;height:38px;border-radius:50%;background:rgba(255,255,255,0.18);display:flex;align-items:center;justify-content:center;"><svg width="18" height="18" viewBox="0 0 22 22" fill="none"><rect x="4.5" y="9.5" width="13" height="9" rx="2" stroke="#fff" stroke-width="1.8"/><path d="M7 9.5V7a4 4 0 0 1 8 0v2.5" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg></div>'
          + '<div style="position:absolute;top:16px;left:16px;padding:5px 11px;border-radius:999px;background:rgba(255,210,63,0.9);color:#3b0d73;font-size:11px;font-weight:700;letter-spacing:0.5px;">PREMIUM</div>'
          + '<div style="height:244px;display:flex;align-items:center;justify-content:center;opacity:0.5;">' + g.svg + "</div>"
          + '<div style="position:absolute;bottom:0;left:0;right:0;padding:18px;"><div style="font-size:24px;font-weight:700;color:rgba(255,255,255,0.85);">' + g.name + '</div><div style="font-size:13px;font-weight:500;color:rgba(255,255,255,0.55);">' + g.sub + "</div></div>";
      } else {
        card.style.background = g.bg;
        card.innerHTML =
          '<div class="badge" style="position:absolute;top:14px;right:14px;z-index:3;"></div>'
          + '<div style="height:244px;display:flex;align-items:center;justify-content:center;">' + g.svg + "</div>"
          + '<div style="position:absolute;bottom:0;left:0;right:0;padding:18px;background:linear-gradient(transparent, rgba(0,0,0,0.4));"><div style="font-size:24px;font-weight:700;color:#fff;">' + g.name + '</div><div style="font-size:13px;font-weight:500;color:rgba(255,255,255,0.82);">' + g.sub + "</div></div>";
      }
      car.appendChild(card);
    });
    car.addEventListener("click", function (e) {
      var card = e.target.closest(".card"); if (!card) return;
      if (card.getAttribute("data-locked") === "1") { toast("Locked — unlock with Premium"); return; }
      togglePick(card.getAttribute("data-key"));
    });
    pickBuilt = true;
  }
  function shortFor(key) { for (var i = 0; i < GAMES.length; i++) if (GAMES[i].key === key) return GAMES[i].short || GAMES[i].name; return key; }
  function togglePick(key) {
    var idx = state.selected.indexOf(key);
    if (idx >= 0) state.selected.splice(idx, 1);
    else if (state.selected.length < 3) state.selected.push(key);
    else toast("Line-up is full — tap a game to remove one");
    renderPick(); send({ t: "pickUpdate", games: state.selected, mode: state.mode });
  }
  function renderPick() {
    if (!pickBuilt) buildPickCards();
    el("pick-counter").textContent = state.selected.length + " / 3";
    var cards = el("pick-carousel").querySelectorAll('.card[data-key]');
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i]; if (card.getAttribute("data-locked") === "1") continue;
      var key = card.getAttribute("data-key"), idx = state.selected.indexOf(key), badge = card.querySelector(".badge");
      if (idx >= 0) { badge.style.cssText = SEL_BADGE; badge.textContent = idx + 1; card.style.boxShadow = RING_ON; }
      else { badge.style.cssText = ADD_BADGE; badge.textContent = "+"; card.style.boxShadow = RING_OFF; }
    }
    var lu = el("pick-lineup"); lu.innerHTML = "";
    for (var s = 0; s < 3; s++) {
      var k = state.selected[s];
      var slot = document.createElement("div");
      slot.style.cssText = "flex:1;display:flex;align-items:center;gap:8px;padding:8px;border-radius:13px;background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255," + (k ? "0.16" : "0.22") + ");" + (k ? "" : "border-style:dashed;");
      slot.innerHTML = '<div style="width:24px;height:24px;border-radius:50%;background:' + (k ? "#FFD23F" : "rgba(255,255,255,0.18)") + ';color:' + (k ? "#3b0d73" : "rgba(255,255,255,0.7)") + ';font-size:13px;font-weight:700;display:flex;align-items:center;justify-content:center;flex:none;">' + (s + 1) + "</div>"
        + '<span style="font-size:13px;font-weight:600;color:' + (k ? "#fff" : "rgba(255,255,255,0.4)") + ';white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">' + (k ? esc(shortFor(k)) : "Empty") + "</span>";
      lu.appendChild(slot);
    }
    setMode(state.mode, true);
    var ok = state.selected.length === 3;
    el("pick-go").style.opacity = ok ? "1" : "0.5";
  }
  function setMode(mode, silent) {
    state.mode = mode;
    var active = "flex:1;display:flex;align-items:center;justify-content:center;gap:8px;height:50px;border:none;border-radius:12px;cursor:pointer;font-family:'Fredoka',sans-serif;background:#FFD23F;color:#3b0d73;box-shadow:0 3px 8px rgba(0,0,0,0.2);";
    var idle = "flex:1;display:flex;align-items:center;justify-content:center;gap:8px;height:50px;border:none;border-radius:12px;cursor:pointer;font-family:'Fredoka',sans-serif;background:transparent;color:rgba(255,255,255,0.7);";
    el("pick-mode-wins").style.cssText = mode === "wins" ? active : idle;
    el("pick-mode-final").style.cssText = mode === "final" ? active : idle;
    if (!silent) send({ t: "pickUpdate", games: state.selected, mode: state.mode });
  }

  // ---- live match controls ----
  function scoreForMe(d) {
    var ids = d.PlayerIds || [], scores = d.Scores || [];
    for (var i = 0; i < ids.length; i++) if (ids[i] === state.myId) return scores[i] || 0;
    return 0;
  }
  function onGame(d) {
    el("game-title").textContent = d.GameName || "Mini-game";
    el("game-round").textContent = "Round " + (d.Round || "-") + " / " + (d.TotalRounds || "-");
    el("game-prompt").textContent = d.Prompt || "Ready";
    el("game-time").textContent = "Time left: " + Number(d.TimeLeft || 0).toFixed(1) + "s";
    el("game-score").textContent = scoreForMe(d);
    var golf = d.MiniGameId === "mini_golf";
    el("game-golf-controls").style.display = golf ? "block" : "none";
    el("game-tap").style.display = golf ? "none" : "block";
    go("game");
  }
  function setBid(v) {
    state.bidAmount = Math.max(0, Math.min(state.bidMax, v));
    el("bid-amount").textContent = state.bidAmount;
  }
  function onBidding(d) {
    state.bidMax = d.YourCoins || 0;
    state.bidSubmitted = !!d.HasSubmitted;
    setBid(Math.min(state.bidAmount, state.bidMax));
    el("bid-time").textContent = "Time left: " + Number(d.TimeLeft || 0).toFixed(1) + "s";
    el("bid-coins").textContent = state.bidMax;
    el("bid-submit").textContent = state.bidSubmitted ? "Bid Submitted" : "Submit Bid";
    el("bid-submit").disabled = state.bidSubmitted;
    go("bid");
  }
  function onResults(d) {
    el("results-title").textContent = d.Final ? "Final Results" : "Results";
    var names = d.PlayerNames || [], placements = d.Placements || [], coins = d.CoinsCollected || [];
    var wins = d.Wins || [], totals = d.TotalCoins || [];
    var order = names.map(function (_, i) { return i; }).sort(function (a, b) { return (placements[a] || 999) - (placements[b] || 999); });
    el("results-list").innerHTML = order.map(function (i) {
      var extra = d.Final ? ("Wins " + (wins[i] || 0) + " / Coins " + (totals[i] || 0)) : ("+" + (coins[i] || 0) + " coins");
      return '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;"><div style="font-size:16px;font-weight:700;color:#fff;">#' + (placements[i] || "-") + " " + esc(names[i] || "Player") + '</div><div style="font-size:13px;font-weight:700;color:#FFD23F;">' + esc(extra) + "</div></div>";
    }).join("");
    go("results");
  }

  // ---- networking (optional; host wiring is Stage 2) ----
  function send(o) { try { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); } catch (e) {} }
  function sendProfile() { send({ t: "profile", name: state.name, avatar: state.avatar, color: state.color }); }
  function connect() {
    try {
      if (!location.host) return;
      ws = new WebSocket("ws://" + location.host + "/");
      ws.onmessage = function (e) {
        var m; try { m = JSON.parse(e.data); } catch (_) { return; }
        var d = m.d || {};
        if (m.t === "roomCreated") { state.code = d.code; if (state.screen === "lobby") renderLobby(); }
        else if (m.t === "lobby") {
          if (d.players) state.players = d.players;
          var me = (d.players || []).filter(function (p) { return p.you; })[0];
          if (me) state.myId = me.id;
          if (d.code) state.code = d.code;
          if (d.hostName) state.hostName = d.hostName;
          if (typeof d.premium === "boolean") state.isPremium = d.premium;
          if (state.screen === "lobby") renderLobby();
        } else if (m.t === "goPick" && state.role === "host") { go("pick"); }
        else if (m.t === "error") { toast(d.msg || "Error"); }
        else if (m.t === "game") { onGame(d); }
        else if (m.t === "bidding") { onBidding(d); }
        else if (m.t === "results") { onResults(d); }
      };
    } catch (e) { ws = null; }
  }

  // ---- wiring ----
  function wire() {
    el("home-host").addEventListener("click", function () { state.role = "host"; go("setup"); });
    el("home-join").addEventListener("click", function () { state.role = "player"; go("setup"); });
    el("home-premium").addEventListener("click", function () { toast("Premium coming soon"); });
    el("home-account").addEventListener("click", function () { toast("Playing as Guest"); });

    el("setup-back").addEventListener("click", function () { go("home"); });
    el("setup-confirm").addEventListener("click", onSetupConfirm);
    el("setup-name").addEventListener("input", function () { state.name = el("setup-name").value; });

    // room-code boxes: auto-advance
    ["code0", "code1", "code2", "code3"].forEach(function (id, i, arr) {
      var box = el(id);
      box.addEventListener("input", function () {
        box.value = (box.value || "").toUpperCase().slice(0, 1);
        if (box.value && i < arr.length - 1) el(arr[i + 1]).focus();
      });
      box.addEventListener("keydown", function (e) {
        if (e.key === "Backspace" && !box.value && i > 0) el(arr[i - 1]).focus();
      });
    });

    el("lobby-back").addEventListener("click", function () { send({ t: "leave" }); state.players = []; go("home"); });
    el("lobby-pick").addEventListener("click", function () { send({ t: "startPick" }); go("pick"); });
    el("lobby-share").addEventListener("click", function () {
      var txt = "Join my Mini Arcade room: " + (state.code || "");
      if (navigator.share) { navigator.share({ text: txt }).catch(function () {}); } else { toast("Room code: " + (state.code || "")); }
    });
    el("lobby-premium").addEventListener("click", function () { state.isPremium = true; renderPlayers(); toast("Premium unlocked (demo)"); });

    el("pick-back").addEventListener("click", function () { go("lobby"); });
    el("pick-mode-wins").addEventListener("click", function () { setMode("wins"); });
    el("pick-mode-final").addEventListener("click", function () { setMode("final"); });
    el("pick-go").addEventListener("click", function () {
      if (state.selected.length !== 3) { toast("Pick 3 games to start"); return; }
      send({ t: "pickStart", games: state.selected, mode: state.mode });
      toast("Starting…");
    });

    el("game-tap").addEventListener("touchstart", function (e) { e.preventDefault(); send({ t: "tap" }); }, { passive: false });
    el("game-tap").addEventListener("mousedown", function () { send({ t: "tap" }); });
    el("game-aim-left").addEventListener("click", function () { send({ t: "input", action: "aim_left" }); });
    el("game-aim-right").addEventListener("click", function () { send({ t: "input", action: "aim_right" }); });
    el("game-power-down").addEventListener("click", function () { send({ t: "input", action: "power_down" }); });
    el("game-power-up").addEventListener("click", function () { send({ t: "input", action: "power_up" }); });
    el("game-shoot").addEventListener("click", function () { send({ t: "input", action: "shoot" }); });
    el("bid-minus").addEventListener("click", function () { setBid(state.bidAmount - 10); });
    el("bid-plus").addEventListener("click", function () { setBid(state.bidAmount + 10); });
    el("bid-all").addEventListener("click", function () { setBid(state.bidMax); });
    el("bid-submit").addEventListener("click", function () {
      if (state.bidSubmitted) return;
      send({ t: "bid", amount: state.bidAmount });
      state.bidSubmitted = true;
      el("bid-submit").textContent = "Bid Submitted";
      el("bid-submit").disabled = true;
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    wire();
    connect();
    go("home");
  });
})();
