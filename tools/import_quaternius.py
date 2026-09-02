#!/usr/bin/env python3
"""Copy Quaternius glTF models into the project with texture references removed.

usage: import_quaternius.py <kit glTF dir> <dest dir> <ModelName> [ModelName ...]
"""
import json, os, shutil, sys

src, dst, names = sys.argv[1], sys.argv[2], sys.argv[3:]
os.makedirs(dst, exist_ok=True)
for n in names:
    path = os.path.join(src, f"{n}.gltf")
    if not os.path.exists(path):
        print(f"skip {n}: not in kit"); continue
    g = json.load(open(path))
    for k in ("images", "textures", "samplers"):
        g.pop(k, None)
    for m in g.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for k in ("baseColorTexture", "metallicRoughnessTexture"):
            pbr.pop(k, None)
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
    json.dump(g, open(os.path.join(dst, f"{n}.gltf"), "w"))
    for b in g.get("buffers", []):
        uri = b.get("uri")
        if uri:
            shutil.copy(os.path.join(src, uri), os.path.join(dst, uri))
    mats = [m.get("name") for m in g.get("materials", [])]
    print(f"imported {n} materials={mats}")
print("Material names map to palette colours in scene/world/mesh_lib.gd::palette_for_material")
