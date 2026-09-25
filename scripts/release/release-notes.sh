#!/usr/bin/env bash
# Generates Markdown release notes from conventional commits between the previous tag and TAG.
# Usage: scripts/release/release-notes.sh [TAG] [--signed]
#   TAG defaults to HEAD. --signed omits the "unsigned build" install note.
#   NOTES_VERSION=x.y.z names a release whose tag does not exist yet (automatic releases).
set -euo pipefail

TAG="${1:-HEAD}"
SIGNED="${2:-}"
REPO_URL="${REPO_URL:-https://github.com/MozeeB/OpenWallpaperMac}"

# A tagged release starts after the previous tag; an untagged (automatic) one after the latest tag.
BASE="$TAG^"
[[ -n "${NOTES_VERSION:-}" ]] && BASE="$TAG"
PREVIOUS="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$BASE" 2>/dev/null || true)"
if [[ -n "$PREVIOUS" ]]; then RANGE="$PREVIOUS..$TAG"; else RANGE="$TAG"; fi
VERSION="${NOTES_VERSION:-${TAG#v}}"
TAG_NAME="$TAG"
[[ -n "${NOTES_VERSION:-}" ]] && TAG_NAME="v$NOTES_VERSION"

section() {
  local title="$1" pattern="$2" lines
  lines="$(git log --no-merges --pretty=format:'%s|%h' "$RANGE" | grep -E "^($pattern)(\([^)]*\))?!?: " || true)"
  [[ -z "$lines" ]] && return 0
  printf '### %s\n\n' "$title"
  while IFS='|' read -r subject hash; do
    local text="${subject#*: }"
    printf -- '- %s%s (%s)\n' "$(printf '%s' "${text:0:1}" | tr '[:lower:]' '[:upper:]')" "${text:1}" "[\`$hash\`]($REPO_URL/commit/$hash)"
  done <<< "$lines"
  printf '\n'
}

if [[ "$VERSION" == "HEAD" ]]; then echo "## Unreleased"; else echo "## OpenWallpaperMac $VERSION"; fi
echo
section "Features" "feat"
section "Fixes" "fix"
section "Performance" "perf"
section "Refactoring" "refactor"
section "Documentation" "docs"
section "Maintenance" "chore|ci|test|build"

cat <<EOF
### Install

1. Download \`OpenWallpaperMac-$VERSION.dmg\` below and open it.
2. Drag **OpenWallpaperMac** into **Applications**, then launch it. It appears in the Dock and the menu bar.
EOF
if [[ "$SIGNED" != "--signed" ]]; then
  cat <<'EOF'
3. This build is not notarized. On first launch macOS will block it: open **System Settings > Privacy &
   Security** and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/OpenWallpaperMac.app`).
EOF
fi
cat <<EOF

Requires macOS 15 or later (Apple silicon recommended). Verify the download with the attached \`.sha256\` file.

EOF
if [[ -n "$PREVIOUS" ]]; then echo "**Full changelog:** $REPO_URL/compare/$PREVIOUS...$TAG_NAME"; fi
