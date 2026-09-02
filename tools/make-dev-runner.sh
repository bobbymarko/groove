#!/usr/bin/env bash
# Builds build/RideDev.app: a copy of the installed Godot editor with a
# Bluetooth usage description added to its Info.plist and an ad-hoc signature.
#
# Why: macOS refuses CoreBluetooth access to apps whose Info.plist lacks
# NSBluetoothAlwaysUsageDescription, and the stock Godot.app has none. Running
# the project through this copy lets GDBLE reach the trainer during development.
# Exported builds get the key from the export preset instead.
#
# Usage:  tools/make-dev-runner.sh            # build the runner
#         tools/run-dev.sh                    # launch the project with it
set -euo pipefail

GODOT_APP="${GODOT_APP:-/Applications/Godot.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"   # keep Godot from scanning build/
OUT="$ROOT/build/RideDev.app"
ENT="$ROOT/build/godot.entitlements"

[ -d "$GODOT_APP" ] || { echo "Godot not found at $GODOT_APP (set GODOT_APP)"; exit 1; }

mkdir -p "$ROOT/build"
rm -rf "$OUT"
cp -R "$GODOT_APP" "$OUT"

PLIST="$OUT/Contents/Info.plist"
DESC="Ride connects to your smart trainer and sensors over Bluetooth."
plutil -replace NSBluetoothAlwaysUsageDescription -string "$DESC" "$PLIST"
plutil -replace NSBluetoothPeripheralUsageDescription -string "$DESC" "$PLIST"
plutil -replace CFBundleIdentifier -string "dev.ride.godot-dev" "$PLIST"
plutil -replace CFBundleName -string "RideDev" "$PLIST"

# Keep Godot's own entitlements (notably disable-library-validation, which
# lets the editor load third-party GDExtension dylibs), but re-sign ad hoc.
codesign -d --entitlements :- "$GODOT_APP" 2>/dev/null > "$ENT"
xattr -cr "$OUT" || true
codesign --force --deep --sign - --entitlements "$ENT" "$OUT"
codesign --verify --deep --strict "$OUT"
echo "Built $OUT"
