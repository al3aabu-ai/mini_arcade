// Portable random IDs that work both under Node (uses the platform's strong
// crypto) and inside the iOS host's JavaScriptCore engine, which has no
// `node:crypto`. Falls back to a v4-shaped Math.random UUID — fine for room and
// seat tokens in a LAN party game.
export function randomUUID(): string {
  const g = globalThis as { crypto?: { randomUUID?: () => string } };
  if (typeof g.crypto?.randomUUID === "function") return g.crypto.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
