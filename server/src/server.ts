import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { networkInterfaces } from "node:os";
import { WebSocketServer, type WebSocket } from "ws";
import { parseClientMessage, type ServerMessage } from "./protocol.js";
import { Room, RoomManager } from "./room.js";

interface ConnState {
  room: Room | null;
  playerId: string | null;
}

export function lanAddresses(): string[] {
  const out: string[] = [];
  for (const ifaces of Object.values(networkInterfaces())) {
    for (const iface of ifaces ?? []) {
      if (iface.family === "IPv4" && !iface.internal) out.push(iface.address);
    }
  }
  return out;
}

export function startServer(port: number) {
  const manager = new RoomManager();

  const httpServer = createServer((req: IncomingMessage, res: ServerResponse) => {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, ...manager.stats }));
      return;
    }
    res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    res.end("Frantics game server is running. Point the iPhone app at this address. 🎉\n");
  });

  const wss = new WebSocketServer({ server: httpServer });

  wss.on("connection", (ws: WebSocket) => {
    const conn: ConnState = { room: null, playerId: null };

    const reply = (msg: ServerMessage) => ws.send(JSON.stringify(msg));
    const fail = (message: string) => reply({ t: "error", message });

    ws.on("message", (data) => {
      let parsed: unknown;
      try {
        parsed = JSON.parse(data.toString());
      } catch {
        return fail("Malformed JSON");
      }
      const msg = parseClientMessage(parsed);
      if (!msg) return fail("Missing message type");

      try {
        switch (msg.t) {
          case "create_room": {
            if (conn.room) return fail("Already in a room");
            const room = manager.create();
            const res = room.addPlayer({
              name: String(msg.name ?? ""),
              avatar: String(msg.avatar ?? ""),
              color: String(msg.color ?? ""),
              isHost: true,
              ws,
            });
            if (!res.ok) return fail(res.reason);
            conn.room = room;
            conn.playerId = res.player.id;
            reply({
              t: "room_joined",
              playerId: res.player.id,
              token: res.player.token,
              state: room.snapshot(),
            });
            console.log(`[room ${room.code}] created by ${res.player.name}`);
            break;
          }
          case "join_room": {
            if (conn.room) return fail("Already in a room");
            const room = manager.get(String(msg.code ?? ""));
            if (!room) return fail("Room not found — check the code");
            const res = room.addPlayer({
              name: String(msg.name ?? ""),
              avatar: String(msg.avatar ?? ""),
              color: String(msg.color ?? ""),
              isHost: false,
              ws,
            });
            if (!res.ok) return fail(res.reason);
            conn.room = room;
            conn.playerId = res.player.id;
            reply({
              t: "room_joined",
              playerId: res.player.id,
              token: res.player.token,
              state: room.snapshot(),
            });
            console.log(`[room ${room.code}] ${res.player.name} joined`);
            break;
          }
          case "rejoin": {
            const room = manager.get(String(msg.code ?? ""));
            if (!room) return fail("Room not found");
            const player = room.rejoin(String(msg.playerId), String(msg.token), ws);
            if (!player) return fail("Could not rejoin — seat not found");
            conn.room = room;
            conn.playerId = player.id;
            reply({
              t: "room_joined",
              playerId: player.id,
              token: player.token,
              state: room.snapshot(),
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
    });

    ws.on("close", () => {
      if (conn.room && conn.playerId) conn.room.handleDisconnect(conn.playerId, ws);
    });
  });

  httpServer.listen(port, () => {
    console.log("");
    console.log("  🎉 Frantics server is up");
    console.log(`     local:   ws://localhost:${port}`);
    for (const addr of lanAddresses()) {
      console.log(`     LAN:     ws://${addr}:${port}   ← put this in the iPhone app on the same WiFi`);
    }
    console.log("");
  });

  return {
    httpServer,
    wss,
    manager,
    close() {
      wss.close();
      httpServer.close();
    },
  };
}
