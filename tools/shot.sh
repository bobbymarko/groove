#!/usr/bin/env bash
# Screenshot a scene through the Bluetooth-enabled dev runner (LaunchServices launch,
# so macOS applies the bundle's Bluetooth usage description).
#   tools/shot.sh res://ui/screens/devices_screen.tscn build/devices.png [ride]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/build/RideDev.app"
[ -d "$RUNNER" ] || "$ROOT/tools/make-dev-runner.sh"
OUT="$2"; case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT";; esac
GODOT_BIN="$RUNNER/Contents/MacOS/Godot"
"$GODOT_BIN" --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
LOG="$ROOT/build/shot.log"; : > "$LOG"
open -W -n "$RUNNER" --args --path "$ROOT" --resolution 1280x800 --log-file "$LOG" \
  -s tools/screenshot.gd -- "$1" "$OUT" "${@:3}"
grep -E "screenshot|ERROR|SCRIPT ERROR|at:" "$LOG" || true
