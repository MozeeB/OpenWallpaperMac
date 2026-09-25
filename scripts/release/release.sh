#!/usr/bin/env bash
# Builds, signs (Developer ID, hardened runtime), notarizes and packages a DMG.
#
# Required environment:
#   DEVELOPER_ID   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE keychain profile created with:
#                  xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
set -euo pipefail

: "${DEVELOPER_ID:?set DEVELOPER_ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
VERSION="$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)"
DIST="$ROOT/dist"
APP="$ROOT/build/DerivedData/Build/Products/Release/OpenWallpaperMac.app"
DMG="$DIST/OpenWallpaperMac-$VERSION.dmg"

rm -rf "$DIST" && mkdir -p "$DIST"
xcodegen generate
xcodebuild -project OpenWallpaperMac.xcodeproj -scheme OpenWallpaperMac -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build

codesign --verify --deep --strict --verbose=2 "$APP"

hdiutil create -volname "OpenWallpaperMac" -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Release ready: $DMG"
