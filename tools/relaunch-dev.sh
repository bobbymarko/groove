#!/usr/bin/env bash
# Restart the dev runner, unless a ride is in progress (an unfinished journal
# touched in the last three minutes). Pass --force to restart anyway.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIDES="$HOME/Library/Application Support/Godot/app_userdata/Ride/rides"
if [ "${1:-}" != "--force" ] && [ -d "$RIDES" ]; then
  for j in $(find "$RIDES" -name '*.jsonl' -mmin -3 2>/dev/null); do
    if ! tail -1 "$j" | grep -q '"end"'; then
      echo "ride in progress ($j); not relaunching"; exit 2
    fi
  done
fi
pkill -f "RideDev.app/Contents/MacOS/Godot" || true
sleep 1
"$ROOT/tools/run-dev.sh" >/dev/null 2>&1 &
sleep 3
pgrep -f RideDev >/dev/null && echo relaunched
