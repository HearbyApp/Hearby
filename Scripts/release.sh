#!/bin/bash
# Build a signed, notarized, drag-to-Applications DMG of SpeakSelection.
#
# This script is for YOU (the developer) — end users never run anything;
# they download the DMG, drag the app to Applications, and open it.
#
# One-time prerequisites:
#   1. Apple Developer Program membership ($99/yr).
#   2. A "Developer ID Application" certificate in your Keychain
#      (Xcode → Settings → Accounts → Manage Certificates → +).
#   3. Store notarization credentials once:
#        xcrun notarytool store-credentials notary-profile \
#          --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
#      (generate an app-specific password at appleid.apple.com)
#
# Then:  ./Scripts/release.sh "Developer ID Application: Your Name (TEAMID)"
set -euo pipefail

IDENTITY="${1:?Usage: release.sh \"Developer ID Application: Name (TEAMID)\"}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary-profile}"

cd "$(dirname "$0")/.."
BUILD=build/release
APP="$BUILD/SpeakSelection.app"
DMG="$BUILD/SpeakSelection.dmg"
rm -rf "$BUILD" && mkdir -p "$BUILD"

echo "==> Generating Xcode project"
xcodegen

echo "==> Building Release"
xcodebuild -project SpeakSelection.xcodeproj \
  -scheme SpeakSelection -configuration Release \
  -derivedDataPath "$BUILD/dd" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO \
  build
cp -R "$BUILD/dd/Build/Products/Release/SpeakSelection.app" "$APP"

echo "==> Signing with Developer ID (hardened runtime)"
codesign --force --deep --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Building DMG"
STAGE="$BUILD/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SpeakSelection" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "==> Notarizing (this waits for Apple; usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$DMG"

echo ""
echo "✓ Ready to ship: $DMG"
echo "  Users: download → open DMG → drag to Applications → launch."
