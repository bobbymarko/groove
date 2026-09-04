#!/usr/bin/env bash
# Restart the dev runner, unless a ride is in progress (an unfinished journal
# touched in the last three minutes). Pass --force to restart anyway; further
# arguments go to the app (e.g. -- summary=latest).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIDES="$HOME/Library/Application Support/Godot/app_userdata/Groove/rides"
if [ "${1:-}" != "--force" ] && [ -d "$RIDES" ]; then
  while IFS= read -r -d '' j; do
    if ! tail -n 1 "$j" | grep -q '"end"'; then
      echo "ride in progress ($(basename "$j")); not relaunching"; exit 2
    fi
  done < <(find "$RIDES" -name '*.jsonl' -mmin -3 -print0 2>/dev/null)
fi
pkill -f "GrooveDev.app/Contents/MacOS/Godot" || true
sleep 1
"$ROOT/tools/run-dev.sh" "${@:2}" >/dev/null 2>&1 &
sleep 3
pgrep -f GrooveDev >/dev/null && echo relaunched
