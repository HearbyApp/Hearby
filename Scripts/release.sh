#!/bin/bash
# Build a signed, notarized, drag-to-Applications DMG of Hearby.
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
#
# To rehearse the install flow before you have that certificate:
#
#   ./Scripts/release.sh --local
#
# builds the same DMG signed with your Apple Development identity, skipping
# notarization and the appcast. It installs and runs correctly on THIS Mac.
# It is not distributable — on anyone else's machine Gatekeeper blocks it,
# which is exactly the friction notarization removes.
set -euo pipefail

cd "$(dirname "$0")/.."

LOCAL=0
if [ "${1:-}" = "--local" ]; then
  LOCAL=1
  # First codesigning identity in the keychain — whatever this Mac has.
  IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
  if [ -z "$IDENTITY" ]; then
    echo "FATAL: no codesigning identity found in your keychain." >&2
    exit 1
  fi
  echo "==> LOCAL TEST BUILD — not notarized, not distributable"
  echo "    signing as: $IDENTITY"
else
  IDENTITY="${1:?Usage: release.sh \"Developer ID Application: Name (TEAMID)\" | --local}"
fi
NOTARY_PROFILE="${NOTARY_PROFILE:-notary-profile}"

BUILD=build/release
APP="$BUILD/Hearby.app"
DMG="$BUILD/Hearby.dmg"
rm -rf "$BUILD" && mkdir -p "$BUILD"

echo "==> Generating Xcode project"
xcodegen

echo "==> Checking the Sparkle feed is configured"
# Shipping the placeholder means every copy has auto-update silently off,
# with no way to push a fix to the users who already installed it. A local
# test build is never distributed, so it is allowed to carry the placeholder.
if grep -q "YOUR-GITHUB-USERNAME" project.yml; then
  if [ "$LOCAL" -eq 1 ]; then
    echo "    placeholder feed — auto-update will be disabled in this build"
  else
    echo "FATAL: SUFeedURL in project.yml is still the placeholder." >&2
    echo "       Set it to your GitHub owner/repo before releasing." >&2
    exit 1
  fi
fi

# Single source of truth for both: project.yml. Deriving them keeps the git
# tag, the DMG and the appcast's download URLs from drifting apart.
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
GITHUB_REPO=$(awk -F'/' '/SUFeedURL:/ {print $4 "/" $5; exit}' project.yml)
if [ "$LOCAL" -eq 1 ]; then GITHUB_REPO="${GITHUB_REPO:-local/local}"; fi
if [ -z "$VERSION" ] || [ -z "$GITHUB_REPO" ]; then
  echo "FATAL: could not read MARKETING_VERSION or SUFeedURL from project.yml" >&2
  exit 1
fi
echo "    v$VERSION -> $GITHUB_REPO"

echo "==> Running unit tests"
# Logged rather than piped: piping into grep would mask xcodebuild's exit
# status, and a trailing `|| true` resets PIPESTATUS, so a failing suite
# would sail through unnoticed.
TESTLOG="$BUILD/tests.log"
if ! xcodebuild test -project Hearby.xcodeproj \
  -scheme Hearby -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD/dd-test" >"$TESTLOG" 2>&1; then
  grep -E "error:|XCTAssert.* failed" "$TESTLOG" | head -20 >&2
  echo "FATAL: tests failed — full log at $TESTLOG" >&2
  exit 1
fi
grep -E "Executed [0-9]+ tests" "$TESTLOG" | tail -1

echo "==> Building Release (universal)"
# -destination 'generic/platform=macOS' is load-bearing: without it xcodebuild
# builds only the host architecture and ships an arm64-only app that Intel
# Macs cannot run, regardless of ARCHS/ONLY_ACTIVE_ARCH.
xcodebuild -project Hearby.xcodeproj \
  -scheme Hearby -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/dd" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO \
  build
cp -R "$BUILD/dd/Build/Products/Release/Hearby.app" "$APP"

echo "==> Verifying universal binary"
archs=$(lipo -archs "$APP/Contents/MacOS/Hearby")
for want in arm64 x86_64; do
  case " $archs " in
    *" $want "*) ;;
    *) echo "FATAL: binary is missing the $want slice (got: $archs)" >&2; exit 1 ;;
  esac
done
echo "    $archs"

echo "==> Self-test (loads the voice bundle and synthesizes)"
# Catches a model/config mismatch — wrong filename, missing lexicon, stale
# speaker table — before it reaches a customer as an app that says nothing.
# Needs the voice bundle installed on this machine; launch the app once first.
MODEL_DIR="$HOME/Library/Application Support/Hearby/kokoro-multi-lang-v1_0"
if [ -d "$MODEL_DIR" ]; then
  "$APP/Contents/MacOS/Hearby" --self-test
else
  echo "    SKIPPED: voice bundle not installed at $MODEL_DIR"
  echo "    Launch Hearby once to download it, then re-run for a verified build."
fi

echo "==> Signing with Developer ID (hardened runtime)"
# Inside out, never --deep. Apple discourages --deep, and it would in any
# case apply the app's own settings to Sparkle's nested helpers rather than
# what each of them needs. Sparkle ships four nested bundles plus the
# framework; each must carry its own signature before the enclosing bundle
# is sealed, or the outer signature is invalidated the moment anything
# inside it changes.
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  sign "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE/Versions/B"
fi

sign "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "==> Building DMG"
STAGE="$BUILD/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Hearby" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
# The DMG needs its own signature: the app inside is notarized either way,
# but Gatekeeper's check of the downloaded file rejects an unsigned image
# ("no usable signature").
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$LOCAL" -eq 1 ]; then
  echo ""
  echo "✓ Local test build: $DMG"
  echo ""
  echo "  Install it the way a user would:"
  echo "    open \"$DMG\"           # mounts it in Finder"
  echo "    drag Hearby onto the Applications shortcut"
  echo "    open /Applications/Hearby.app"
  echo ""
  echo "  Not notarized: this runs on THIS Mac only. On any other machine"
  echo "  Gatekeeper will refuse it until you have a Developer ID cert."
  exit 0
fi

echo "==> Notarizing (this waits for Apple; usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$DMG"

echo "==> Verifying the shipped artifact"
xcrun stapler validate "$DMG"
# Gatekeeper's actual verdict on a fresh Mac. Only meaningful now that the
# ticket is stapled — running it before notarization always fails.
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "==> Generating the Sparkle appcast"
# generate_appcast signs each update with the private EdDSA key from the
# login Keychain and writes appcast.xml describing everything in the folder.
# Sparkle's tools come with the Swift package the build just resolved;
# point SPARKLE_BIN elsewhere to use another copy.
SPARKLE_BIN="${SPARKLE_BIN:-$BUILD/dd/SourcePackages/artifacts/sparkle/Sparkle/bin}"
if [ -x "$SPARKLE_BIN/generate_appcast" ]; then
  # generate_appcast reads every archive in the directory, so give it one
  # containing just this release.
  CAST="$BUILD/appcast-input"
  mkdir -p "$CAST"
  cp "$DMG" "$CAST/"
  "$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v$VERSION/" \
    "$CAST"
  cp "$CAST/appcast.xml" "$BUILD/appcast.xml"
  echo "    $BUILD/appcast.xml"
else
  echo "    SKIPPED: Sparkle tools not found at $SPARKLE_BIN" >&2
  echo "    Download Sparkle-*.tar.xz from github.com/sparkle-project/Sparkle/releases" >&2
  echo "    and extract its bin/ there, or set SPARKLE_BIN." >&2
  exit 1
fi

echo ""
echo "✓ Ready to ship: $DMG"
echo ""
echo "  Publish as GitHub release v$VERSION on $GITHUB_REPO, attaching BOTH:"
echo "    - $DMG"
echo "    - $BUILD/appcast.xml"
echo "  The appcast must be attached to every release: the feed URL points at"
echo "  /releases/latest/download/appcast.xml, so a release without it breaks"
echo "  updates for everyone."
echo ""
echo "  Users: download → open DMG → drag to Applications → launch."
