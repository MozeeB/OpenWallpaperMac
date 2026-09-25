#!/usr/bin/env bash
# Builds OpenWallpaperMac and packages a drag-to-Applications DMG.
#
# Works without an Apple Developer account (ad-hoc signed). When signing credentials are present it
# signs with Developer ID + hardened runtime and, if notary credentials are present, notarizes and
# staples the DMG.
#
# Environment (all optional):
#   VERSION           marketing version, e.g. 0.2.0 (default: MARKETING_VERSION in project.yml)
#   BUILD_NUMBER      CFBundleVersion (default: 1)
#   DEVELOPER_ID      "Developer ID Application: Name (TEAMID)"; enables real signing
#   NOTARY_PROFILE    notarytool keychain profile, or...
#   NOTARY_KEY_PATH / NOTARY_KEY_ID / NOTARY_ISSUER   App Store Connect API key for notarytool
#   OUTPUT_DIR        where the DMG goes (default: dist)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Release/OpenWallpaperMac.app"
DMG="$OUTPUT_DIR/OpenWallpaperMac-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

log() { printf '\n==> %s\n' "$*"; }

log "Generating Xcode project"
command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --quiet

SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual)
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
fi

log "Building OpenWallpaperMac $VERSION ($BUILD_NUMBER)"
mkdir -p "$ROOT/build"
BUILD_LOG="$ROOT/build/release-build.log"
rm -rf "$APP"
if ! xcodebuild -project OpenWallpaperMac.xcodeproj -scheme OpenWallpaperMac -configuration Release \
  -derivedDataPath "$DERIVED" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${SIGN_ARGS[@]}" build > "$BUILD_LOG" 2>&1; then
  grep -E "error:" "$BUILD_LOG" | head -20 >&2 || tail -40 "$BUILD_LOG" >&2
  echo "Build failed; full log: $BUILD_LOG" >&2
  exit 1
fi
test -d "$APP" || { echo "Build failed: $APP missing" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

log "Creating DMG"
mkdir -p "$OUTPUT_DIR"
rm -f "$DMG"
ditto "$APP" "$STAGING/OpenWallpaperMac.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "OpenWallpaperMac $VERSION" -srcfolder "$STAGING" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  log "Signing DMG"
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    log "Notarizing (keychain profile)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    log "Notarizing (API key)"
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  fi
  if [[ -n "${NOTARY_PROFILE:-}${NOTARY_KEY_PATH:-}" ]]; then
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  fi
fi

hdiutil verify "$DMG" >/dev/null 2>&1 || { echo "DMG verification failed" >&2; exit 1; }
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
log "Done: $DMG ($(du -h "$DMG" | cut -f1))"
echo "$DMG"
