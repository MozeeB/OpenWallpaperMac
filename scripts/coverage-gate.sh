#!/usr/bin/env bash
# Per-module line coverage from `swift test --enable-code-coverage`; fails below the threshold.
# SwiftUI views and the thin CLI are reported but excluded from the gate (covered by UI tests / e2e).
set -euo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-80}"
BIN_DIR="$(swift build --show-bin-path)"
PROFDATA="$BIN_DIR/codecov/default.profdata"
TEST_BINARY="$BIN_DIR/OpenWallpaperMacPackageTests.xctest/Contents/MacOS/OpenWallpaperMacPackageTests"

if [[ ! -f "$PROFDATA" ]]; then
  echo "No coverage data; run: swift test --enable-code-coverage" >&2
  exit 2
fi

REPORT="$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(\.build|Tests|/Views/|/owctl/)' 2>/dev/null)"

printf '%-18s %8s %8s %8s\n' "Module" "Lines" "Missed" "Cover"
FAIL=0
MODULES="OWCore OWFormats OWAudioAnalysis OWAudioCapture OWPower OWDesktop OWRendering OWScene OWLibrary OWAppFeature"
# The Core Audio tap needs real audio hardware; gate it only when the live test ran (OW_LIVE_AUDIO=1).
UNGATED=""
if [[ "${OW_LIVE_AUDIO:-0}" != "1" ]]; then UNGATED="OWAudioCapture"; fi
for module in $MODULES; do
  # llvm-cov prints paths relative to Sources/, e.g. "OWCore/Models/Wallpaper.swift".
  read -r lines missed < <(echo "$REPORT" | awk -v prefix="$module/" '
    index($1, prefix) == 1 { lines += $8; missed += $9 } END { print lines + 0, missed + 0 }')
  if [[ "$lines" -eq 0 ]]; then continue; fi
  cover=$(awk -v l="$lines" -v m="$missed" 'BEGIN { printf "%.1f", (l - m) * 100 / l }')
  flag=""
  if awk -v c="$cover" -v t="$THRESHOLD" 'BEGIN { exit !(c < t) }'; then
    if [[ " $UNGATED " == *" $module "* ]]; then flag="  (not gated: needs OW_LIVE_AUDIO=1)"; else flag="  < ${THRESHOLD}%"; FAIL=1; fi
  fi
  printf '%-18s %8d %8d %7s%%%s\n' "$module" "$lines" "$missed" "$cover" "$flag"
done

TOTAL=$(echo "$REPORT" | awk '/^TOTAL/ { print $10 }')
echo "TOTAL line coverage (gated files): $TOTAL"
exit $FAIL
