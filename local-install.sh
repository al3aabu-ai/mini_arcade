#!/usr/bin/env bash
# local-install.sh — build Frantics and install it on the iPhone "iPhn".
# Pinned to ONE device on purpose (no auto-detection). Bypasses TestFlight.
#
#   ./local-install.sh
#
set -euo pipefail
cd "$(dirname "$0")"

DEVICE_ID="00008130-000C79C8369A001C"      # iPhn — change here if you swap phones
TEAM="${DEVELOPMENT_TEAM:-9472PWTG9J}"
DERIVED="ios/build/DerivedData-device"
APP="$DERIVED/Build/Products/Debug-iphoneos/Frantics.app"

echo "==> Building Frantics for iPhn…"
rm -rf "$DERIVED"
xcodebuild \
  -project ios/Frantics.xcodeproj \
  -scheme Frantics \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  clean build \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

[ -d "$APP" ] || { echo "✗ Build failed — scroll up for the error."; exit 1; }

echo "==> Installing on iPhn ($DEVICE_ID)…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "==> Launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" com.frantics.party || true

echo "✅ Done — Frantics is on iPhn."
