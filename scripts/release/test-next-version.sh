#!/usr/bin/env bash
# Tests next-version.sh against throwaway git repositories.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/next-version.sh"
FAILURES=0

repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  echo "$dir"
}

commit() { git -C "$1" commit -q --allow-empty -m "$2" ${3:+-m "$3"}; }

expect() {
  local name="$1" dir="$2" want="$3" got
  got="$(cd "$dir" && "$SCRIPT")"
  if [[ "$got" == "$want" ]]; then
    echo "ok    $name -> '${got}'"
  else
    echo "FAIL  $name: want '$want', got '$got'"
    FAILURES=$((FAILURES + 1))
  fi
}

d=$(repo); commit "$d" "feat: first"; expect "no tag, feat" "$d" "0.1.0"
d=$(repo); commit "$d" "chore: setup"; expect "no tag, chore only" "$d" ""

d=$(repo); commit "$d" "feat: a"; git -C "$d" tag v0.1.1
expect "tag on HEAD" "$d" ""
commit "$d" "docs: readme"; commit "$d" "ci: pipeline"; commit "$d" "style: format"
expect "docs/ci/style only" "$d" ""
commit "$d" "fix: bug"; expect "fix -> patch" "$d" "0.1.2"
commit "$d" "perf(video): faster"; expect "perf with scope -> patch" "$d" "0.1.2"
commit "$d" "feat(ui): button"; expect "feat -> minor" "$d" "0.2.0"
commit "$d" "feat!: new format"; expect "breaking on 0.x -> minor" "$d" "0.2.0"

d=$(repo); commit "$d" "feat: a"; git -C "$d" tag v1.4.2
commit "$d" "fix: b"; expect "1.x fix" "$d" "1.4.3"
commit "$d" "refactor: c" "BREAKING CHANGE: removes old API"; expect "1.x breaking footer -> major" "$d" "2.0.0"

d=$(repo); commit "$d" "feat: a"; git -C "$d" tag v0.3.0; git -C "$d" tag not-a-version
commit "$d" "fix: b"; expect "ignores non-version tags" "$d" "0.3.1"

if [[ "$FAILURES" -gt 0 ]]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all next-version tests passed"
