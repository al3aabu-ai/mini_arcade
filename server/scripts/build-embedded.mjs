// Bundle the on-device game engine (embedded.ts + room.ts + protocol.ts) into a
// single dependency-free JS file that the iOS app loads into JavaScriptCore.
//
//   npm run build:embedded
//
// JavaScriptCore has no Node globals, so we compile `process.env.*` flags to
// literals here. Timers, console, and crypto are injected natively by the app.
import { build } from "esbuild";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const outfile = resolve(here, "../../ios/Frantics/Resources/FranticsEngine.js");

await build({
  entryPoints: [resolve(here, "../src/embedded.ts")],
  bundle: true,
  format: "iife",
  target: "es2018",
  platform: "neutral",
  legalComments: "none",
  define: {
    "process.env.FAST_GAME": '"0"',
    "process.env.ALLOW_SOLO": '"0"',
  },
  outfile,
});

console.log(`✅ Built on-device engine → ${outfile}`);
