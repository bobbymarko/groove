#!/usr/bin/env bash
# Launches the project in the Bluetooth-enabled dev runner, logging to build/run.log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/build/RideDev.app"
[ -d "$RUNNER" ] || "$ROOT/tools/make-dev-runner.sh"
"$RUNNER/Contents/MacOS/Godot" --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
: > "$ROOT/build/run.log"
open "$RUNNER" --args --path "$ROOT" --log-file "$ROOT/build/run.log" "$@"
echo "Launched. Log: $ROOT/build/run.log"
