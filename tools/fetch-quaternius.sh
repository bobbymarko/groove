#!/usr/bin/env bash
# Fetches Quaternius's Stylized Nature MegaKit (standard, CC0) and copies the named
# models into assets/quaternius with textures stripped (our palette shader colours them).
#
#   tools/fetch-quaternius.sh                 # list available models
#   tools/fetch-quaternius.sh Pine_1 Rock_Medium_2 CommonTree_3 ...
#
# The kit zip is cached in build/quaternius/ so repeat runs are instant.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"
CACHE="$ROOT/build/quaternius"
ZIP="$CACHE/Stylized_Nature_MegaKitStandard.zip"
URL="https://store.godotengine.org/asset/quaternius/stylized-nature-megakit/download/31/"
mkdir -p "$CACHE"
if [ ! -f "$ZIP" ]; then
  echo "Downloading Stylized Nature MegaKit (≈104 MB, CC0) …"
  curl -sL -o "$ZIP" "$URL"
fi
if [ ! -d "$CACHE/kit/glTF" ]; then
  rm -rf "$CACHE/kit" && mkdir -p "$CACHE/kit" && (cd "$CACHE/kit" && unzip -q "$ZIP")
fi
if [ $# -eq 0 ]; then
  echo "Available models:"; ls "$CACHE/kit/glTF" | grep '\.gltf$' | sed 's/\.gltf$//' | column -c 120
  exit 0
fi
python3 "$ROOT/tools/import_quaternius.py" "$CACHE/kit/glTF" "$ROOT/assets/quaternius" "$@"
