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
  # `xctrace list devices` groups output: real hardware appears under
  # "== Devices ==" (before "== Simulators =="). We read ONLY that block — never a
  # simulator. A physical iOS device has an OS version like "(17.5.1)" and a
  # trailing UDID; the Mac host has no version. Match on the VERSION pattern, not
  # the device name (yours is "iPhn", not "iPhone"), and grab the trailing UDID.
  xcrun xctrace list devices 2>/dev/null | awk '
      /^== / { indev = ($0 ~ /== Devices ==/) ? 1 : 0; next }
      indev && /\([0-9]+\.[0-9]/ { print; }
    ' | head -1 | sed -E 's/.*\(([0-9A-Fa-f][0-9A-Fa-f-]+)\)[[:space:]]*$/\1/'
}

bold "==> Looking for a connected iPhone…"
DEVICE_ID="$(resolve_device)"
if [ -z "$DEVICE_ID" ]; then
  fail "No iPhone detected. Plug it in with a cable, unlock it, tap \"Trust\" if asked, then re-run. (Override: DEVICE_ID=<udid> ./local-install.sh)"
fi
DEVICE_NAME="$(xcrun xctrace list devices 2>/dev/null | grep "$DEVICE_ID" | head -1 | sed -E 's/ *\(.*//')"
echo "    iPhone: ${DEVICE_NAME:-?}  ($DEVICE_ID)"

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
    ios-deploy --no-wifi --id "$DEVICE_ID" --bundle "$APP"
  else
    ios-deploy --no-wifi --justlaunch --id "$DEVICE_ID" --bundle "$APP"
  fi
else
  echo ""
  echo "No installer found. Either Xcode 15+ (for devicectl) or ios-deploy is needed."
  read -r -p "Install ios-deploy via Homebrew now? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    command -v brew >/dev/null 2>&1 || fail "Homebrew not found — install it from https://brew.sh first."
    brew install ios-deploy
    bold "==> Installing via ios-deploy…"
    ios-deploy --no-wifi --justlaunch --id "$DEVICE_ID" --bundle "$APP"
  else
    fail "Skipped install. Re-run after installing ios-deploy (brew install ios-deploy) or Xcode 15+."
  fi
fi

bold "✅ Done — Frantics is on your device."
