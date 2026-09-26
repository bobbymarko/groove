"""Builds camp/art/models/camp.glb: the van, campfire, chairs, signpost,
trading post and small props.

Blender axes: +X forward, +Z up, the camera side is -Y. The van's sliding
door and every sign face the camera side.
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa

OUT = os.path.join(os.path.dirname(__file__), "..", "models", "camp.glb")
reset()


def vbox(p, x0, x1, y0, y1, z0, z1, role, bevel=0.0):
    b = box(x1 - x0, y1 - y0, z1 - z0, bevel=bevel)
    move(b, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    p.add(b, role)


def wedge(p, pts, y0, y1, role):
    """Extrude a side profile (list of (x, z)) across y0..y1."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in pts]
    b = [bm.verts.new((x, y1, z)) for x, z in pts]
    n = len(pts)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.add(bm, role)


# ================================================================== van
L0, L1 = -2.15, 2.15
W = 0.95
FLOOR, BELT, ROOF = 0.50, 1.30, 2.05
D0, D1 = -0.35, 0.95            # sliding door opening along X
DT = 1.92                        # door top

p = Part("van")
# Lower body (paint), leaving the door opening on the camera side.
vbox(p, L0, 2.02, W - 0.07, W, FLOOR, BELT, "paint", 0.03)
vbox(p, L0, D0, -W, -W + 0.07, FLOOR, BELT, "paint", 0.03)
vbox(p, D1, 2.02, -W, -W + 0.07, FLOOR, BELT, "paint", 0.03)
vbox(p, D0, D1, -W, -W + 0.07, FLOOR, 0.62, "paint", 0.02)
vbox(p, L0, L0 + 0.07, -W, W, FLOOR, BELT, "paint", 0.03)
vbox(p, 1.96, 2.26, -W, W, FLOOR, BELT, "paint", 0.06)        # the stubby nose
# Upper body (cream).
vbox(p, L0, 2.02, W - 0.07, W, BELT, ROOF, "paint2", 0.03)
vbox(p, L0, D0, -W, -W + 0.07, BELT, ROOF, "paint2", 0.03)
vbox(p, D1, 2.02, -W, -W + 0.07, BELT, ROOF, "paint2", 0.03)
vbox(p, D0, D1, -W, -W + 0.07, DT, ROOF, "paint2", 0.02)
vbox(p, L0, L0 + 0.07, -W, W, BELT, ROOF, "paint2", 0.03)
# Front: a gently raked windscreen frame.
wedge(p, [(1.95, BELT), (2.10, BELT), (1.98, ROOF), (1.90, ROOF)], -W, W, "paint2")
vbox(p, L0 - 0.02, 2.02, -W - 0.01, W + 0.01, ROOF - 0.04, ROOF + 0.06, "paint2", 0.05)   # roof
vbox(p, -2.08, 2.0, -W + 0.06, W - 0.06, FLOOR - 0.04, FLOOR + 0.08, "wood")            # floor
# Belt-line trim, split around the door.
for x0, x1 in ((L0, D0), (D1, 2.02)):
    vbox(p, x0, x1, -W - 0.012, -W + 0.02, BELT - 0.025, BELT + 0.025, "trim")
vbox(p, L0, 2.02, W - 0.02, W + 0.012, BELT - 0.025, BELT + 0.025, "trim")
# Windows.
for y, s in ((-W - 0.008, -1), (W + 0.008, 1)):
    vbox(p, -1.98, -0.55, y - 0.006, y + 0.006, 1.42, 1.90, "glass", 0.02)
    vbox(p, 1.12, 1.86, y - 0.006, y + 0.006, 1.42, 1.90, "glass", 0.02)
vbox(p, 1.13, 1.85, W - 0.01, W + 0.02, 1.42, 1.90, "glass")
vbox(p, L0 - 0.01, L0 + 0.005, -0.7, 0.7, 1.45, 1.90, "glass", 0.02)
for y0, y1 in ((-0.84, -0.04), (0.04, 0.84)):
    wedge(p, [(2.035, 1.40), (2.075, 1.40), (1.975, 1.96), (1.945, 1.96)], y0, y1, "glass")
# Nose: headlamps, grille, the pine badge, bumpers, mirrors.
for y in (-0.62, 0.62):
    ring = prism(0.15, 0.15, 0.05, 12)
    rotate(ring, 'Y', 90)
    move(ring, 2.25, y, 0.98)
    p.add(ring, "chrome")
    lens = prism(0.115, 0.10, 0.03, 12)
    rotate(lens, 'Y', 90)
    move(lens, 2.29, y, 0.98)
    p.add(lens, "lamp")
for i in range(3):
    vbox(p, 2.25, 2.29, -0.32, 0.32, 0.72 + i * 0.1, 0.76 + i * 0.1, "trim")
badge = prism(0.13, 0.13, 0.03, 12)
rotate(badge, 'Y', 90)
move(badge, 2.26, 0, 1.15)
p.add(badge, "chrome")
tree = prism(0.08, 0.0, 0.16, 3)
move(tree, 2.29, 0, 1.07)
p.add(tree, "paint")
vbox(p, 2.24, 2.40, -1.0, 1.0, 0.45, 0.62, "trim", 0.03)
vbox(p, -2.32, -2.14, -1.0, 1.0, 0.45, 0.62, "trim", 0.03)
for y in (-1.02, 1.02):
    vbox(p, 1.88, 1.98, y - 0.05, y + 0.05, 1.52, 1.70, "trim", 0.015)
# Wheels and arches.
for x in (-1.42, 1.38):
    for y in (-0.88, 0.88):
        t = torus(0.27, 0.12, 16, 6)
        move(t, x, y, 0.39)
        p.add(t, "tyre")
        hub = prism(0.16, 0.15, 0.20, 8)
        rotate(hub, 'X', 90)
        move(hub, x, y + (0.10 if y > 0 else -0.10), 0.39)
        p.add(hub, "paint2")
        cap = prism(0.05, 0.04, 0.215, 6)
        rotate(cap, 'X', 90)
        move(cap, x, y + (0.107 if y > 0 else -0.107), 0.39)
        p.add(cap, "chrome")
    for y in (-W - 0.004, W + 0.004):
        vbox(p, x - 0.46, x + 0.46, y - 0.006, y + 0.006, FLOOR - 0.02, 0.84, "trim")
# Pop-top: roof panel hinged at the front, canvas wedge beneath.
pop = box(2.85, 1.86, 0.07, bevel=0.025)
move(pop, -1.425, 0, 0)
pm = Matrix.Translation((0.70, 0, ROOF + 0.10)) @ Matrix.Rotation(math.radians(11), 4, 'Y')
p.add(pop, "paint2", pm)
wedge(p, [(0.70, ROOF + 0.06), (-2.12, ROOF + 0.06), (-2.12, ROOF + 0.60)], -0.86, 0.86, "canvas")
flap = box(0.9, 0.02, 0.22, bevel=0.01)
move(flap, -1.3, -0.875, ROOF + 0.26)
p.add(flap, "trim")
# Roof rack over the cab with two crates.
for y in (-0.8, 0.8):
    vbox(p, 0.85, 1.92, y - 0.03, y + 0.03, ROOF + 0.12, ROOF + 0.16, "trim")
for x in (0.9, 1.4, 1.88):
    vbox(p, x - 0.03, x + 0.03, -0.83, 0.83, ROOF + 0.10, ROOF + 0.14, "trim")
vbox(p, 0.95, 1.40, -0.72, -0.08, ROOF + 0.16, ROOF + 0.48, "box1", 0.03)
vbox(p, 1.45, 1.85, 0.02, 0.62, ROOF + 0.16, ROOF + 0.44, "box2", 0.03)
# Ladder and spare wheel on the back.
for y in (0.45, 0.80):
    vbox(p, L0 - 0.10, L0 - 0.06, y - 0.02, y + 0.02, 0.65, ROOF + 0.1, "trim")
for i in range(6):
    vbox(p, L0 - 0.10, L0 - 0.06, 0.45, 0.80, 0.75 + i * 0.22, 0.78 + i * 0.22, "trim")
spare = torus(0.24, 0.10, 14, 6)
rotate(spare, 'Z', 90)
move(spare, L0 - 0.13, -0.38, 1.05)
p.add(spare, "tyre")
# Sliding door, parked open along the back half.
vbox(p, D0 - 1.26, D0 + 0.02, -W - 0.09, -W - 0.03, 0.62, BELT, "paint", 0.02)
vbox(p, D0 - 1.26, D0 + 0.02, -W - 0.09, -W - 0.03, BELT, DT, "paint2", 0.02)
vbox(p, D0 - 1.1, D0 - 0.15, -W - 0.10, -W - 0.09, 1.42, 1.85, "glass", 0.02)
# Interior, seen through the door.
vbox(p, -2.06, 1.9, W - 0.12, W - 0.07, FLOOR, ROOF - 0.05, "wood")
vbox(p, -2.06, 1.9, -W + 0.07, W - 0.07, ROOF - 0.09, ROOF - 0.05, "wood")
vbox(p, -1.95, 0.70, -0.25, W - 0.12, FLOOR, 0.95, "wood_dark", 0.02)
vbox(p, -1.93, 0.68, -0.23, W - 0.13, 0.95, 1.08, "blanket2", 0.03)
vbox(p, -0.9, 0.62, -0.26, W - 0.12, 1.06, 1.12, "blanket", 0.025)
for i in range(3):
    vbox(p, -0.75 + i * 0.45, -0.62 + i * 0.45, -0.27, W - 0.11, 1.08, 1.125, "blanket2")
vbox(p, 0.30, 0.62, 0.35, 0.78, 1.08, 1.22, "blanket2", 0.04)
vbox(p, 0.05, 0.55, W - 0.14, W - 0.12, 1.36, 1.72, "wood_dark", 0.01)
wedge(p, [(0.10, 1.40), (0.50, 1.40), (0.30, 1.66)], W - 0.155, W - 0.14, "mountain")
vbox(p, 1.2, 1.9, -0.8, -0.2, FLOOR, 1.05, "trim", 0.05)        # cab seats
vbox(p, 1.2, 1.9, 0.2, 0.8, FLOOR, 1.05, "trim", 0.05)
lamp = prism(0.07, 0.06, 0.16, 6)
move(lamp, 0.25, 0.25, 1.62)
p.add(lamp, "lamp")
lcap = prism(0.08, 0.02, 0.06, 6)
move(lcap, 0.25, 0.25, 1.78)
p.add(lcap, "trim")
vbox(p, 0.245, 0.255, 0.245, 0.255, 1.84, ROOF - 0.09, "trim")
vbox(p, -0.30, 0.05, W - 0.35, W - 0.12, 1.30, 1.34, "wood_dark")   # shelf with a plant
pot = prism(0.06, 0.08, 0.1, 6)
move(pot, -0.12, W - 0.24, 1.34)
p.add(pot, "box2")
leaves = ico(0.10, 1)
radial_jitter(leaves, 0.25, 90)
move(leaves, -0.12, W - 0.24, 1.52)
p.add(leaves, "leaf")
p.socket("door", ((D0 + D1) / 2, -W - 0.6, 0))
p.socket("lamp", (0.25, 0.25, 1.60))
p.build()

# ================================================================== campfire
p = Part("fire_ring")
rng = random.Random(3)
for i in range(9):
    a = 2 * math.pi * i / 9 + rng.uniform(-.1, .1)
    s = ico(0.16, 1)
    radial_jitter(s, 0.25, 100 + i)
    scale(s, 1.2, 1.0, 0.75)
    move(s, math.cos(a) * 0.62, math.sin(a) * 0.62, 0.08)
    p.add(s, "stone")
for i in range(4):
    a = math.radians(i * 90 + 20)
    log = prism(0.07, 0.06, 0.62, 6)
    m = Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation((0.26, 0, 0.0)) @ Matrix.Rotation(math.radians(-60), 4, 'Y')
    p.add(log, "bark", m)
for i in range(7):
    e = ico(0.06, 1)
    radial_jitter(e, 0.3, 120 + i)
    move(e, rng.uniform(-.22, .22), rng.uniform(-.22, .22), 0.04)
    p.add(e, "ember")
p.build()

for name, role, r, h, tw in (("flame_outer", "flame", 0.30, 0.95, 40), ("flame_mid", "flame2", 0.20, 0.70, -30),
                              ("flame_core", "flame3", 0.10, 0.42, 20)):
    p = Part(name)
    bm = bmesh.new()
    rings = [(r, 0.05), (r * 0.8, h * 0.35), (r * 0.45, h * 0.7)]
    loops = []
    for i, (rr, z) in enumerate(rings):
        loops.append([bm.verts.new((rr * math.cos(2 * math.pi * k / 5 + math.radians(tw) * i),
                                    rr * math.sin(2 * math.pi * k / 5 + math.radians(tw) * i), z)) for k in range(5)])
    for a, b in zip(loops, loops[1:]):
        for k in range(5):
            bm.faces.new((a[k], a[(k + 1) % 5], b[(k + 1) % 5], b[k]))
    bm.faces.new(list(reversed(loops[0])))
    top = bm.verts.new((0.03, 0.02, h))
    for k in range(5):
        bm.faces.new((loops[-1][k], loops[-1][(k + 1) % 5], top))
    p.add(bm, role)
    p.build()

# ================================================================== furniture
p = Part("camp_chair")                # seat top at z 0.46, facing +X
for y in (-0.26, 0.26):
    p.add(tube((-0.22, y, 0.0), (0.22, y, 0.44), 0.018, 0.018, 5), "trim")
    p.add(tube((0.22, y, 0.0), (-0.22, y, 0.44), 0.018, 0.018, 5), "trim")
    p.add(tube((-0.24, y, 0.44), (-0.34, y, 0.95), 0.018, 0.018, 5), "trim")
    vbox(p, -0.16, 0.22, y - 0.03, y + 0.03, 0.62, 0.66, "wood")      # armrests
    p.add(tube((0.18, y, 0.44), (0.18, y, 0.64), 0.016, 0.016, 5), "trim")
seat = box(0.46, 0.52, 0.03)
move(seat, 0.0, 0, 0.45)
p.add(seat, "canvas")
back = box(0.03, 0.52, 0.46)
p.add(back, "canvas", Matrix.Translation((-0.29, 0, 0.72)) @ Matrix.Rotation(math.radians(-11), 4, 'Y'))
for i, y in enumerate((-0.17, 0.0, 0.17)):
    st = box(0.035, 0.07, 0.46)
    p.add(st, "blanket2" if i != 1 else "blanket", Matrix.Translation((-0.308, y, 0.72)) @ Matrix.Rotation(math.radians(-11), 4, 'Y'))
p.build()

p = Part("mug")
p.add(prism(0.05, 0.045, 0.11, 8), "mug")
h = torus(0.03, 0.01, 8, 4)
rotate(h, 'X', 90)
move(h, 0.0, -0.055, 0.055)
p.add(h, "mug")
t = prism(0.025, 0.0, 0.05, 3)
rotate(t, 'X', 90)
move(t, 0.0, -0.035, 0.03)
p.add(t, "paint")
p.build()

p = Part("lantern")
p.add(prism(0.09, 0.09, 0.03, 6), "trim")
g = prism(0.07, 0.07, 0.16, 6)
move(g, 0, 0, 0.03)
p.add(g, "lamp")
c = prism(0.10, 0.03, 0.07, 6)
move(c, 0, 0, 0.19)
p.add(c, "trim")
hh = torus(0.06, 0.008, 8, 4)
move(hh, 0, 0, 0.28)
p.add(hh, "trim")
p.build()

p = Part("log_bench")
lg = prism(0.17, 0.17, 1.4, 7)
rotate(lg, 'Y', 90)
move(lg, -0.7, 0, 0.16)
for v in lg.verts:
    v.co.z = min(v.co.z, 0.28)
p.add(lg, "bark")
for x in (-0.7, 0.7):
    e = prism(0.15, 0.15, 0.01, 7)
    rotate(e, 'Y', 90)
    move(e, x + (0.005 if x > 0 else -0.005), 0, 0.16)
    for v in e.verts:
        v.co.z = min(v.co.z, 0.28)
    p.add(e, "wood")
p.build()

# ================================================================== signpost
# Boards list the events this rider is training for. Text is added in Godot
# at the board sockets, facing the camera side.
p = Part("signpost")
p.add(prism(0.07, 0.06, 2.3, 6), "wood_dark")
for i, (z, d) in enumerate(((1.95, 1), (1.62, -1), (1.29, 1))):
    b = box(0.95, 0.06, 0.24, bevel=0.015)
    move(b, d * 0.42, -0.05, z)
    p.add(b, "wood")
    tri = bmesh.new()
    tv = [tri.verts.new((d * 0.895, -0.08, z + 0.12)), tri.verts.new((d * 0.895, -0.08, z - 0.12)),
          tri.verts.new((d * 1.03, -0.08, z)), tri.verts.new((d * 0.895, -0.02, z + 0.12)),
          tri.verts.new((d * 0.895, -0.02, z - 0.12)), tri.verts.new((d * 1.03, -0.02, z))]
    tri.faces.new((tv[0], tv[1], tv[2]))
    tri.faces.new((tv[5], tv[4], tv[3]))
    tri.faces.new((tv[0], tv[2], tv[5], tv[3]))
    tri.faces.new((tv[1], tv[4], tv[5], tv[2]))
    tri.faces.new((tv[0], tv[3], tv[4], tv[1]))
    bmesh.ops.recalc_face_normals(tri, faces=tri.faces)
    p.add(tri, "wood")
    p.socket("board_%d" % i, (d * 0.42, -0.085, z))
p.build()

# ================================================================== trading post
# Counter along X facing the camera side; the trader stands behind it (+Y).
p = Part("trading_post")
vbox(p, -1.0, 1.0, -0.45, 0.0, 0.0, 0.98, "wood", 0.02)
vbox(p, -1.08, 1.08, -0.52, 0.06, 0.98, 1.06, "wood_dark", 0.02)
for i in range(6):
    vbox(p, -0.98 + i * 0.4, -0.96 + i * 0.4, -0.465, -0.45, 0.05, 0.95, "wood_dark")
for x in (-1.15, 1.15):
    for y in (-0.55, 1.05):
        p.add(prism(0.05, 0.05, 2.72 if y > 0 else 2.42, 6), "wood_dark", Matrix.Translation((x, y, 0)))
# Striped awning, sloping toward the front.
for i in range(8):
    x0 = -1.25 + i * 0.3125
    role = "blanket" if i % 2 == 0 else "blanket2"
    strip = box(0.3125, 1.9, 0.05)
    m = (Matrix.Translation((x0 + 0.156, 0.25, 2.59)) @ Matrix.Rotation(math.radians(9), 4, 'X'))
    p.add(strip, role, m)
    val = prism(0.156, 0.0, 0.16, 3)
    rotate(val, 'X', 180)
    rotate(val, 'Z', 90)
    move(val, x0 + 0.156, -0.70, 2.45)
    p.add(val, role)
# Back shelves with jam.
vbox(p, -1.1, 1.1, 0.95, 1.10, 0.0, 2.0, "wood", 0.02)
for z in (0.9, 1.35):
    vbox(p, -1.05, 1.05, 0.75, 1.0, z, z + 0.04, "wood")
    for i in range(9):
        x = -0.9 + i * 0.225
        jar = prism(0.065, 0.065, 0.14, 7)
        move(jar, x, 0.87, z + 0.04)
        p.add(jar, "jam" if (i + int(z * 10)) % 3 else "berry")
        lid = prism(0.07, 0.07, 0.03, 7)
        move(lid, x, 0.87, z + 0.18)
        p.add(lid, "box2")
for x in (-0.7, 0.55):              # jars on the counter
    jar = prism(0.08, 0.08, 0.17, 7)
    move(jar, x, -0.25, 1.06)
    p.add(jar, "jam")
    lid = prism(0.085, 0.085, 0.035, 7)
    move(lid, x, -0.25, 1.23)
    p.add(lid, "blanket")
p.socket("sign", (0.0, -0.66, 2.73))
p.socket("trader", (0.0, 0.45, 0.0))
p.socket("counter", (0.0, -0.05, 1.06))
p.build()

p = Part("crate_berries")
vbox(p, -0.3, 0.3, -0.22, 0.22, 0.0, 0.3, "wood", 0.015)
for i in range(3):
    vbox(p, -0.31, 0.31, -0.225, 0.225, 0.04 + i * 0.1, 0.07 + i * 0.1, "wood_dark")
rng = random.Random(8)
for i in range(22):
    b = ico(0.05, 1)
    move(b, rng.uniform(-0.24, 0.24), rng.uniform(-0.17, 0.17), 0.3 + rng.uniform(0, 0.05))
    p.add(b, "berry")
p.build()

export_glb(os.path.abspath(OUT))
print("exported", os.path.abspath(OUT))
