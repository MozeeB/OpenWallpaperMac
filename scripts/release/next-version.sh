#!/usr/bin/env bash
# Prints the next semantic version based on conventional commits since the latest v* tag,
# or nothing when no commit warrants a release.
#
#   feat!: / fix!: / "BREAKING CHANGE" -> major (minor while the major version is 0)
#   feat:                              -> minor
#   fix: / perf:                       -> patch
#   anything else (docs, chore, ci, test, style, refactor, build) -> no release
#
# Usage: scripts/release/next-version.sh [REF]   (REF defaults to HEAD)
set -euo pipefail

REF="${1:-HEAD}"
LATEST="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$REF" 2>/dev/null || true)"

if [[ -z "$LATEST" ]]; then
  RANGE="$REF"
  CURRENT="0.0.0"
else
  # Nothing new since the latest tag (e.g. the tag already points at REF).
  if [[ "$(git rev-parse "$LATEST^{commit}")" == "$(git rev-parse "$REF^{commit}")" ]]; then exit 0; fi
  RANGE="$LATEST..$REF"
  CURRENT="${LATEST#v}"
fi

SUBJECTS="$(git log --no-merges --format='%s' "$RANGE")"
BODIES="$(git log --no-merges --format='%b' "$RANGE")"

bump=""
if grep -qE '^[a-z]+(\([^)]*\))?!:' <<< "$SUBJECTS" || grep -q 'BREAKING CHANGE' <<< "$BODIES"; then
  bump="major"
elif grep -qE '^feat(\([^)]*\))?:' <<< "$SUBJECTS"; then
  bump="minor"
elif grep -qE '^(fix|perf)(\([^)]*\))?:' <<< "$SUBJECTS"; then
  bump="patch"
fi
[[ -z "$bump" ]] && exit 0

IFS=. read -r major minor patch <<< "$CURRENT"
case "$bump" in
  major)
    if [[ "$major" -eq 0 ]]; then minor=$((minor + 1)); patch=0; else major=$((major + 1)); minor=0; patch=0; fi ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac
echo "$major.$minor.$patch"
