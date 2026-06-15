// Per-connection message routing, shared by the Node server (server.ts) and the
// iOS on-device host engine (embedded.ts) so both speak the exact same protocol.
import type { ClientMessage, ServerMessage, Socket } from "./protocol.js";
import type { Room, RoomManager } from "./room.js";

export interface ConnState {
  room: Room | null;
  playerId: string | null;
}

/**
 * Route one already-parsed client message for a connection. `ws` is the socket
 * the reply/snapshots go to; `conn` carries the seat this socket is bound to and
 * is mutated as the player joins/leaves.
 */
export function handleClientMessage(
  manager: RoomManager,
  conn: ConnState,
  ws: Socket,
  msg: ClientMessage,
): void {
  const reply = (m: ServerMessage) => ws.send(JSON.stringify(m));
  const fail = (message: string) => reply({ t: "error", message });

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
          state: room.snapshotFor(res.player.id),
        });
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
          state: room.snapshotFor(res.player.id),
        });
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
          state: room.snapshotFor(player.id),
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
            room.previewLineup(playerId, msg.lineup); // sanitized server-side
            break;
          case "select_lineup":
            room.selectLineup(playerId, msg.lineup); // sanitized + validated server-side
            break;
          case "register_coins":
            room.registerCoins(playerId, msg.coins); // sanitized server-side
            break;
          case "collect_coin":
            room.collectCoin(playerId, String(msg.coinId), String(msg.playerId));
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
              Array.isArray(msg.sunk) ? msg.sunk.map(String) : [],
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
