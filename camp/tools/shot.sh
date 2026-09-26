#!/usr/bin/env bash
# Render Camp's style lab.
#   camp/tools/shot.sh hero build/camp-hero.png [frames=60] [t=0.3] [--size 1600x900]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/build/GrooveDev.app"
[ -d "$RUNNER" ] || "$ROOT/tools/make-dev-runner.sh"
MODE="$1"; OUT="$2"; shift 2
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT";; esac
SIZE="1600x900"
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in --size) SIZE="$2"; shift 2;; *) EXTRA+=("$1"); shift;; esac
done
GODOT_BIN="$RUNNER/Contents/MacOS/Godot"
"$GODOT_BIN" --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
LOG="$ROOT/build/camp-shot.log"; : > "$LOG"
open -W -n "$RUNNER" --args --path "$ROOT" --resolution "$SIZE" --log-file "$LOG" \
  -s camp/tools/lab_shot.gd -- no-radio "$MODE" "$OUT" ${EXTRA[@]+"${EXTRA[@]}"} &
OPEN_PID=$!
# Watchdog: a script error leaves the window open forever, so give up after
# a while (or as soon as the log shows a parse error) and close only our run.
for _ in $(seq 1 ${CAMP_SHOT_TIMEOUT:-240}); do
  kill -0 "$OPEN_PID" 2>/dev/null || break
  if grep -q "SCRIPT ERROR" "$LOG" 2>/dev/null; then sleep 2; break; fi
  sleep 1
done
if kill -0 "$OPEN_PID" 2>/dev/null; then
  pkill -f "log-file $LOG" || true
  echo "camp shot: stopped (error or timeout)"
fi
wait "$OPEN_PID" 2>/dev/null || true
grep -E "screenshot|ERROR|SCRIPT ERROR|at:" "$LOG" || true
