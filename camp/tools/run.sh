#!/usr/bin/env bash
# Open Camp's prototypes in a window. The radio stays off, so this never
# pairs with a trainer or interrupts a ride.
#   camp/tools/run.sh editor          the monster builder
#   camp/tools/run.sh lab [camp]      the scenes (keys 1-5 switch views)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/build/GrooveDev.app"
[ -d "$RUNNER" ] || "$ROOT/tools/make-dev-runner.sh"
"$RUNNER/Contents/MacOS/Godot" --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
case "${1:-editor}" in
  editor) SCENE="res://camp/editor/monster_editor.tscn"; shift || true;;
  lab)    SCENE="res://camp/lab/lab_viewer.tscn"; shift;;
  *) echo "usage: camp/tools/run.sh editor | lab [hero|lineup|three_quarter|camp|trader]"; exit 2;;
esac
open -n "$RUNNER" --args --path "$ROOT" "$SCENE" -- no-radio "$@"
