import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { hostname, networkInterfaces } from "node:os";
import { Bonjour, type Service } from "bonjour-service";
import { WebSocketServer, type WebSocket } from "ws";
import { parseClientMessage } from "./protocol.js";
import { RoomManager } from "./room.js";
import { handleClientMessage, type ConnState } from "./dispatch.js";

/// Bonjour/mDNS service type the iPhone app browses for (`_frantics._tcp`).
/// Advertising this lets phones on the same WiFi find the server with zero
/// configuration — no LAN address to type in.
const BONJOUR_TYPE = "frantics";

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

  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    const remote = req.socket.remoteAddress ?? "?";
    console.log(`[conn] open from ${remote}`);
    ws.on("close", (code) => console.log(`[conn] closed ${remote} (code ${code})`));
    const conn: ConnState = { room: null, playerId: null };

    ws.on("message", (data) => {
      let parsed: unknown;
      try {
        parsed = JSON.parse(data.toString());
      } catch {
        return ws.send(JSON.stringify({ t: "error", message: "Malformed JSON" }));
      }
      const msg = parseClientMessage(parsed);
      if (!msg) return ws.send(JSON.stringify({ t: "error", message: "Missing message type" }));
      handleClientMessage(manager, conn, ws, msg);
    });

    ws.on("close", () => {
      if (conn.room && conn.playerId) conn.room.handleDisconnect(conn.playerId, ws);
    });
  });

  // Advertise over Bonjour so the iPhone app's "Same WiFi" mode finds us
  // automatically. Best-effort: if mDNS can't start (locked-down network,
  // permissions), the manual address path still works.
  let bonjour: Bonjour | null = null;
  let service: Service | null = null;
  try {
    // The error callback catches low-level mDNS socket errors (e.g. a transient
    // EHOSTUNREACH when WiFi drops). Without it, bonjour-service rethrows and
    // would crash the whole game server — discovery is best-effort, the game is not.
    bonjour = new Bonjour(undefined, (err: unknown) =>
      console.warn("[bonjour] mDNS error (discovery disabled, game unaffected):", err),
    );
    service = bonjour.publish({
      name: `Frantics on ${hostname()}`,
      type: BONJOUR_TYPE,
      port,
      txt: { path: "/" },
    });
    service.on("error", (err: unknown) => console.warn("[bonjour] advertise error:", err));
  } catch (err) {
    console.warn("[bonjour] could not start mDNS advertising:", err);
  }

  httpServer.listen(port, () => {
    console.log("");
    console.log("  🎉 Frantics server is up");
    console.log(`     local:   ws://localhost:${port}`);
    for (const addr of lanAddresses()) {
      console.log(`     LAN:     ws://${addr}:${port}`);
    }
    if (service) {
      console.log("     WiFi:    auto-discovered — pick \"Same WiFi\" in the app, no address needed");
    }
    console.log("");
  });

  return {
    httpServer,
    wss,
    manager,
    close() {
      try {
        service?.stop?.(() => {});
        bonjour?.destroy();
      } catch {
        /* ignore teardown errors */
      }
      wss.close();
      httpServer.close();
    },
  };
}
