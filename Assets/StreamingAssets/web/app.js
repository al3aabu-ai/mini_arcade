/* Mini Arcade — phone controller. Screens are verbatim from the Game UI design;
   this only adds navigation, selection state (using the design's exact styles),
   and the WebSocket link to the Unity host. */
(function () {
  "use strict";
  var el = function (id) { return document.getElementById(id); };
  function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){return ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c];}); }
  function toast(m){ var t=el("toast"); t.textContent=m; t.classList.add("show"); clearTimeout(toast._t); toast._t=setTimeout(function(){t.classList.remove("show");},1700); }

  // Face inner-SVGs, verbatim from the design (index 0..7).
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
  // Verbatim "taken" tiles from the Join design (slots 7 & 8).
  var TAKEN = [
    '<div style="position: relative; aspect-ratio: 1; border-radius: 18px; background: rgba(255,255,255,0.22); display: flex; align-items: center; justify-content: center; opacity: 0.6;"><svg width="38" height="38" viewBox="0 0 48 48" fill="none"><path d="M14 21l4-4 4 4" stroke="rgba(255,255,255,0.7)" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M26 21l4-4 4 4" stroke="rgba(255,255,255,0.7)" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M16 29q8 7 16 0" stroke="rgba(255,255,255,0.7)" stroke-width="3" fill="none" stroke-linecap="round"/></svg><div style="position: absolute; bottom: 4px; right: 4px; width: 20px; height: 20px; border-radius: 50%; background: linear-gradient(150deg, #FFE27A, #FFB300); display: flex; align-items: center; justify-content: center; color: #3b0d73; font-size: 11px; font-weight: 700; box-shadow: 0 2px 4px rgba(0,0,0,0.3);">G</div></div>',
    '<div style="position: relative; aspect-ratio: 1; border-radius: 18px; background: rgba(255,255,255,0.22); display: flex; align-items: center; justify-content: center; opacity: 0.6;"><svg width="38" height="38" viewBox="0 0 48 48" fill="none"><circle cx="18" cy="19" r="3" fill="rgba(255,255,255,0.7)"/><circle cx="30" cy="19" r="3" fill="rgba(255,255,255,0.7)"/><path d="M16 28q8 7 16 0" stroke="rgba(255,255,255,0.7)" stroke-width="3" fill="none" stroke-linecap="round"/></svg><div style="position: absolute; bottom: 4px; right: 4px; width: 20px; height: 20px; border-radius: 50%; background: linear-gradient(150deg, #38E1FF, #0e9fc4); display: flex; align-items: center; justify-content: center; color: #fff; font-size: 11px; font-weight: 700; box-shadow: 0 2px 4px rgba(0,0,0,0.3);">L</div></div>'
  ];
  var GRAD = {
    "#FF5DA2": "linear-gradient(150deg,#FF7DB6,#FF5DA2)", "#FFD23F": "linear-gradient(150deg,#FFE27A,#FFB300)",
    "#38E1FF": "linear-gradient(150deg,#7DECFF,#0e9fc4)", "#B6FF4B": "linear-gradient(150deg,#D0FF85,#4fbf2e)",
    "#fb923c": "linear-gradient(150deg,#FFB877,#ea580c)", "#a855f7": "linear-gradient(150deg,#C18BFF,#7e22ce)"
  };
  var JOIN_COLORS = ["#FF5DA2","#FFD23F","#38E1FF","#B6FF4B","#fb923c","#a855f7"];
  var HOST_COLORS = ["#FFD23F","#FF5DA2","#38E1FF","#B6FF4B","#fb923c","#a855f7"];

  // Pick cards, verbatim from the Pick Games design.
  var GAMES = [
    { key:"golf", name:"Mini Golf", short:"Golf", sub:"Precision · sink the trickiest shots", bg:"linear-gradient(160deg, #34d399, #059669)",
      svg:'<svg width="110" height="120" viewBox="0 0 76 84" fill="none"><ellipse cx="38" cy="68" rx="30" ry="8" fill="rgba(0,0,0,0.18)"/><rect x="36" y="10" width="4.5" height="54" rx="2" fill="#fff"/><path d="M40 12h22l-7 8 7 8H40z" fill="#FF5DA2"/><circle cx="20" cy="64" r="8" fill="#fff"/></svg>' },
    { key:"sumo", name:"Sumo Smash", short:"Sumo", sub:"Brawl · shove rivals off the ring", bg:"linear-gradient(160deg, #fb923c, #ea580c)",
      svg:'<svg width="130" height="96" viewBox="0 0 96 70" fill="none"><circle cx="34" cy="40" r="24" fill="#3b0d73"/><circle cx="64" cy="40" r="24" fill="#fff"/><circle cx="27" cy="35" r="3.5" fill="#fff"/><circle cx="71" cy="35" r="3.5" fill="#3b0d73"/></svg>' },
    { key:"bomb", name:"Hot Bomb", short:"Bomb", sub:"Chaos · don't be holding it at zero", bg:"linear-gradient(160deg, #f472b6, #db2777)",
      svg:'<svg width="112" height="120" viewBox="0 0 78 84" fill="none"><circle cx="34" cy="50" r="24" fill="#1a1a22"/><rect x="40" y="20" width="8" height="14" rx="3" fill="#1a1a22"/><path d="M46 22c8-4 6-12 12-14" stroke="#1a1a22" stroke-width="3.5" fill="none" stroke-linecap="round"/><circle cx="61" cy="7" r="6" fill="#FFD23F"/><circle cx="26" cy="44" r="6" fill="rgba(255,255,255,0.28)"/></svg>' },
    { key:"kart", name:"Kart Dash", sub:"Racing · unlock with Premium", locked:true,
      svg:'<svg width="120" height="90" viewBox="0 0 120 90" fill="none"><circle cx="32" cy="62" r="16" fill="#1a1a22"/><circle cx="88" cy="62" r="16" fill="#1a1a22"/><rect x="24" y="32" width="72" height="22" rx="8" fill="#fff"/></svg>' },
    { key:"sky", name:"Sky Hop", sub:"Platformer · unlock with Premium", locked:true,
      svg:'<svg width="100" height="100" viewBox="0 0 100 100" fill="none"><rect x="20" y="64" width="60" height="14" rx="4" fill="#fff"/><path d="M50 20l16 28H34z" fill="#fff"/></svg>' }
  ];

  var state = { role:"player", name:"Player", avatar:0, color:"#FF5DA2", code:"", hostName:"Guest",
    isPremium:false, players:[], selected:["golf","sumo","bomb"], mode:"wins" };
  var ws = null, pickBuilt = false;

  function go(name){
    var list = document.querySelectorAll(".screen");
    for (var i=0;i<list.length;i++) list[i].classList.remove("active");
    var s = el("screen-"+name); if (s) s.classList.add("active");
  }

  // ---------- setup (join / host) ----------
  function setAvatar(prefix){ var a=el(prefix+"-avatar"); if(!a) return; a.style.background=GRAD[state.color]||state.color; a.innerHTML='<svg width="58" height="58" viewBox="0 0 48 48" fill="#3b0d73">'+FACES[state.avatar]+'</svg>'; }
  function renderChars(prefix, joinTaken){
    var box=el(prefix+"-chars"); if(!box) return; var html="";
    for (var i=0;i<FACES.length;i++){
      if (joinTaken && i>=6){ html += TAKEN[i-6]; continue; }
      var selSh = (i===state.avatar) ? "box-shadow:0 0 0 3px #FFD23F, 0 4px 10px rgba(0,0,0,0.2);" : "";
      html += '<div data-idx="'+i+'" style="aspect-ratio:1;border-radius:18px;background:rgba(255,255,255,0.92);display:flex;align-items:center;justify-content:center;cursor:pointer;'+selSh+'"><svg width="38" height="38" viewBox="0 0 48 48" fill="#3b0d73">'+FACES[i]+'</svg></div>';
    }
    box.innerHTML=html;
    Array.prototype.forEach.call(box.querySelectorAll('[data-idx]'), function(tile){
      tile.addEventListener("click", function(){ state.avatar=parseInt(tile.getAttribute("data-idx"),10); renderChars(prefix,joinTaken); setAvatar(prefix); sendProfile(); });
    });
  }
  function renderColors(prefix, colors){
    var box=el(prefix+"-colors"); if(!box) return; var html="";
    colors.forEach(function(c){
      var selSh=(c===state.color)?"box-shadow:0 0 0 3px #fff, 0 0 0 6px rgba(255,255,255,0.25);":"";
      html += '<div data-col="'+c+'" style="flex:1;aspect-ratio:1;border-radius:50%;background:'+c+';cursor:pointer;'+selSh+'"></div>';
    });
    box.innerHTML=html;
    Array.prototype.forEach.call(box.querySelectorAll('[data-col]'), function(sw){
      sw.addEventListener("click", function(){ state.color=sw.getAttribute("data-col"); renderColors(prefix,colors); setAvatar(prefix); sendProfile(); });
    });
  }

  // ---------- lobby ----------
  function avatarHtml(p,size,fs){
    var bg = p.isHost ? "linear-gradient(150deg,#FFE27A,#FFB300)" : (GRAD[p.color]||p.color||"#FF5DA2");
    var lc = (p.isHost||p.color==="#FFD23F"||p.color==="#B6FF4B")?"#3b0d73":"#fff";
    var letter = esc((p.name||"?").charAt(0).toUpperCase());
    var star = p.isHost ? '<div style="position:absolute;top:-6px;right:-4px;width:22px;height:22px;border-radius:50%;background:#3b0d73;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 5px rgba(0,0,0,0.3);"><svg width="13" height="13" viewBox="0 0 24 24" fill="#FFD23F"><path d="M12 2l2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4z"/></svg></div>' : "";
    return '<div style="position:relative;width:'+size+'px;height:'+size+'px;"><div style="width:'+size+'px;height:'+size+'px;border-radius:50%;background:'+bg+';display:flex;align-items:center;justify-content:center;color:'+lc+';font-size:'+fs+'px;font-weight:700;box-shadow:0 6px 14px rgba(0,0,0,0.25), inset 0 0 0 2px rgba(255,255,255,0.28);">'+letter+'</div>'+star+'</div>';
  }
  function lockSlot(){
    return '<div style="display:flex;flex-direction:column;align-items:center;gap:7px;"><div style="width:60px;height:60px;border-radius:50%;background:rgba(255,255,255,0.05);border:1.5px dashed rgba(255,255,255,0.22);display:flex;align-items:center;justify-content:center;"><svg width="20" height="20" viewBox="0 0 22 22" fill="none"><rect x="4.5" y="9.5" width="13" height="9" rx="2" stroke="rgba(255,255,255,0.4)" stroke-width="1.8"/><path d="M7 9.5V7a4 4 0 0 1 8 0v2.5" stroke="rgba(255,255,255,0.4)" stroke-width="1.8" stroke-linecap="round"/></svg></div><div style="font-size:11px;font-weight:500;color:rgba(255,255,255,0.4);">Premium</div></div>';
  }
  function renderLobbyHost(){
    el("lh-code").textContent = state.code || "----";
    var maxP = state.isPremium ? 8 : 2;
    el("lh-count").textContent = state.players.length + " / " + maxP + " joined";
    var html="";
    state.players.forEach(function(p){
      html += '<div style="display:flex;flex-direction:column;align-items:center;gap:7px;">'+avatarHtml(p,60,24)+
        '<div style="text-align:center;line-height:1.1;"><div style="font-size:13px;font-weight:600;color:#fff;">'+esc(p.name)+'</div>'+
        '<div style="font-size:10.5px;font-weight:600;color:'+(p.isHost?"#FFD23F":"#B6FF4B")+';letter-spacing:0.5px;">'+(p.isHost?"HOST":"Connected")+'</div></div></div>';
    });
    for (var i=Math.max(0,6-state.players.length); i>0; i--) html += lockSlot();
    el("lh-players").innerHTML = html;
  }
  function renderLobbyPlayer(){
    el("lp-host").textContent = state.hostName || "Host";
    el("lp-code").textContent = state.code || "----";
    var html="";
    state.players.forEach(function(p){
      var role = p.isHost ? "HOST" : (p.you ? "YOU" : "");
      html += '<div style="display:flex;flex-direction:column;align-items:center;gap:7px;">'+avatarHtml(p,58,23)+
        '<div style="text-align:center;line-height:1.1;"><div style="font-size:13px;font-weight:600;color:#fff;">'+esc(p.name)+'</div>'+
        (role?'<div style="font-size:10.5px;font-weight:600;color:'+(p.isHost?"#FFD23F":"#B6FF4B")+';">'+role+'</div>':'')+'</div></div>';
    });
    el("lp-room").innerHTML = html;
  }

  // ---------- pick ----------
  var SEL_BADGE="width:38px;height:38px;border-radius:50%;background:#FFD23F;display:flex;align-items:center;justify-content:center;color:#3b0d73;font-size:19px;font-weight:700;box-shadow:0 3px 8px rgba(0,0,0,0.25);";
  var ADD_BADGE="width:38px;height:38px;border-radius:50%;background:rgba(255,255,255,0.18);border:1.5px solid rgba(255,255,255,0.45);display:flex;align-items:center;justify-content:center;color:#fff;font-size:24px;font-weight:600;";
  function buildPick(){
    var car=el("pk-carousel"); car.innerHTML="";
    GAMES.forEach(function(g){
      var c=document.createElement("div");
      c.setAttribute("data-key",g.key);
      c.style.cssText="flex:none;width:252px;height:328px;border-radius:24px;overflow:hidden;position:relative;scroll-snap-align:center;";
      if (g.locked){
        c.setAttribute("data-locked","1");
        c.style.background="linear-gradient(160deg, #6b6480, #4a4458)"; c.style.boxShadow="0 14px 28px rgba(0,0,0,0.25)";
        c.innerHTML='<div style="position:absolute;inset:0;background:rgba(20,16,30,0.4);"></div><div style="position:absolute;top:14px;right:14px;width:38px;height:38px;border-radius:50%;background:rgba(255,255,255,0.18);display:flex;align-items:center;justify-content:center;"><svg width="18" height="18" viewBox="0 0 22 22" fill="none"><rect x="4.5" y="9.5" width="13" height="9" rx="2" stroke="#fff" stroke-width="1.8"/><path d="M7 9.5V7a4 4 0 0 1 8 0v2.5" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg></div><div style="position:absolute;top:16px;left:16px;padding:5px 11px;border-radius:999px;background:rgba(255,210,63,0.9);color:#3b0d73;font-size:11px;font-weight:700;letter-spacing:0.5px;">PREMIUM</div><div style="height:244px;display:flex;align-items:center;justify-content:center;opacity:0.5;">'+g.svg+'</div><div style="position:absolute;bottom:0;left:0;right:0;padding:18px;"><div style="font-size:24px;font-weight:700;color:rgba(255,255,255,0.85);">'+g.name+'</div><div style="font-size:13px;font-weight:500;color:rgba(255,255,255,0.55);">'+g.sub+'</div></div>';
      } else {
        c.style.background=g.bg;
        c.innerHTML='<div class="badge" style="position:absolute;top:14px;right:14px;z-index:3;"></div><div style="height:244px;display:flex;align-items:center;justify-content:center;">'+g.svg+'</div><div style="position:absolute;bottom:0;left:0;right:0;padding:18px;background:linear-gradient(transparent, rgba(0,0,0,0.4));"><div style="font-size:24px;font-weight:700;color:#fff;">'+g.name+'</div><div style="font-size:13px;font-weight:500;color:rgba(255,255,255,0.82);">'+g.sub+'</div></div>';
      }
      car.appendChild(c);
    });
    car.addEventListener("click", function(e){ var card=e.target.closest('[data-key]'); if(!card) return; if(card.getAttribute("data-locked")==="1"){ toast("Locked — unlock with Premium"); return; } togglePick(card.getAttribute("data-key")); });
    pickBuilt=true;
  }
  function shortFor(k){ for(var i=0;i<GAMES.length;i++) if(GAMES[i].key===k) return GAMES[i].short||GAMES[i].name; return k; }
  function togglePick(k){ var i=state.selected.indexOf(k); if(i>=0) state.selected.splice(i,1); else if(state.selected.length<3) state.selected.push(k); else toast("Line-up is full — tap a game to remove one"); renderPick(); send({t:"pickUpdate",games:state.selected,mode:state.mode}); }
  function renderPick(){
    if(!pickBuilt) buildPick();
    el("pk-counter").textContent = state.selected.length + " / 3";
    Array.prototype.forEach.call(el("pk-carousel").querySelectorAll('[data-key]'), function(card){
      if(card.getAttribute("data-locked")==="1") return;
      var k=card.getAttribute("data-key"), idx=state.selected.indexOf(k), b=card.querySelector(".badge");
      if(idx>=0){ b.style.cssText=SEL_BADGE; b.textContent=idx+1; card.style.boxShadow="0 14px 28px rgba(0,0,0,0.3), 0 0 0 3px #FFD23F"; }
      else { b.style.cssText=ADD_BADGE; b.textContent="+"; card.style.boxShadow="0 14px 28px rgba(0,0,0,0.25)"; }
    });
    var lu=el("pk-lineup"); lu.innerHTML="";
    for (var s=0;s<3;s++){ var k=state.selected[s];
      lu.innerHTML += '<div style="flex:1;display:flex;align-items:center;gap:8px;padding:8px;border-radius:13px;background:rgba(255,255,255,0.1);border:1px '+(k?"solid":"dashed")+' rgba(255,255,255,'+(k?"0.16":"0.22")+');"><div style="width:24px;height:24px;border-radius:50%;background:'+(k?"#FFD23F":"rgba(255,255,255,0.18)")+';color:'+(k?"#3b0d73":"rgba(255,255,255,0.7)")+';font-size:13px;font-weight:700;display:flex;align-items:center;justify-content:center;flex:none;">'+(s+1)+'</div><span style="font-size:13px;font-weight:600;color:'+(k?"#fff":"rgba(255,255,255,0.4)")+';white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">'+(k?esc(shortFor(k)):"Empty")+'</span></div>';
    }
    el("pk-go").style.opacity = state.selected.length===3 ? "1" : "0.5";
  }
  function setMode(m){
    state.mode=m;
    var active="flex:1;display:flex;align-items:center;justify-content:center;gap:8px;height:50px;border:none;border-radius:12px;font-family:'Fredoka',sans-serif;cursor:pointer;background:#FFD23F;color:#3b0d73;box-shadow:0 3px 8px rgba(0,0,0,0.2);";
    var idle="flex:1;display:flex;align-items:center;justify-content:center;gap:8px;height:50px;border:none;border-radius:12px;font-family:'Fredoka',sans-serif;cursor:pointer;background:transparent;color:rgba(255,255,255,0.7);";
    el("pk-mode-wins").style.cssText = m==="wins"?active:idle;
    el("pk-mode-final").style.cssText = m==="final"?active:idle;
    send({t:"pickUpdate",games:state.selected,mode:state.mode});
  }

  // ---------- room code inputs ----------
  function wireCode(prefix){
    var ids=[prefix+"-code0",prefix+"-code1",prefix+"-code2",prefix+"-code3"];
    ids.forEach(function(id,i){ var b=el(id); if(!b) return;
      b.addEventListener("input", function(){ b.value=(b.value||"").toUpperCase().slice(0,1); if(b.value && i<ids.length-1) el(ids[i+1]).focus(); });
      b.addEventListener("keydown", function(e){ if(e.key==="Backspace" && !b.value && i>0) el(ids[i-1]).focus(); });
    });
  }
  function readCode(prefix){ return [0,1,2,3].map(function(i){ return (el(prefix+"-code"+i).value||"").toUpperCase(); }).join("").replace(/[^A-Z0-9]/g,""); }
  function randomCode(){ var a="ABCDEFGHJKLMNPQRSTUVWXYZ",s=""; for(var i=0;i<4;i++) s+=a.charAt(Math.floor(Math.random()*a.length)); return s; }

  // ---------- networking (matches the Unity host protocol) ----------
  function send(o){ try{ if(ws&&ws.readyState===1) ws.send(JSON.stringify(o)); }catch(e){} }
  function sendProfile(){ send({t:"profile",name:state.name,avatar:state.avatar,color:state.color}); }
  function connect(){
    try{ if(!location.host) return; ws=new WebSocket("ws://"+location.host+"/");
      ws.onmessage=function(e){ var m; try{m=JSON.parse(e.data);}catch(_){return;} var d=m.d||{};
        if(m.t==="roomCreated"){ state.code=d.code; el("lh-code").textContent=d.code; }
        else if(m.t==="lobby"){ if(d.players) state.players=d.players; if(d.code) state.code=d.code; if(d.hostName) state.hostName=d.hostName; if(typeof d.premium==="boolean") state.isPremium=d.premium; if(el("screen-lobby-host").classList.contains("active")) renderLobbyHost(); if(el("screen-lobby-player").classList.contains("active")) renderLobbyPlayer(); }
        else if(m.t==="goPick" && state.role==="host"){ go("pick"); renderPick(); }
        else if(m.t==="error"){ toast(d.msg||"Error"); }
      };
    }catch(e){ ws=null; }
  }

  // ---------- wiring ----------
  function wire(){
    el("ho-host").addEventListener("click", function(){ state.role="host"; state.color="#FFD23F"; state.avatar=0; go("host"); el("hs-name").value=state.name==="Player"?"Sam":state.name; renderChars("hs",false); renderColors("hs",HOST_COLORS); setAvatar("hs"); });
    el("ho-join").addEventListener("click", function(){ state.role="player"; state.color="#FF5DA2"; state.avatar=0; go("join"); el("jn-name").value=state.name==="Player"?"Maya":state.name; renderChars("jn",true); renderColors("jn",JOIN_COLORS); setAvatar("jn"); });
    el("ho-account").addEventListener("click", function(){ go("login"); });
    el("ho-premium").addEventListener("click", function(){ toast("Premium coming soon"); });

    el("lg-guest").addEventListener("click", function(){ go("home"); });
    el("lg-login").addEventListener("click", function(){ toast("Login is for restoring Premium"); });
    el("lg-apple").addEventListener("click", function(){ toast("Sign in with Apple — soon"); });

    el("jn-back").addEventListener("click", function(){ go("home"); });
    el("hs-back").addEventListener("click", function(){ go("home"); });
    el("jn-name").addEventListener("input", function(){ state.name=el("jn-name").value; });
    el("hs-name").addEventListener("input", function(){ state.name=el("hs-name").value; });
    wireCode("jn");

    el("hs-confirm").addEventListener("click", function(){
      state.name=(el("hs-name").value||"").trim()||"Host"; state.code=randomCode(); state.hostName=state.name;
      state.players=[{name:state.name,color:state.color,isHost:true,you:true}];
      send({t:"createRoom",name:state.name,avatar:state.avatar,color:state.color});
      go("lobby-host"); renderLobbyHost();
    });
    el("jn-confirm").addEventListener("click", function(){
      var code=readCode("jn"); if(code.length<4){ toast("Enter the 4-character room code"); return; }
      state.name=(el("jn-name").value||"").trim()||"Player"; state.code=code;
      state.players=[{name:state.hostName||"Host",isHost:true,color:"#FFD23F"},{name:state.name,color:state.color,you:true}];
      send({t:"join",code:code,name:state.name,avatar:state.avatar,color:state.color});
      go("lobby-player"); renderLobbyPlayer();
    });

    el("lh-leave").addEventListener("click", function(){ send({t:"leave"}); state.players=[]; go("home"); });
    el("lp-leave").addEventListener("click", function(){ send({t:"leave"}); state.players=[]; go("home"); });
    el("lh-pick").addEventListener("click", function(){ send({t:"startPick"}); go("pick"); renderPick(); });
    el("lh-premium").addEventListener("click", function(){ state.isPremium=true; renderLobbyHost(); toast("Premium unlocked (demo)"); });
    el("lh-share").addEventListener("click", function(){ var t="Join my Mini Arcade room: "+(state.code||""); if(navigator.share){ navigator.share({text:t}).catch(function(){}); } else toast("Room code: "+(state.code||"")); });

    el("pk-back").addEventListener("click", function(){ go("lobby-host"); });
    el("pk-mode-wins").addEventListener("click", function(){ setMode("wins"); });
    el("pk-mode-final").addEventListener("click", function(){ setMode("final"); });
    el("pk-go").addEventListener("click", function(){ if(state.selected.length!==3){ toast("Pick 3 games to start"); return; } send({t:"pickStart",games:state.selected,mode:state.mode}); toast("Starting…"); });
  }

  document.addEventListener("DOMContentLoaded", function(){ wire(); connect(); go("home"); });
})();
