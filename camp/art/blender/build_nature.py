"""Builds camp/art/models/nature.glb: trail and camp dressing.

Pines, rocks, a berry bush (the cheapest collectible), grass, stumps,
mountains and clouds. Origins sit on the ground.
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa

OUT = os.path.join(os.path.dirname(__file__), "..", "models", "nature.glb")
reset()


def lathe(rings, sides, seed, jit=0.0, apex=None, twist=0.0):
    """rings: list of (radius, z). Returns a closed low-poly solid of revolution."""
    rng = random.Random(seed)
    bm = bmesh.new()
    loops = []
    for i, (r, z) in enumerate(rings):
        loop = []
        for s in range(sides):
            a = 2 * math.pi * s / sides + twist * i
            rr = r * (1 + rng.uniform(-jit, jit))
            loop.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z + rng.uniform(-jit, jit) * r * 0.4)))
        loops.append(loop)
    for a, b in zip(loops, loops[1:]):
        for s in range(sides):
            bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
    bm.faces.new(list(reversed(loops[0])))
    if apex is not None:
        top = bm.verts.new(apex)
        last = loops[-1]
        for s in range(sides):
            bm.faces.new((last[s], last[(s + 1) % sides], top))
    else:
        bm.faces.new(loops[-1])
    return bm


def pine(name, seed, height, tiers):
    rng = random.Random(seed)
    p = Part(name)
    p.add(lathe([(0.10, 0), (0.08, height * 0.3)], 6, seed), "bark")
    z = height * 0.16
    step = (height - z) / tiers
    for t in range(tiers):
        r = (1.0 - t / tiers) * height * 0.30 + 0.12
        top = z + step * 1.9
        cone = lathe([(r, z), (r * 0.62, z + step * 0.45)], 7, seed + t, jit=0.12,
                     apex=(rng.uniform(-.04, .04), rng.uniform(-.04, .04), top), twist=0.3)
        for v in cone.verts:       # droop the skirt
            if abs(v.co.z - z) < 0.05:
                v.co.z -= 0.06 * r
        p.add(cone, "leaf" if t % 2 == 0 else "leaf_dark")
        z += step
    return p.build()


pine("pine_a", 1, 3.4, 4)
pine("pine_b", 2, 2.4, 3)
pine("pine_c", 3, 4.6, 5)


def rock(name, seed, sx, sy, sz):
    p = Part(name)
    bm = ico(0.5, 1)
    radial_jitter(bm, 0.22, seed)
    scale(bm, sx, sy, sz)
    move(bm, 0, 0, sz * 0.32)
    p.add(bm, "rock")
    return p.build()


rock("rock_a", 4, 1.0, 0.8, 0.6)
rock("rock_b", 5, 0.6, 0.5, 0.55)
rock("rock_c", 6, 1.8, 1.2, 0.9)

# Berry bush: the humblest haul.
p = Part("bush_berry")
rng = random.Random(8)
for i in range(5):
    b = ico(0.28 + rng.uniform(0, .1), 1)
    radial_jitter(b, 0.18, 30 + i)
    a = i * 1.3
    move(b, math.cos(a) * 0.22, math.sin(a) * 0.18, 0.28 + (0.12 if i == 0 else 0))
    p.add(b, "leaf" if i % 2 else "leaf_dark")
for i in range(12):
    a = rng.uniform(0, 2 * math.pi)
    z = rng.uniform(0.25, 0.6)
    r = 0.42 - (z - 0.25) * 0.4
    berry = ico(0.045, 1)
    move(berry, math.cos(a) * r, math.sin(a) * r * 0.8 - 0.05, z)
    p.add(berry, "berry")
p.build()

p = Part("grass")
rng = random.Random(9)
for i in range(6):
    a = rng.uniform(-0.5, 0.5)
    h = rng.uniform(0.18, 0.34)
    blade = lathe([(0.025, 0)], 3, i, apex=(math.sin(a) * h * 0.5, 0, h))
    move(blade, rng.uniform(-0.12, 0.12), rng.uniform(-0.06, 0.06), 0)
    p.add(blade, "grass")
p.build()

p = Part("stump")
p.add(lathe([(0.30, 0), (0.24, 0.12), (0.22, 0.34)], 8, 10, jit=0.06), "bark")
top = prism(0.205, 0.205, 0.02, 8)
move(top, 0, 0, 0.33)
p.add(top, "dirt")
p.build()


def mountain(name, seed, r, h, snow):
    p = Part(name)
    bm = lathe([(r, 0), (r * 0.72, h * 0.3), (r * 0.42, h * 0.62)], 9, seed, jit=0.14,
               apex=(r * 0.05, 0, h))
    top = bm.faces
    me_roles = []
    p.add(bm, "mountain")
    # Snow: re-tag the faces near the peak.
    snow_idx = p.slot("snow")
    p.bm.faces.ensure_lookup_table()
    for f in p.bm.faces:
        if f.calc_center_median().z > h * snow:
            f.material_index = snow_idx
    return p.build()


mountain("mountain_a", 11, 9.0, 8.0, 0.62)
mountain("mountain_b", 12, 7.0, 5.5, 0.70)
mountain("mountain_c", 13, 12.0, 10.0, 0.58)

p = Part("cloud")
rng = random.Random(14)
for i in range(4):
    c = ico(0.9 - i * 0.12, 1)
    radial_jitter(c, 0.12, 40 + i)
    scale(c, 1.3, 0.8, 0.55)
    move(c, i * 0.9 - 1.3, 0, (0.25 if i in (1, 2) else 0.0))
    p.add(c, "cloud")
p.build()

# ------------------------------------------------------------------ forage finds

p = Part("flower_patch")                # tempo and threshold plateaus
rng = random.Random(21)
for i in range(7):
    x, y = rng.uniform(-0.28, 0.28), rng.uniform(-0.2, 0.2)
    h = rng.uniform(0.22, 0.42)
    p.add(tube((x, y, 0), (x + rng.uniform(-.04, .04), y, h), 0.012, 0.009, 4), "grass")
    head = ico(0.055, 1)
    radial_jitter(head, 0.2, 200 + i)
    scale(head, 1.0, 1.0, 0.6)
    move(head, x, y, h + 0.02)
    p.add(head, "petal" if i % 3 else "petal2")
    eye = ico(0.022, 0)
    move(eye, x + 0.03, y - 0.03, h + 0.04)
    p.add(eye, "petal2" if i % 3 else "dirt")
leaves = ico(0.16, 1)
radial_jitter(leaves, 0.3, 230)
scale(leaves, 1.6, 1.2, 0.45)
move(leaves, 0, 0, 0.05)
p.add(leaves, "leaf")
p.build()

p = Part("rabbit")                      # faces +X, origin on the ground
body = ico(0.17, 1)
radial_jitter(body, 0.08, 240)
scale(body, 1.3, 0.85, 0.9)
move(body, 0, 0, 0.17)
p.add(body, "critter")
head = ico(0.11, 1)
radial_jitter(head, 0.08, 241)
move(head, 0.2, 0, 0.30)
p.add(head, "critter")
for y in (-0.045, 0.045):
    ear = prism(0.03, 0.012, 0.2, 5)
    scale(ear, 0.6, 1.0, 1.0)
    p.add(ear, "critter", Matrix.Translation((0.17, y, 0.36)) @ Matrix.Rotation(math.radians(-18), 4, 'Y'))
    eye = ico(0.018, 0)
    move(eye, 0.29, y * 1.1, 0.33)
    p.add(eye, "pupil")
tail = ico(0.06, 1)
move(tail, -0.22, 0, 0.22)
p.add(tail, "critter2")
for x in (-0.1, 0.12):
    for y in (-0.07, 0.07):
        foot = box(0.12 if x < 0 else 0.06, 0.05, 0.04, bevel=0.01)
        move(foot, x, y, 0.02)
        p.add(foot, "critter")
p.build()

p = Part("beehive")                     # max efforts: honey for watts
p.add(lathe([(0.25, 0), (0.30, 0.15), (0.27, 0.32), (0.18, 0.46), (0.06, 0.55)], 9, 250, jit=0.02), "hive")
for z in (0.12, 0.26, 0.40):
    r = 0.30 if z < 0.2 else (0.28 if z < 0.3 else 0.21)
    band = torus(r, 0.022, 12, 4)
    rotate(band, 'X', 90)
    move(band, 0, 0, z)
    p.add(band, "wood_dark")
door = prism(0.05, 0.05, 0.02, 7)
rotate(door, 'Y', 90)
move(door, 0.27, 0, 0.12)
p.add(door, "trim")
drip = ico(0.04, 1)
scale(drip, 1, 1, 1.5)
move(drip, 0.2, -0.12, 0.06)
p.add(drip, "honey")
p.build()

export_glb(os.path.abspath(OUT))
print("exported", os.path.abspath(OUT))
