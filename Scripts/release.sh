#!/bin/zsh
#
#  release.sh
#  Q2-Sync › Scripts
#
#  PURPOSE
#  Builds the Release version of Q2 Sync signed with your Developer ID,
#  has Apple notarize it, and packs it as a zip with a SHA-256 checksum,
#  ready to attach to a GitHub release.
#
#  ONE-TIME SETUP (nothing here goes in the repository)
#  1. Install your "Developer ID Application" certificate in your keychain
#     (Xcode › Settings › Accounts › Manage Certificates).
#  2. Store notarization credentials under a profile name, using an
#     app-specific password from appleid.apple.com:
#         xcrun notarytool store-credentials "q2sync-notary" \
#             --apple-id "you@example.com" --team-id "YOURTEAMID"
#
#  USAGE (from the repository root; commit your changes first)
#      TEAM_ID=YOURTEAMID Scripts/release.sh
#  Optional: NOTARY_PROFILE=name (default q2sync-notary).
#
#  OUTPUT (in build/release/)
#      Q2-Sync-<version>.zip      the notarized, stapled app
#      Q2-Sync-<version>.zip.sha256
#
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-q2sync-notary}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first, so the build number and hash are exact."
  exit 1
fi

APP_NAME="Q2 Sync.app"
DERIVED="build/release-DerivedData"
OUT="build/release"
BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"

echo "→ Building and signing with Developer ID (hardened runtime, secure timestamp)…"
rm -rf "$DERIVED" "$OUT"
mkdir -p "$OUT"
xcodebuild -project Q2-Sync.xcodeproj -scheme Q2-Sync -configuration Release \
  -derivedDataPath "$DERIVED" -quiet \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

[[ -d "$BUILT_APP" ]] || { echo "Build output not found at $BUILT_APP"; exit 1; }

echo "→ Checking the signature…"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

PLIST="$BUILT_APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
COMMIT=$(/usr/libexec/PlistBuddy -c "Print :Q2SyncBuildCommit" "$PLIST")
ZIP="$OUT/Q2-Sync-$VERSION.zip"

echo "→ Sending to Apple for notarization (a few minutes)…"
ditto -c -k --keepParent "$BUILT_APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
rm "$OUT/notarize.zip"

echo "→ Stapling the notarization ticket…"
xcrun stapler staple "$BUILT_APP"
spctl --assess --type execute --verbose=2 "$BUILT_APP"

echo "→ Packing $ZIP…"
ditto -c -k --keepParent "$BUILT_APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

echo "✓ Q2 Sync $VERSION ($BUILD · $COMMIT) is ready:"
echo "  $ZIP"
cat "$ZIP.sha256"
