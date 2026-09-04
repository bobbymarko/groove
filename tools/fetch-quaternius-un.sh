#!/usr/bin/env bash
# Fetches Quaternius's Ultimate Nature Pack ("150+ LowPoly Nature Models", CC0) from
# itch.io and copies the named models (OBJ + MTL) into assets/quaternius/un/.
#
#   tools/fetch-quaternius-un.sh                  # list available models
#   tools/fetch-quaternius-un.sh Cactus_1 PalmTree_2 ...
#
# The zip is cached in build/quaternius/UltimateNature.zip. The download uses the
# same free-download handshake the itch.io page performs in the browser.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/build/quaternius"; ZIP="$CACHE/UltimateNature.zip"; DIR="$CACHE/un"
GAME="https://quaternius.itch.io/150-lowpoly-nature-models"
mkdir -p "$CACHE" && touch "$ROOT/build/.gdignore"
if [ ! -f "$ZIP" ]; then
  echo "Downloading Ultimate Nature Pack (≈22 MB, CC0) …"
  C="$CACHE/itch.cookies"; PAGE=$(curl -sL -c "$C" -b "$C" "$GAME")
  CSRF=$(echo "$PAGE" | grep -oE 'csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//; s/"$//')
  UPLOAD=$(echo "$PAGE" | grep -oE 'Ultimate Nature Pack by Quaternius\.zip' >/dev/null && echo 1588309)
  URL=$(curl -sL -b "$C" -c "$C" -X POST "$GAME/file/$UPLOAD?source=view_game&as_props=1" --data-urlencode "csrf_token=$CSRF" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
  curl -sL -o "$ZIP" "$URL"
fi
if [ ! -d "$DIR/OBJ" ]; then rm -rf "$DIR" && mkdir -p "$DIR" && (cd "$DIR" && unzip -q "$ZIP"); fi
if [ $# -eq 0 ]; then
  echo "Available models:"; ls "$DIR/OBJ" | grep '\.obj$' | sed 's/\.obj$//' | column -c 120; exit 0
fi
OUT="$ROOT/assets/quaternius/un"; mkdir -p "$OUT"
cp "$DIR/License.txt" "$OUT/LICENSE.txt"
for n in "$@"; do
  [ -f "$DIR/OBJ/$n.obj" ] || { echo "no such model: $n"; continue; }
  cp "$DIR/OBJ/$n.obj" "$DIR/OBJ/$n.mtl" "$OUT/"
  echo "imported $n"
done
