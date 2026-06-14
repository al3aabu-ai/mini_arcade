#!/usr/bin/env bash
# local-install.sh — build the Frantics SceneKit app and install it straight onto
# a plugged-in iPhone, bypassing App Store Connect / TestFlight entirely (no
# upload, no ITMS-90382 daily limit).
#
#   ./local-install.sh                 # clean → build (signed) → install → launch
#   DEVICE_ID=<udid> ./local-install.sh
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./local-install.sh
#   NO_LAUNCH=1 ./local-install.sh     # install but don't auto-launch
#
# Requires: Xcode + command line tools. Uses `xcrun devicectl` (Xcode 15+, no
# third-party tools) and falls back to `ios-deploy` (auto-installed via Homebrew
# if you approve).

set -euo pipefail
cd "$(dirname "$0")"

SCHEME="${SCHEME:-Frantics}"
CONFIG="${CONFIG:-Debug}"
PROJECT="ios/Frantics.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-com.frantics.party}"
# Free personal team from TESTFLIGHT.md; override with DEVELOPMENT_TEAM=... if needed.
TEAM="${DEVELOPMENT_TEAM:-9472PWTG9J}"
DERIVED="ios/build/DerivedData-device"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
fail() { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

# --- 1. Find a connected iPhone --------------------------------------------------

resolve_device() {
  [ -n "${DEVICE_ID:-}" ] && { echo "$DEVICE_ID"; return; }
  local json=/tmp/frantics-devices.json
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || return 0
  python3 - "$json" <<'PY' 2>/dev/null || true
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devs:
    cp = d.get("connectionProperties", {})
    hw = d.get("hardwareProperties", {})
    if cp.get("tunnelState") not in ("unavailable", None) and hw.get("deviceType", "").lower() in ("iphone", "ipad"):
        print(d["identifier"]); break
PY
}

bold "==> Looking for a connected iPhone…"
DEVICE_ID="$(resolve_device)"
if [ -n "$DEVICE_ID" ]; then
  echo "    device: $DEVICE_ID"
else
  echo "    (couldn't auto-detect via devicectl — will rely on ios-deploy auto-detect)"
fi

# --- 2. Clean the build cache ----------------------------------------------------

bold "==> Cleaning build cache…"
rm -rf "$DERIVED"
xcodebuild clean -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" >/dev/null

# --- 3. Build + sign for the device ---------------------------------------------

bold "==> Building $SCHEME ($CONFIG) for device, signing with team $TEAM…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build \
  | grep -E "error:|warning: Signing|BUILD SUCCEEDED|BUILD FAILED" || true

APP="$(find "$DERIVED/Build/Products/$CONFIG-iphoneos" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
[ -d "$APP" ] || fail "Build produced no .app — scroll up for the xcodebuild error (signing/provisioning?)."
echo "    built: $APP"

# --- 4. Install onto the device --------------------------------------------------

launch_flag() { [ -n "${NO_LAUNCH:-}" ] && echo "" || echo "launch"; }

if xcrun devicectl --version >/dev/null 2>&1 && [ -n "$DEVICE_ID" ]; then
  bold "==> Installing via devicectl…"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  if [ -z "${NO_LAUNCH:-}" ]; then
    bold "==> Launching on device…"
    xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || \
      echo "    (installed; auto-launch failed — just tap the app on your phone)"
  fi
elif command -v ios-deploy >/dev/null 2>&1; then
  bold "==> Installing via ios-deploy…"
  if [ -n "${NO_LAUNCH:-}" ]; then
    ios-deploy --no-wifi --bundle "$APP"
  else
    ios-deploy --no-wifi --justlaunch --bundle "$APP"
  fi
else
  echo ""
  echo "No installer found. Either Xcode 15+ (for devicectl) or ios-deploy is needed."
  read -r -p "Install ios-deploy via Homebrew now? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    command -v brew >/dev/null 2>&1 || fail "Homebrew not found — install it from https://brew.sh first."
    brew install ios-deploy
    bold "==> Installing via ios-deploy…"
    ios-deploy --no-wifi --justlaunch --bundle "$APP"
  else
    fail "Skipped install. Re-run after installing ios-deploy (brew install ios-deploy) or Xcode 15+."
  fi
fi

bold "✅ Done — Frantics is on your device."
