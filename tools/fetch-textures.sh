#!/usr/bin/env bash
# Fetches the photo-scanned CC0 PBR texture sets used by the Realistic look (R43) at 1K and
# writes them to assets/textures/<slot>/ as
#   albedo.jpg   sRGB colour
#   normal.jpg   tangent-space normal, OpenGL convention (Y+), as Godot expects
#   arm.jpg      R = ambient occlusion, G = roughness, B = metallic
#   height.jpg   displacement, single channel, 512 px on the long side
# Sources: Poly Haven (polyhaven.com) and ambientCG (ambientcg.com), both CC0.
#
#   tools/fetch-textures.sh            # fetch and convert everything missing
#   tools/fetch-textures.sh --force    # redo the conversion even if the outputs exist
#
# Raw downloads are cached in build/textures/ (git-ignored), so repeat runs are instant and
# offline. Channel packing and JPG encoding use a small Swift helper (ImageIO) that is compiled
# once into build/textures/bin/; it needs the Xcode command line tools, which this project has.
# Downloaded archives are treated as data: unzipped into fresh directories, never executed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"
CACHE="$ROOT/build/textures"
OUT="$ROOT/assets/textures"
UA="groove-fetch-textures/1.0"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
mkdir -p "$CACHE/bin" "$OUT"

# slot | source | asset id   (the chosen set for each slot; see assets/textures/README.md)
SETS=(
  "trail_gravel|polyhaven|rocky_trail"
  "trail_mud|polyhaven|forest_ground_06"
  "forest_floor|polyhaven|forest_leaves_04"
  "grass_ground|polyhaven|grass_ground"
  "rock_cliff|ambientcg|Rock032"
  "rock_mossy|ambientcg|Rock011"
  "snow|ambientcg|Snow001"
  "snow_trail|ambientcg|Snow013"
  "sand|polyhaven|dense_sand"
  "desert_gravel|polyhaven|gravelly_sand"
  "bark_pine|ambientcg|Bark004"
  "bark_oak|ambientcg|Bark001"
  "bark_birch|ambientcg|Bark007"
  "wood_planks|polyhaven|weathered_brown_planks"
)

JPG_Q=0.90   # albedo
MAP_Q=0.85   # normal, arm
HGT_Q=0.85   # height
HGT_PX=512

# ---- the Swift helper: re-encode, pack, shrink -------------------------------------------
TEX="$CACHE/bin/tex"
if [ ! -x "$TEX" ] || [ "$0" -nt "$TEX" ]; then
  cat > "$CACHE/bin/tex.swift" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// tex color  in out q            re-encode as sRGB JPG
// tex data   in out q            re-encode as JPG without colour management (normal, arm)
// tex gray   in out q px         single-channel JPG, long side scaled to px
// tex pack   out q ao rough      R=ao G=rough B=0 (non-metal); "-" for ao means white
func load(_ p: String) -> CGImage {
  guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
        let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { fputs("cannot read \(p)\n", stderr); exit(1) }
  return i
}
func rgba(_ im: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
  var d = [UInt8](repeating: 0, count: w * h * 4)
  let cs = CGColorSpace(name: CGColorSpace.sRGB)!
  let c = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  c.interpolationQuality = .high
  c.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h))
  return d
}
func save(_ im: CGImage, _ p: String, _ q: Double) {
  let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: p) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(d, im, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
  if !CGImageDestinationFinalize(d) { fputs("cannot write \(p)\n", stderr); exit(1) }
}
func fromRGBA(_ d: [UInt8], _ w: Int, _ h: Int) -> CGImage {
  var d = d
  let cs = CGColorSpace(name: CGColorSpace.sRGB)!
  let c = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  return c.makeImage()!
}
let a = CommandLine.arguments
switch a[1] {
case "color", "data":
  let im = load(a[2])
  save(fromRGBA(rgba(im, im.width, im.height), im.width, im.height), a[3], Double(a[4])!)
case "gray":
  let im = load(a[2]); let px = Int(a[5])!
  let k = Double(px) / Double(max(im.width, im.height))   // long side becomes px, aspect kept
  let w = max(1, Int((Double(im.width) * k).rounded())), h = max(1, Int((Double(im.height) * k).rounded()))
  var d = [UInt8](repeating: 0, count: w * h)
  let c = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  c.interpolationQuality = .high
  c.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h))
  save(c.makeImage()!, a[3], Double(a[4])!)
case "pack":
  let rough = load(a[5]); let w = rough.width, h = rough.height
  let r = rgba(rough, w, h)
  var ao = [UInt8](repeating: 255, count: w * h * 4)
  if a[4] != "-" { ao = rgba(load(a[4]), w, h) }
  var o = [UInt8](repeating: 0, count: w * h * 4)
  for i in 0..<(w * h) {
    o[i * 4] = ao[i * 4]; o[i * 4 + 1] = r[i * 4]; o[i * 4 + 2] = 0; o[i * 4 + 3] = 255
  }
  save(fromRGBA(o, w, h), a[2], Double(a[3])!)
default:
  fputs("unknown command\n", stderr); exit(1)
}
SWIFT
  swiftc -O "$CACHE/bin/tex.swift" -o "$TEX" 2>&1 | grep -v warning || true
fi

dl() {  # dl url dest [md5]
  local url="$1" dest="$2" md5="${3:-}"
  if [ -s "$dest" ]; then return; fi
  mkdir -p "$(dirname "$dest")"
  curl -sL -A "$UA" -o "$dest.part" "$url"
  if [ ! -s "$dest.part" ]; then echo "download failed: $url" >&2; rm -f "$dest.part"; exit 1; fi
  if [ -n "$md5" ] && [ "$(md5 -q "$dest.part")" != "$md5" ]; then
    echo "checksum mismatch: $url" >&2; rm -f "$dest.part"; exit 1
  fi
  mv "$dest.part" "$dest"
}

# Each fetcher leaves the raw 1K files in $CACHE/<source>/<id>/ (color, nor, disp, and arm or rough + ao).
fetch_polyhaven() {  # id  -> raw/{color,nor,arm,disp}.jpg
  local id="$1" d="$CACHE/polyhaven/$1"
  mkdir -p "$d"
  dl "https://api.polyhaven.com/files/$id" "$d/files.json"
  dl "https://api.polyhaven.com/info/$id" "$d/info.json"
  local m k
  for m in "color:Diffuse" "nor:nor_gl" "arm:arm" "disp:Displacement"; do
    k="${m#*:}"
    local url md5
    url="$(jq -r --arg k "$k" '.[$k]["1k"].jpg.url' "$d/files.json")"
    md5="$(jq -r --arg k "$k" '.[$k]["1k"].jpg.md5' "$d/files.json")"
    dl "$url" "$d/${m%%:*}.jpg" "$md5"
  done
}

fetch_ambientcg() {  # id -> raw/{color,nor,rough,disp}.jpg and ao.jpg when the set has one
  local id="$1" d="$CACHE/ambientcg/$1"
  mkdir -p "$d"
  dl "https://ambientcg.com/get?file=${id}_1K-JPG.zip" "$d/$id.zip"
  if [ ! -s "$d/color.jpg" ]; then
    unzip -tq "$d/$id.zip" >/dev/null || { echo "$id: not a valid zip" >&2; rm -f "$d/$id.zip"; exit 1; }
    local x; x="$(mktemp -d "$CACHE/unzip.XXXXXX")"
    unzip -q -o -j "$d/$id.zip" "*_Color.jpg" "*_NormalGL.jpg" "*_Roughness.jpg" "*_Displacement.jpg" "*_AmbientOcclusion.jpg" -d "$x" || true   # some sets have no AO map (exit 11)
    mv "$x/${id}_1K-JPG_Color.jpg" "$d/color.jpg"
    mv "$x/${id}_1K-JPG_NormalGL.jpg" "$d/nor.jpg"
    mv "$x/${id}_1K-JPG_Roughness.jpg" "$d/rough.jpg"
    mv "$x/${id}_1K-JPG_Displacement.jpg" "$d/disp.jpg"
    [ -f "$x/${id}_1K-JPG_AmbientOcclusion.jpg" ] && mv "$x/${id}_1K-JPG_AmbientOcclusion.jpg" "$d/ao.jpg"
    rm -rf "$x"
  fi
}

for entry in "${SETS[@]}"; do
  IFS='|' read -r slot source id <<< "$entry"
  dest="$OUT/$slot"
  if [ "$FORCE" = 0 ] && [ -s "$dest/albedo.jpg" ] && [ -s "$dest/normal.jpg" ] && [ -s "$dest/arm.jpg" ] && [ -s "$dest/height.jpg" ]; then
    continue
  fi
  echo "$slot  <-  $source/$id"
  mkdir -p "$dest"
  if [ "$source" = polyhaven ]; then
    fetch_polyhaven "$id"; raw="$CACHE/polyhaven/$id"
    "$TEX" data "$raw/arm.jpg" "$dest/arm.jpg" "$MAP_Q"
  else
    fetch_ambientcg "$id"; raw="$CACHE/ambientcg/$id"
    ao="-"; [ -f "$raw/ao.jpg" ] && ao="$raw/ao.jpg"
    "$TEX" pack "$dest/arm.jpg" "$MAP_Q" "$ao" "$raw/rough.jpg"
  fi
  "$TEX" color "$raw/color.jpg" "$dest/albedo.jpg" "$JPG_Q"
  "$TEX" data "$raw/nor.jpg" "$dest/normal.jpg" "$MAP_Q"
  "$TEX" gray "$raw/disp.jpg" "$dest/height.jpg" "$HGT_Q" "$HGT_PX"
done
echo "Textures in $OUT: $(du -sh "$OUT" | cut -f1)"
