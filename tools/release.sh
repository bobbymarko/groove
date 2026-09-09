#!/usr/bin/env bash
# Export the macOS and Windows builds and zip them with the version number.
#   tools/release.sh 0.0.2
# Needs the Godot 4.7.2 export templates and the GDBLE libraries for both
# platforms in addons/gdble (see docs/dev-setup.md). Upload with:
#   gh release create v<version> build/Groove-<version>-macos.zip build/Groove-<version>-windows-x86_64.zip
set -euo pipefail
VERSION="${1:?usage: tools/release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT"
grep -q "application/version=\"$VERSION\"" export_presets.cfg || { echo "export_presets.cfg is not at version $VERSION"; exit 1; }
ls addons/gdble/*.dylib >/dev/null 2>&1 || { echo "missing macOS GDBLE library"; exit 1; }
ls addons/gdble/*.dll >/dev/null 2>&1 || { echo "missing Windows GDBLE library"; exit 1; }
rm -rf build/Groove-macos.zip build/Groove-windows
mkdir -p build/Groove-windows
"$GODOT" --headless --path "$ROOT" --import > build/import.log 2>&1 || true
"$GODOT" --headless --path "$ROOT" --export-release "macOS" build/Groove-macos.zip > build/export-macos.log 2>&1
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" build/Groove-windows/Groove.exe > build/export-windows.log 2>&1
grep -iE "error|failed" build/export-macos.log build/export-windows.log && { echo "export reported errors, see build/export-*.log"; exit 1; } || true
mv build/Groove-macos.zip "build/Groove-$VERSION-macos.zip"
rm -f "build/Groove-$VERSION-windows-x86_64.zip"
(cd build/Groove-windows && zip -qr "../Groove-$VERSION-windows-x86_64.zip" .)
ls -la "build/Groove-$VERSION-macos.zip" "build/Groove-$VERSION-windows-x86_64.zip"
