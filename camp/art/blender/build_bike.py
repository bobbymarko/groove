"""Builds camp/art/models/bike.glb: a chunky, made-up trail BMX.

Parts: frame (with sockets), fork, wheel, crank, pedal, saddle, seatpost.
Origin of the frame is the ground point under the bottom bracket.
"""
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa

OUT = os.path.join(os.path.dirname(__file__), "..", "models", "bike.glb")
reset()

BB = Vector((0.0, 0.0, 0.30))
REAR = Vector((-0.50, 0.0, 0.34))
FRONT = Vector((0.58, 0.0, 0.34))
SEAT = Vector((-0.13, 0.0, 0.70))      # top of the seat tube
HT_TOP = Vector((0.40, 0.0, 0.80))
HT_BOT = Vector((0.46, 0.0, 0.60))

# ---------------------------------------------------------------- frame
p = Part("frame")
p.add(tube(BB, SEAT + Vector((0.004, 0, 0.02)), 0.038, 0.034, 6), "frame")
p.add(tube(SEAT + Vector((0.02, 0, -0.03)), HT_TOP + Vector((0, 0, -0.03)), 0.036, 0.040, 6), "frame")
p.add(tube(BB, HT_BOT + Vector((0, 0, 0.03)), 0.050, 0.046, 6), "frame")
p.add(tube(HT_BOT + Vector((0.004, 0, -0.03)), HT_TOP + Vector((-0.004, 0, 0.03)), 0.050, 0.050, 8), "frame")
for y in (-0.065, 0.065):
    p.add(tube(BB + Vector((0, y * 0.6, 0)), REAR + Vector((0, y, 0)), 0.026, 0.022, 5), "frame")
    p.add(tube(SEAT + Vector((0.01, y * 0.5, -0.05)), REAR + Vector((0.01, y, 0.02)), 0.022, 0.020, 5), "frame")
    drop = box(0.07, 0.02, 0.07, bevel=0.01)
    move(drop, REAR.x, y, REAR.z)
    p.add(drop, "frame")
bbshell = prism(0.055, 0.055, 0.15, 8)
rotate(bbshell, 'X', 90)
move(bbshell, BB.x, 0.075, BB.z)
p.add(bbshell, "rim")
# Rear cog and the chain loop on the camera side.
cog = prism(0.05, 0.05, 0.012, 10)
rotate(cog, 'X', 90)
move(cog, REAR.x, -0.07, REAR.z)
p.add(cog, "chrome")
ring_r, cog_r = 0.105, 0.052
for (a, b, ra, rb) in ((BB, REAR, ring_r, cog_r),):
    d = (b - a)
    n = Vector((-d.z, 0, d.x)).normalized()
    for s in (1, -1):
        p.add(tube(a + n * ra * s + Vector((0, -0.08, 0)), b + n * rb * s + Vector((0, -0.075, 0)), 0.008, 0.008, 4), "dark")
# Number plate on the bars: pure BMX attitude.
plate = box(0.02, 0.24, 0.17, bevel=0.03)
move(plate, HT_TOP.x + 0.10, 0, HT_TOP.z + 0.05)
p.add(plate, "accent")
# Stem and riser bars.
stem_end = HT_TOP + Vector((0.07, 0, 0.05))
p.add(tube(HT_TOP + Vector((0, 0, 0.02)), stem_end, 0.032, 0.032, 6), "rim")
for s in (1, -1):
    rise = stem_end + Vector((-0.02, 0.13 * s, 0.10))
    grip = stem_end + Vector((-0.04, 0.33 * s, 0.12))
    p.add(tube(stem_end, rise, 0.018, 0.018, 6), "chrome")
    p.add(tube(rise, grip, 0.018, 0.018, 6), "chrome")
    p.add(tube(grip - Vector((0, 0.11 * s, 0)), grip + Vector((0, 0.01 * s, 0)), 0.027, 0.027, 6), "grip")
    p.socket("grip_" + ("l" if s > 0 else "r"), grip - Vector((0, 0.05 * s, 0)))
p.add(tube(stem_end + Vector((-0.02, -0.13, 0.10)), stem_end + Vector((-0.02, 0.13, 0.10)), 0.014, 0.014, 5), "chrome")
p.socket("bb", BB)
p.socket("seat", SEAT)
p.socket("axle_rear", REAR)
p.socket("axle_front", FRONT)
p.build()

# ---------------------------------------------------------------- fork
p = Part("fork")
crown = box(0.08, 0.20, 0.05, bevel=0.012)
move(crown, HT_BOT.x + 0.01, 0, HT_BOT.z - 0.04)
p.add(crown, "frame")
for y in (-0.08, 0.08):
    p.add(tube(HT_BOT + Vector((0.01, y, -0.05)), FRONT + Vector((0, y, 0)), 0.03, 0.022, 6), "frame")
p.build()

# ---------------------------------------------------------------- wheel
p = Part("wheel")
p.add(torus(0.28, 0.062, 18, 6), "tyre")
for i in range(22):                 # knobs
    a = 2 * math.pi * (i + 0.5) / 22
    k = box(0.045, 0.13 if i % 2 else 0.09, 0.035, bevel=0.006)
    m = Matrix.Rotation(-a, 4, 'Y') @ Matrix.Translation((0.338, 0, 0))
    p.add(k, "tyre", m @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
p.add(torus(0.225, 0.018, 18, 4), "rim")
for i in range(5):                  # chunky mag spokes
    a = 2 * math.pi * i / 5
    s = box(0.19, 0.03, 0.045, bevel=0.008)
    move(s, 0.12, 0, 0)
    p.add(s, "frame", Matrix.Rotation(a, 4, 'Y'))
hub = prism(0.05, 0.05, 0.12, 8)
rotate(hub, 'X', 90)
move(hub, 0, 0.06, 0)
p.add(hub, "rim")
p.build()

# ---------------------------------------------------------------- crank
# Origin at the bottom bracket. At rest the camera-side (right) arm points down.
p = Part("crank")
ring = prism(0.105, 0.105, 0.012, 16)
rotate(ring, 'X', 90)
move(ring, 0, -0.075, 0)
p.add(ring, "chrome")
spider = prism(0.05, 0.05, 0.016, 5)
rotate(spider, 'X', 90)
move(spider, 0, -0.08, 0)
p.add(spider, "dark")
for y, z in ((-0.10, -0.17), (0.10, 0.17)):
    arm = box(0.035, 0.02, 0.20, bevel=0.008)
    move(arm, 0, y, z / 2)
    p.add(arm, "dark")
p.add(tube((0, -0.10, 0), (0, 0.10, 0), 0.022, 0.022, 6), "chrome")
p.socket("pedal_r", (0, -0.13, -0.17))
p.socket("pedal_l", (0, 0.13, 0.17))
p.build()

p = Part("pedal")
body = box(0.10, 0.09, 0.022, bevel=0.006)
p.add(body, "dark")
for x in (-0.04, 0.04):
    for y in (-0.035, 0.035):
        pin = prism(0.006, 0.006, 0.02, 4)
        move(pin, x, y, 0.005)
        p.add(pin, "chrome")
p.build()

# ---------------------------------------------------------------- seat
p = Part("saddle")
s = box(0.26, 0.13, 0.05, bevel=0.02)
for v in s.verts:
    if v.co.x > 0.02:
        v.co.y *= 0.55
    if v.co.x < -0.08:
        v.co.z += 0.012
move(s, 0.02, 0, 0.035)
p.add(s, "saddle")
p.build()

p = Part("seatpost")
p.add(prism(0.022, 0.022, 0.45, 6), "chrome", Matrix.Translation((0, 0, -0.45)))
p.build()

export_glb(os.path.abspath(OUT))
print("exported", os.path.abspath(OUT))
