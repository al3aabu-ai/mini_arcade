#!/usr/bin/env bash
# Archive + upload Frantics to TestFlight in one shot.
#
# One-time prerequisites (account owner, ~10 min + Apple review wait):
#   1. Paid Apple Developer Program membership (developer.apple.com/programs).
#   2. App record on appstoreconnect.apple.com: My Apps -> + -> New App
#      (platform iOS, bundle ID com.frantics.party).
#   3. App Store Connect API key: Users and Access -> Integrations ->
#      Team Keys -> Generate (role: App Manager). Download the .p8 once and
#      note the Key ID + Issuer ID.
#
# Usage:
#   TEAM_ID=XXXXXXXXXX \
#   ASC_KEY_ID=ABC123XYZ \
#   ASC_ISSUER_ID=12345678-aaaa-bbbb-cccc-1234567890ab \
#   ASC_KEY_PATH=$HOME/keys/AuthKey_ABC123XYZ.p8 \
#   ./scripts/release-testflight.sh
#
# Build numbers auto-increment from the clock so re-runs never collide.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your (paid) Apple Developer team ID}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID (App Store Connect API key id)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect issuer id)}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH (path to the AuthKey .p8 file)}"

BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHIVE_PATH="build/Frantics-${BUILD_NUMBER}.xcarchive"

echo "==> Archiving (build ${BUILD_NUMBER})"
xcodebuild archive \
  -project ios/Frantics.xcodeproj \
  -scheme Frantics \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${ASC_KEY_PATH}" \
  -authenticationKeyID "${ASC_KEY_ID}" \
  -authenticationKeyIssuerID "${ASC_ISSUER_ID}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  | grep -E "error:|warning: Signing|ARCHIVE" || true

[ -d "${ARCHIVE_PATH}" ] || { echo "Archive failed"; exit 1; }

echo "==> Uploading to App Store Connect / TestFlight"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "build/export-${BUILD_NUMBER}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${ASC_KEY_PATH}" \
  -authenticationKeyID "${ASC_KEY_ID}" \
  -authenticationKeyIssuerID "${ASC_ISSUER_ID}"

echo ""
echo "✅ Uploaded build ${BUILD_NUMBER}."
echo "   It appears in App Store Connect -> TestFlight after ~5-15 min of processing."
echo "   Add internal testers there; they install via the TestFlight app."
