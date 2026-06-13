// On-device game host. Bundled to a single JS file and run inside the iOS
// host phone's JavaScriptCore engine, so the HOST PARTY phone runs the *exact*
// same authoritative game logic as the Node server — no second implementation.
//
// The native side (Swift) owns the real WebSocket server + Bonjour advertising.
// It injects two globals and drives this engine:
//   __frantics_send(connId, text)  — write a text frame to that connection
//   __frantics_close(connId)       — close that connection
// and calls FranticsEngine.open / .message / .close as connections come and go.
import { parseClientMessage } from "./protocol.js";
import { RoomManager } from "./room.js";
import { handleClientMessage, type ConnState } from "./dispatch.js";

declare const __frantics_send: (connId: string, text: string) => void;
declare const __frantics_close: (connId: string) => void;

/** Socket shim: a per-connection object the room state machine writes to. */
class NativeSocket {
  readonly OPEN = 1;
  readyState = 1;
  constructor(private readonly connId: string) {}
  send(text: string): void {
    if (this.readyState === this.OPEN) __frantics_send(this.connId, text);
  }
  close(): void {
    if (this.readyState !== 3) {
      this.readyState = 3;
      __frantics_close(this.connId);
    }
  }
}

const manager = new RoomManager();
const conns = new Map<string, { conn: ConnState; ws: NativeSocket }>();

const FranticsEngine = {
  /** A new WebSocket connection opened. */
  open(connId: string): void {
    conns.set(connId, { conn: { room: null, playerId: null }, ws: new NativeSocket(connId) });
  },

  /** A text frame arrived on a connection. */
  message(connId: string, text: string): void {
    const entry = conns.get(connId);
    if (!entry) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return entry.ws.send(JSON.stringify({ t: "error", message: "Malformed JSON" }));
    }
    const msg = parseClientMessage(parsed);
    if (!msg) return entry.ws.send(JSON.stringify({ t: "error", message: "Missing message type" }));
    handleClientMessage(manager, entry.conn, entry.ws, msg);
  },

  /** A connection closed (or dropped). Free the seat's socket. */
  close(connId: string): void {
    const entry = conns.get(connId);
    if (!entry) return;
    const { conn, ws } = entry;
    ws.readyState = 3;
    if (conn.room && conn.playerId) conn.room.handleDisconnect(conn.playerId, ws);
    conns.delete(connId);
  },
};

// Expose to the native host. (Also assigned to a bare name for IIFE bundling.)
(globalThis as unknown as { FranticsEngine: typeof FranticsEngine }).FranticsEngine = FranticsEngine;
