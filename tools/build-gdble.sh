#!/usr/bin/env bash
# Builds the GDBLE Bluetooth extension from source for this Mac and installs it
# into addons/gdble. Pinned to a known-good commit of the master branch, which
# (unlike the 0.5.5 release) reports radio-level disconnects.
#
# Requires: cargo (brew install rust), git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"   # keep Godot from scanning build/
GDBLE_REPO="${GDBLE_REPO:-https://github.com/Fantety/GDBLE.git}"
GDBLE_COMMIT="${GDBLE_COMMIT:-65f03b3}"
SRC="$ROOT/build/gdble-src"

if [ ! -d "$SRC/.git" ]; then
  git clone -q "$GDBLE_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q "$GDBLE_COMMIT"
(cd "$SRC" && cargo build --release --locked)

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)  DEST="libgdble.macos.arm64.dylib" ;;
  Darwin/x86_64) DEST="libgdble.macos.x86_64.dylib" ;;
  Linux/x86_64)  DEST="libgdble.linux.x86_64.so" ;;
  *) echo "Unsupported host: $(uname -s)/$(uname -m)"; exit 1 ;;
esac
SRC_LIB="$SRC/target/release/libgdble.dylib"
[ -f "$SRC_LIB" ] || SRC_LIB="$SRC/target/release/libgdble.so"
cp "$SRC_LIB" "$ROOT/addons/gdble/$DEST"
echo "Installed addons/gdble/$DEST from GDBLE $GDBLE_COMMIT ($(git -C "$SRC" log -1 --format=%cs))"
