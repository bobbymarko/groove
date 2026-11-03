#!/usr/bin/env bash
# Open Camp's prototypes in a window. The radio stays off, so this never
# pairs with a trainer or interrupts a ride.
#   camp/tools/run.sh editor          the monster builder
#   camp/tools/run.sh lab [camp]      the scenes (keys 1-5 switch views)
#   camp/tools/run.sh ride [workout=res://...]        a practice ride on the simulator
#   camp/tools/run.sh ride real [workout=res://...]   a real ride on your paired trainer
#     (real rides use Bluetooth and are recorded; close Groove first so the
#      two apps don't fight over the trainer)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/build/GrooveDev.app"
[ -d "$RUNNER" ] || "$ROOT/tools/make-dev-runner.sh"
"$RUNNER/Contents/MacOS/Godot" --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
RADIO="no-radio"
case "${1:-editor}" in
  editor) SCENE="res://camp/editor/monster_editor.tscn"; shift || true;;
  lab)    SCENE="res://camp/lab/lab_viewer.tscn"; shift;;
  ride)   SCENE="res://camp/ride/camp_ride.tscn"; shift
          [ "${1:-}" = "real" ] && RADIO="real";;
  *) echo "usage: camp/tools/run.sh editor | lab [view] | ride [real] [workout=res://...]"; exit 2;;
esac
open -n "$RUNNER" --args --path "$ROOT" "$SCENE" -- "$RADIO" "$@"
