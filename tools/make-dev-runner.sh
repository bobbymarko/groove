#!/usr/bin/env bash
# Builds build/GrooveDev.app: a copy of the installed Godot editor with a
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
OUT="$ROOT/build/GrooveDev.app"
ENT="$ROOT/build/godot.entitlements"

[ -d "$GODOT_APP" ] || { echo "Godot not found at $GODOT_APP (set GODOT_APP)"; exit 1; }

mkdir -p "$ROOT/build"
rm -rf "$OUT"
cp -R "$GODOT_APP" "$OUT"

PLIST="$OUT/Contents/Info.plist"
DESC="Ride connects to your smart trainer and sensors over Bluetooth."
plutil -replace NSBluetoothAlwaysUsageDescription -string "$DESC" "$PLIST"
plutil -replace NSBluetoothPeripheralUsageDescription -string "$DESC" "$PLIST"
plutil -replace CFBundleIdentifier -string "app.groove.dev" "$PLIST"
plutil -replace CFBundleName -string "GrooveDev" "$PLIST"
plutil -replace CFBundleDisplayName -string "Groove" "$PLIST"

# App icon: the coach's face inside the macOS squircle (tools/make_icon.py), as an iconset.
ICONSET="$ROOT/build/Groove.iconset"
SRC_ICON="$ROOT/assets/images/app-icon.png"
[ -f "$SRC_ICON" ] || python3 "$ROOT/tools/make_icon.py" "$ROOT/assets/images/coach-avatar.png" "$SRC_ICON"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC_ICON" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC_ICON" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/Groove.icns"
plutil -replace CFBundleIconFile -string "Groove.icns" "$PLIST"
plutil -remove CFBundleIconName "$PLIST" 2>/dev/null || true

# Keep Godot's own entitlements (notably disable-library-validation, which
# lets the editor load third-party GDExtension dylibs), but re-sign ad hoc.
codesign -d --entitlements :- "$GODOT_APP" 2>/dev/null > "$ENT"
xattr -cr "$OUT" || true
codesign --force --deep --sign - --entitlements "$ENT" "$OUT"
codesign --verify --deep --strict "$OUT"
echo "Built $OUT"
