#!/usr/bin/env python3
"""Import a Quaternius Universal Base Character (glTF for Godot) into
assets/character/: copies the mesh, keeps only base-colour textures (our cel
shader paints the body and ignores normal/roughness maps), shrinks them to
1024 px, and writes the CC0 note.

  tools/import_character.py "<pack>/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
"""
import json, os, shutil, subprocess, sys

src = sys.argv[1]
src_dir = os.path.dirname(src)
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out_dir = os.path.join(root, "assets", "character")
os.makedirs(out_dir, exist_ok=True)
j = json.load(open(src))
# Keep base colour textures only.
keep = set()
for m in j.get("materials", []):
    m.pop("normalTexture", None)
    pbr = m.get("pbrMetallicRoughness", {})
    pbr.pop("metallicRoughnessTexture", None)
    if "baseColorTexture" in pbr:
        keep.add(pbr["baseColorTexture"]["index"])
old_textures = j.get("textures", [])
old_images = j.get("images", [])
new_textures, new_images, tex_map, img_map = [], [], {}, {}
for ti in sorted(keep):
    t = old_textures[ti]
    si = t["source"]
    if si not in img_map:
        img_map[si] = len(new_images)
        new_images.append(old_images[si])
    tex_map[ti] = len(new_textures)
    new_textures.append({**t, "source": img_map[si]})
for m in j.get("materials", []):
    pbr = m.get("pbrMetallicRoughness", {})
    if "baseColorTexture" in pbr:
        pbr["baseColorTexture"]["index"] = tex_map[pbr["baseColorTexture"]["index"]]
j["textures"] = new_textures
j["images"] = new_images
name = os.path.splitext(os.path.basename(src))[0]
json.dump(j, open(os.path.join(out_dir, name + ".gltf"), "w"))
for b in j.get("buffers", []):
    if "uri" in b:
        shutil.copy(os.path.join(src_dir, b["uri"]), os.path.join(out_dir, b["uri"]))
for im in new_images:
    s = os.path.join(src_dir, im["uri"]); d = os.path.join(out_dir, im["uri"])
    subprocess.run(["sips", "-Z", "1024", s, "--out", d], check=True, capture_output=True)
open(os.path.join(out_dir, "ATTRIBUTION.txt"), "w").write(
    "Universal Base Characters by Quaternius (https://quaternius.com), Standard tier.\n"
    "Licence: CC0 1.0. Imported with tools/import_character.py: base-colour textures only, shrunk to 1024 px.\n")
print("imported", name, "textures:", [im["uri"] for im in new_images])
