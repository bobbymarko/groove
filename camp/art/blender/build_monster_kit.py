"""Builds camp/art/models/monster_kit.glb: every swappable monster part.

Run: blender -b --factory-startup --python camp/art/blender/build_monster_kit.py
Blender axes: rider faces +X, up +Z, camera side is -Y. Bodies have their
origin at the seat (bottom centre). Face parts have their origin at the face
socket with +X pointing out of the face.
"""
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa

OUT = os.path.join(os.path.dirname(__file__), "..", "models", "monster_kit.glb")

reset()


def mirror_y(bm):
    scale(bm, 1, -1, 1)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return bm


def bend_x(bm, k):
    """Curve a flat face part around the body: pull the sides back."""
    for v in bm.verts:
        v.co.x -= k * v.co.y * v.co.y
    return bm


def cap_top(bm, z):
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                           plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=True)
    edges = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.holes_fill(bm, edges=edges)
    return bm


# ------------------------------------------------------------------ bodies
# Each body: (part, sockets). Socket "scale" rides on the empty's rotation
# slot only; sizes are handled in Godot from socket names.

def body_sockets(p, *, face, mouth, top, back, shoulder, hip, horn):
    p.socket("face", face)
    p.socket("mouth", mouth)
    p.socket("top", top)
    p.socket("back", back)
    p.socket("shoulder_l", (shoulder[0], shoulder[1], shoulder[2]))
    p.socket("shoulder_r", (shoulder[0], -shoulder[1], shoulder[2]))
    p.socket("hip_l", (hip[0], hip[1], hip[2]))
    p.socket("hip_r", (hip[0], -hip[1], hip[2]))
    p.socket("horn_l", (horn[0], horn[1], horn[2]), (math.radians(-28), 0, 0))
    p.socket("horn_r", (horn[0], -horn[1], horn[2]), (math.radians(28), 0, 0))


def round_body(fur):
    p = Part("body_round_fur" if fur else "body_round")
    bm = ico(0.40, 2)
    scale(bm, 1.0, 1.0, 0.92)
    # A touch of pear: the belly is heavier than the crown.
    taper(bm, 2, lambda z: 1.0 + max(0.0, -z) * 0.25)
    move(bm, 0, 0, 0.37)
    radial_jitter(bm, 0.035, 11, (0, 0, 0.37))
    if fur:
        tufts(bm, 400, 0.13, 1.0, 5, center=(0, 0, 0.37), min_z=0.08,
              keep_clear=(((0.36, 0, 0.50), 0.17), ((0.37, 0, 0.33), 0.13)))
    p.add(bm, "primary")
    # Belly patch, a lighter shaggy bib.
    belly = ico(0.24, 1)
    scale(belly, 0.45, 1.0, 1.1)
    move(belly, 0.27, 0, 0.26)
    radial_jitter(belly, 0.05, 3, (0.27, 0, 0.26))
    p.add(belly, "secondary")
    body_sockets(p, face=(0.33, 0, 0.50), mouth=(0.36, 0, 0.33), top=(0.0, 0, 0.64),
                 back=(-0.36, 0, 0.40), shoulder=(0.04, 0.35, 0.40), hip=(0.02, 0.20, 0.10),
                 horn=(0.04, 0.22, 0.66))
    return p


def square_body(fur):
    p = Part("body_square_fur" if fur else "body_square")
    bm = box(0.44, 0.52, 0.52, bevel=0.04)
    move(bm, 0, 0, 0.30)
    taper(bm, 2, lambda z: 1.0 - (z - 0.30) * 0.25)
    if fur:
        radial_jitter(bm, 0.03, 4, (0, 0, 0.3))
        tufts(bm, 400, 0.07, 1.0, 9, center=(0, 0, 0.30), min_z=0.06)
    p.add(bm, "primary")
    # Chest plate and two bolts.
    plate = box(0.03, 0.30, 0.20, bevel=0.01)
    move(plate, 0.225, 0, 0.30)
    p.add(plate, "secondary")
    for y in (-0.10, 0.10):
        b = prism(0.022, 0.022, 0.02, 6)
        rotate(b, 'Y', 90)
        move(b, 0.235, y, 0.43)
        p.add(b, "accent")
    body_sockets(p, face=(0.23, 0, 0.44), mouth=(0.23, 0, 0.36), top=(0, 0, 0.58),
                 back=(-0.23, 0, 0.32), shoulder=(0.0, 0.27, 0.46), hip=(0.0, 0.15, 0.06),
                 horn=(0.02, 0.18, 0.56))
    return p


def bean_body(fur):
    p = Part("body_bean_fur" if fur else "body_bean")
    bm = ico(0.30, 2)
    scale(bm, 1.0, 1.0, 1.45)
    taper(bm, 2, lambda z: 1.0 - max(0.0, z) * 0.35)
    rotate(bm, 'Y', 10)            # a forward hunch
    move(bm, 0, 0, 0.42)
    radial_jitter(bm, 0.03, 21, (0, 0, 0.42))
    if fur:
        tufts(bm, 400, 0.10, 1.0, 13, center=(0, 0, 0.42), min_z=0.12,
              keep_clear=(((0.30, 0, 0.64), 0.15), ((0.31, 0, 0.47), 0.12)))
    p.add(bm, "primary")
    body_sockets(p, face=(0.30, 0, 0.64), mouth=(0.31, 0, 0.47), top=(0.06, 0, 0.74),
                 back=(-0.26, 0, 0.44), shoulder=(0.06, 0.27, 0.46), hip=(0.02, 0.17, 0.10),
                 horn=(0.08, 0.15, 0.80))
    return p


for fur in (False, True):
    round_body(fur).build()
    square_body(fur).build()
    bean_body(fur).build()

# ------------------------------------------------------------------ heads
# Origin at the neck (bottom centre). A body with no head shows its face on
# the body's own face socket.

p = Part("head_screen")
shell = box(0.36, 0.44, 0.32, bevel=0.035)
move(shell, 0, 0, 0.20)
p.add(shell, "primary")
screen = box(0.02, 0.34, 0.20, bevel=0.01)
move(screen, 0.185, 0, 0.20)
p.add(screen, "screen")
neck = prism(0.06, 0.07, 0.05, 6)
p.add(neck, "secondary")
for y in (-1, 1):                  # ear bolts
    ear = prism(0.05, 0.04, 0.04, 6)
    rotate(ear, 'X', -90 * y)
    move(ear, 0, 0.22 * y, 0.21)
    p.add(ear, "accent")
p.socket("face", (0.20, 0, 0.22))
p.socket("mouth", (0.20, 0, 0.13))
p.socket("top", (0, 0, 0.36))
p.socket("horn_l", (0.0, 0.16, 0.34), (math.radians(-28), 0, 0))
p.socket("horn_r", (0.0, -0.16, 0.34), (math.radians(28), 0, 0))
p.build()

p = Part("head_skull")
sk = ico(0.19, 2)
scale(sk, 1.05, 0.95, 1.0)
move(sk, 0.0, 0, 0.21)
jaw = box(0.20, 0.22, 0.10, bevel=0.02)
move(jaw, 0.07, 0, 0.07)
p.add(sk, "teeth").add(jaw, "teeth")
for y in (-1, 1):
    s = ico(0.06, 1)
    scale(s, 0.5, 1.0, 1.1)
    move(s, 0.17, 0.075 * y, 0.21)
    p.add(s, "pupil")
nose = prism(0.03, 0.0, 0.04, 3)
rotate(nose, 'Y', 180)
move(nose, 0.19, 0, 0.16)
p.add(nose, "pupil")
p.socket("face", (0.19, 0, 0.30))
p.socket("mouth", (0.17, 0, 0.07))
p.socket("top", (0, 0, 0.27))
p.socket("horn_l", (0.0, 0.13, 0.35), (math.radians(-28), 0, 0))
p.socket("horn_r", (0.0, -0.13, 0.35), (math.radians(28), 0, 0))
p.build()

# ------------------------------------------------------------------ eyes

def eyeball(p, r, y=0.0, lid_tilt=0.0, lid_drop=0.25, pupil=0.45, brow=True, look=(0.0, 0.0)):
    """Eyeball + heavy upper lid. lid_drop: fraction of the eye the lid hides.
    lid_tilt: degrees, positive = inner corner down (a scowl)."""
    ball = uvsphere(r, 10, 8)
    move(ball, -r * 0.35, y, 0)
    p.add(ball, "eye")
    pu = uvsphere(r * pupil, 8, 6)
    scale(pu, 0.45, 1.0, 1.0)
    move(pu, r * 0.62, y + look[0] * r, -r * 0.08 + look[1] * r)
    p.add(pu, "pupil")
    lid = uvsphere(r * 1.10, 10, 8)
    cap_top(lid, r * (1.0 - 2.0 * lid_drop) * 1.10)
    lid_m = Matrix.Translation((-r * 0.33, y, 0)) @ Matrix.Rotation(math.radians(lid_tilt), 4, 'X')
    p.add(lid, "primary", lid_m)
    if brow:
        b = box(r * 0.55, r * 2.2, r * 0.38, bevel=r * 0.08)
        bm_m = (Matrix.Translation((r * 0.35, y, r * (1.02 - lid_drop * 0.9)))
                @ Matrix.Rotation(math.radians(lid_tilt * 1.6), 4, 'X'))
        p.add(b, "secondary", bm_m)


p = Part("eyes_cyclops")
eyeball(p, 0.15, lid_drop=0.34, lid_tilt=-6, pupil=0.42)
p.build()

p = Part("eyes_squint")
eyeball(p, 0.075, y=0.10, lid_drop=0.42, lid_tilt=-18, pupil=0.5, look=(0.1, 0))
eyeball(p, 0.075, y=-0.10, lid_drop=0.42, lid_tilt=18, pupil=0.5, look=(0.1, 0))
p.build()

p = Part("eyes_screen")
for y in (0.085, -0.085):
    e = box(0.012, 0.09, 0.07)
    side = 1.0 if y > 0 else -1.0
    for v in e.verts:              # slant the tops down toward the middle: a glare
        if v.co.z > 0:
            v.co.z += 0.022 * (v.co.y / 0.045) * side
    move(e, 0.0, y, 0)
    p.add(e, "glow")
p.build()

p = Part("eyes_shades")
for y in (-0.10, 0.10):
    lens = box(0.03, 0.15, 0.08, bevel=0.012)
    for v in lens.verts:
        if v.co.z < 0:
            v.co.y *= 0.8
    move(lens, 0.0, y, 0)
    p.add(lens, "pupil")
bar = box(0.03, 0.34, 0.025)
move(bar, 0.005, 0, 0.03)
p.add(bar, "dark")
p.build()

# ------------------------------------------------------------------ mouths

p = Part("mouth_teeth")
gash = box(0.05, 0.30, 0.09, bevel=0.012)
for v in gash.verts:               # a lopsided grin: one corner higher
    v.co.z += v.co.y * 0.12
bend_x(gash, 0.9)
p.add(gash, "mouth")
for i in range(7):
    y = -0.12 + i * 0.04
    up = prism(0.018, 0.0, 0.045 if i % 3 else 0.06, 3)
    rotate(up, 'Y', 180)
    t = Matrix.Translation((0.03 - 0.9 * y * y, y, 0.045 + y * 0.12))
    p.add(up, "teeth", t)
for i in range(6):
    y = -0.10 + i * 0.04
    lo = prism(0.016, 0.0, 0.04, 3)
    t = Matrix.Translation((0.03 - 0.9 * y * y, y, -0.045 + y * 0.12))
    p.add(lo, "teeth", t)
p.build()

p = Part("mouth_smirk")
s = box(0.04, 0.16, 0.025, bevel=0.008)
for v in s.verts:
    v.co.z += max(0.0, -v.co.y) * 0.25
bend_x(s, 1.2)
p.add(s, "mouth")
fang = prism(0.016, 0.0, 0.045, 3)
rotate(fang, 'Y', 180)
p.add(fang, "teeth", Matrix.Translation((0.02, -0.05, 0.0)))
p.build()

p = Part("mouth_grill")
for i in range(4):
    b = box(0.015, 0.16, 0.012)
    move(b, 0, 0, -0.03 + i * 0.022)
    p.add(b, "glow")
p.build()

# ------------------------------------------------------------------ extras

def horn(side):
    p = Part("horn_%s" % side)
    pts = []
    for i in range(7):
        t = i / 6.0
        pts.append(Vector((0.06 * math.sin(t * 2.2) - 0.02, 0.10 * t, 0.20 * t - 0.05 * t * t)))
    for i in range(6):
        r0 = 0.055 * (1.0 - i / 6.0) + 0.006
        r1 = 0.055 * (1.0 - (i + 1) / 6.0) + 0.004
        p.add(tube(pts[i], pts[i + 1], r0, r1, 6), "horn")
    if side == "r":
        mirror_y(p.bm)
    return p


horn("l").build()
horn("r").build()

p = Part("cap_back")                 # cap worn backwards: attitude
dome = uvsphere(0.20, 10, 8)
cap_top(dome, 0.0)
scale(dome, 1.05, 1.0, 0.72)
p.add(dome, "cap")
brim = box(0.20, 0.26, 0.018, bevel=0.006)
move(brim, -0.24, 0, 0.012)
p.add(brim, "cloth")
button = uvsphere(0.025, 6, 4)
move(button, 0, 0, 0.145)
p.add(button, "cloth")
p.build()

p = Part("beanie")
dome = uvsphere(0.20, 10, 8)
cap_top(dome, -0.01)
scale(dome, 1.0, 1.0, 1.1)
p.add(dome, "cloth")
cuff = torus(0.195, 0.035, 12, 5)
rotate(cuff, 'X', 90)
move(cuff, 0, 0, 0.01)
p.add(cuff, "cloth")
pom = ico(0.05, 1)
jitter(pom, 0.012, 2)
move(pom, 0, 0, 0.23)
p.add(pom, "accent")
p.build()

p = Part("spikes")                   # a crest from the crown down the back, from the top socket
for i in range(6):
    a = math.radians(18 - i * 24)
    c = Vector((0.0, 0, -0.30))
    pos = c + Vector((math.sin(a), 0, math.cos(a))) * 0.29
    cone = prism(0.07 - i * 0.005, 0.0, 0.17 - i * 0.015, 5)
    m = Matrix.Translation(pos) @ Matrix.Rotation(a - math.radians(12), 4, 'Y')
    p.add(cone, "secondary", m)
p.build()

p = Part("antenna")
p.add(prism(0.012, 0.012, 0.16, 5), "dark")
tip = ico(0.035, 1)
move(tip, 0, 0, 0.18)
p.add(tip, "accent")
p.build()

p = Part("backpack")
pack = box(0.16, 0.28, 0.32, bevel=0.03)
move(pack, -0.08, 0, 0)
p.add(pack, "cloth")
flap = box(0.17, 0.29, 0.10, bevel=0.02)
move(flap, -0.085, 0, 0.13)
p.add(flap, "accent")
pocket = box(0.05, 0.18, 0.12, bevel=0.015)
move(pocket, -0.18, 0, -0.05)
p.add(pocket, "cloth")
p.build()

p = Part("beard")                    # origin at the mouth socket
b = ico(0.20, 2)
scale(b, 0.55, 1.15, 1.35)
move(b, 0.0, 0, -0.16)
radial_jitter(b, 0.05, 71, (0, 0, -0.16))
tufts(b, 400, 0.08, 1.0, 72, center=(0, 0, -0.10))
p.add(b, "beard")
for side in (-1, 1):                 # a drooping moustache
    m = prism(0.045, 0.0, 0.20, 5)
    p.add(m, "beard", Matrix.Translation((0.07, 0.03 * side, 0.02)) @ Matrix.Rotation(math.radians(150 * side), 4, 'X'))
p.build()

p = Part("hat_pioneer")              # wide brim, pinched crown, a band
brim = prism(0.36, 0.36, 0.025, 12)
jitter(brim, 0.012, 73, (0.5, 0.5, 1))
for v in brim.verts:                 # brim turns up at the sides
    v.co.z += (abs(v.co.y) / 0.36) ** 2 * 0.06
p.add(brim, "cap")
crown = prism(0.20, 0.17, 0.20, 8)
for v in crown.verts:
    if v.co.z > 0.19 and abs(v.co.y) < 0.05:
        v.co.z -= 0.05
move(crown, 0, 0, 0.02)
p.add(crown, "cap")
band = prism(0.205, 0.20, 0.045, 8)
move(band, 0, 0, 0.025)
p.add(band, "accent")
feather = prism(0.02, 0.0, 0.22, 4)
p.add(feather, "horn", Matrix.Translation((-0.05, 0.19, 0.06)) @ Matrix.Rotation(math.radians(-35), 4, 'Y'))
p.build()

p = Part("pipe")                     # origin at the mouth socket, out the camera side
p.add(tube((0.02, -0.06, -0.01), (0.20, -0.12, -0.07), 0.012, 0.012, 5), "dark")
bowl = prism(0.04, 0.045, 0.08, 7)
move(bowl, 0.21, -0.125, -0.09)
p.add(bowl, "dark")
ember = prism(0.032, 0.032, 0.01, 7)
move(ember, 0.21, -0.125, -0.012)
p.add(ember, "ember")
p.build()

# ------------------------------------------------------------------ hands and feet
# Hands: origin at the wrist, pointing +X. Feet: origin at the ankle, toe +X,
# sole bottom at z = -0.09; the pedal sits under the ball of the foot.

p = Part("hand_mitt")
palm = box(0.11, 0.10, 0.08, bevel=0.02)
move(palm, 0.055, 0, 0)
p.add(palm, "primary")
thumb = box(0.05, 0.035, 0.035, bevel=0.01)
move(thumb, 0.04, 0.055, 0.02)
p.add(thumb, "primary")
p.build()

p = Part("hand_claw")
palm = box(0.09, 0.10, 0.07, bevel=0.018)
move(palm, 0.045, 0, 0)
p.add(palm, "primary")
for y in (-0.035, 0.0, 0.035):
    c = prism(0.017, 0.0, 0.07, 4)
    p.add(c, "horn", Matrix.Translation((0.085, y, 0.0)) @ Matrix.Rotation(math.radians(115), 4, 'Y'))
p.build()

p = Part("shoe")
upper = box(0.22, 0.12, 0.10, bevel=0.03)
for v in upper.verts:
    if v.co.x > 0.02:
        v.co.z -= (v.co.x - 0.02) * 0.25
move(upper, 0.05, 0, -0.03)
p.add(upper, "dark")
sole = box(0.24, 0.13, 0.03, bevel=0.01)
move(sole, 0.05, 0, -0.085)
p.add(sole, "sole")
tongue = box(0.06, 0.08, 0.04, bevel=0.01)
move(tongue, -0.01, 0, 0.03)
p.add(tongue, "accent")
p.build()

p = Part("hoof")
h = prism(0.07, 0.085, 0.11, 7)
move(h, 0.02, 0, -0.10)
p.add(h, "dark")
p.build()

export_glb(os.path.abspath(OUT))
print("exported", os.path.abspath(OUT))
