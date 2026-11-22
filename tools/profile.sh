#!/usr/bin/env bash
# Profile the realistic look: median frame time for the full scene, then with
# each feature switched off in turn. Radio off, so it never touches the trainer.
#   tools/profile.sh [preset=summer] [at=2000] [hour=14] [route=<path>] [quick]
# Close other heavy apps first; another Groove window rendering skews the numbers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/build/GrooveDev.app"
[ -d "$RUNNER" ] || "$ROOT/tools/make-dev-runner.sh"
LOG="$(mktemp "$ROOT/build/profile.XXXXXX")"
open -W -n "$RUNNER" --args --path "$ROOT" --resolution 1280x800 --disable-vsync --log-file "$LOG" \
  -s tools/profile_real.gd -- "$@" no-radio
grep -E "prof\]|ERROR|SCRIPT ERROR|at:" "$LOG" || true
rm -f "$LOG"
