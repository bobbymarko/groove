#!/usr/bin/env python3
"""Copy Quaternius glTF models into the project, keeping only base-colour textures
(downscaled to 512 px; the scene renders at 240 px so more is wasted bytes).

usage: import_quaternius.py <kit glTF dir> <dest dir> <ModelName> [ModelName ...]
"""
import json, os, shutil, subprocess, sys

src, dst, names = sys.argv[1], sys.argv[2], sys.argv[3:]
tex_dst = os.path.join(dst, "textures")
os.makedirs(tex_dst, exist_ok=True)

def import_texture(uri):
    out = os.path.join(tex_dst, os.path.basename(uri))
    if not os.path.exists(out):
        shutil.copy(os.path.join(src, uri), out)
        subprocess.run(["sips", "-Z", "512", out], check=True, capture_output=True)
    return "textures/" + os.path.basename(uri)

for n in names:
    path = os.path.join(src, f"{n}.gltf")
    if not os.path.exists(path):
        print(f"skip {n}: not in kit"); continue
    g = json.load(open(path))
    images = g.get("images", [])
    textures = g.get("textures", [])
    keep_images = {}
    for m in g.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        pbr.pop("metallicRoughnessTexture", None)
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
        bct = pbr.get("baseColorTexture")
        if bct is not None:
            img_index = textures[bct["index"]]["source"]
            keep_images[img_index] = images[img_index]["uri"]
    # Rewrite kept images to the downscaled copies; drop the rest.
    for idx, uri in keep_images.items():
        images[idx]["uri"] = import_texture(uri)
    used = set(keep_images)
    g["images"] = [images[i] if i in used else {"uri": "textures/unused.png"} for i in range(len(images))]
    json.dump(g, open(os.path.join(dst, f"{n}.gltf"), "w"))
    for b in g.get("buffers", []):
        if b.get("uri"):
            shutil.copy(os.path.join(src, b["uri"]), os.path.join(dst, b["uri"]))
    print(f"imported {n} materials={[m.get('name') for m in g.get('materials', [])]} textures={sorted(set(keep_images.values()))}")
