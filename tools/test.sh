#!/usr/bin/env bash
# Runs the unit tests headless. Imports first so new global classes are registered.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"   # keep Godot from scanning build/
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
OUT="$("$GODOT" --headless --path "$ROOT" -s tests/run_tests.gd 2>&1)"; STATUS=$?
echo "$OUT"
if echo "$OUT" | grep -q -E "SCRIPT ERROR|Parse Error|Compile Error"; then
  echo "FAIL: script errors during test run"; exit 1
fi
exit $STATUS
