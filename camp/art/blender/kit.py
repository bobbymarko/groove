"""Shared helpers for Camp's Blender build scripts.

Conventions (Blender side): the rider faces +X, up is +Z, the camera-facing
side is -Y. The glTF exporter turns this into Godot's +X forward, +Y up,
+Z toward the side-view camera.

Every part is one mesh object. Attachment points are empties parented to it,
named "<part>__<socket>" so names stay unique inside Blender; Godot splits on
the double underscore. Materials are named by role ("primary", "secondary",
"eye", "pupil", ...) so the game can recolour them.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

# Default role colours. The editor overrides these per rider.
ROLE_COLOURS = {
    "primary": (0.46, 0.27, 0.78),
    "secondary": (0.30, 0.16, 0.55),
    "accent": (0.94, 0.42, 0.01),
    "eye": (0.95, 0.93, 0.88),
    "pupil": (0.06, 0.05, 0.06),
    "mouth": (0.16, 0.05, 0.12),
    "teeth": (0.96, 0.93, 0.84),
    "horn": (0.91, 0.82, 0.64),
    "dark": (0.12, 0.12, 0.14),
    "sole": (0.92, 0.90, 0.85),
    "metal": (0.55, 0.60, 0.66),
    "screen": (0.04, 0.10, 0.14),
    "glow": (0.20, 0.95, 1.00),
    "cap": (0.86, 0.22, 0.18),
    "cloth": (0.14, 0.20, 0.36),
    "frame": (0.94, 0.42, 0.01),
    "tyre": (0.10, 0.10, 0.11),
    "rim": (0.22, 0.22, 0.25),
    "chrome": (0.70, 0.72, 0.75),
    "saddle": (0.13, 0.12, 0.13),
    "grip": (0.12, 0.12, 0.12),
    "leaf": (0.20, 0.42, 0.26),
    "leaf_dark": (0.13, 0.30, 0.22),
    "bark": (0.36, 0.23, 0.16),
    "rock": (0.46, 0.46, 0.50),
    "snow": (0.93, 0.93, 0.97),
    "mountain": (0.36, 0.34, 0.52),
    "berry": (0.72, 0.10, 0.28),
    "grass": (0.40, 0.58, 0.28),
    "cloud": (0.98, 0.72, 0.66),
    "dirt": (0.55, 0.36, 0.22),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(role):
    m = bpy.data.materials.get(role)
    if m:
        return m
    m = bpy.data.materials.new(role)
    c = ROLE_COLOURS.get(role, (1, 0, 1))
    m.diffuse_color = (*c, 1.0)
    try:
        m.use_nodes = True
    except Exception:
        pass
    if m.node_tree:
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*c, 1.0)
            bsdf.inputs["Roughness"].default_value = 1.0
    return m


class Part:
    """Accumulates geometry for one part; each piece carries a material role."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.roles = []          # material roles in slot order
        self.sockets = {}        # socket name -> (location, rotation euler XYZ)

    def slot(self, role):
        if role not in self.roles:
            self.roles.append(role)
        return self.roles.index(role)

    def add(self, piece_bm, role, matrix=None):
        """Merge a bmesh into the part with every face in the given role."""
        if matrix is not None:
            bmesh.ops.transform(piece_bm, matrix=matrix, verts=piece_bm.verts)
        idx = self.slot(role)
        me = bpy.data.meshes.new("tmp")
        piece_bm.to_mesh(me)
        piece_bm.free()
        offset = len(self.bm.faces)
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        self.bm.faces.ensure_lookup_table()
        for f in self.bm.faces[offset:]:
            f.material_index = idx
        return self

    def socket(self, name, loc, rot=(0, 0, 0)):
        self.sockets[name] = (Vector(loc), rot)

    def build(self, collection=None):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = False
        for r in self.roles:
            me.materials.append(material(r))
        ob = bpy.data.objects.new(self.name, me)
        (collection or bpy.context.scene.collection).objects.link(ob)
        for s, (loc, rot) in self.sockets.items():
            e = bpy.data.objects.new("%s__%s" % (self.name, s), None)
            e.empty_display_size = 0.05
            e.location = loc
            e.rotation_euler = rot
            e.parent = ob
            (collection or bpy.context.scene.collection).objects.link(e)
        return ob


# ---------------------------------------------------------------- primitives

def ico(radius=1.0, subdiv=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    return bm


def uvsphere(radius=1.0, segs=8, rings=6):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    return bm


def box(sx, sy, sz, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect='EDGES', profile=0.5)
    return bm


def prism(r1, r2, depth, sides=6):
    """Cylinder/cone along +Z from z=0 to z=depth."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides,
                          radius1=r1, radius2=r2, depth=depth)
    bmesh.ops.translate(bm, vec=(0, 0, depth / 2), verts=bm.verts)
    return bm


def torus(major, minor, maj_segs=16, min_segs=6):
    bm = bmesh.new()
    verts = []
    for i in range(maj_segs):
        a = 2 * math.pi * i / maj_segs
        ring = []
        for j in range(min_segs):
            b = 2 * math.pi * j / min_segs
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), minor * math.sin(b), r * math.sin(a))))
        verts.append(ring)
    for i in range(maj_segs):
        for j in range(min_segs):
            a, b = verts[i], verts[(i + 1) % maj_segs]
            bm.faces.new((a[j], b[j], b[(j + 1) % min_segs], a[(j + 1) % min_segs]))
    return bm


def tube(p0, p1, r0, r1=None, sides=6):
    """Prism from point p0 to p1 (Blender coordinates)."""
    r1 = r0 if r1 is None else r1
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = prism(r0, r1, d.length, sides)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


# ---------------------------------------------------------------- shaping

def jitter(bm, amount, seed, axes=(1, 1, 1)):
    rng = random.Random(seed)
    for v in bm.verts:
        v.co.x += rng.uniform(-amount, amount) * axes[0]
        v.co.y += rng.uniform(-amount, amount) * axes[1]
        v.co.z += rng.uniform(-amount, amount) * axes[2]
    return bm


def radial_jitter(bm, amount, seed, center=(0, 0, 0)):
    rng = random.Random(seed)
    c = Vector(center)
    for v in bm.verts:
        d = v.co - c
        if d.length > 1e-6:
            v.co = c + d * (1.0 + rng.uniform(-amount, amount))
    return bm


def scale(bm, sx, sy, sz):
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return bm


def move(bm, x, y, z):
    bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts)
    return bm


def rotate(bm, axis, degrees):
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(degrees), 3, axis), verts=bm.verts)
    return bm


def taper(bm, axis_index, fn):
    """Scale the other two axes by fn(coordinate along axis)."""
    for v in bm.verts:
        k = fn(v.co[axis_index])
        for i in range(3):
            if i != axis_index:
                v.co[i] *= k
    return bm


def tufts(bm, count, length, width, seed, center=(0, 0, 0), min_z=-99, keep_clear=()):
    """Shingled shag: every face hangs a pointed clump that droops over the
    one below, so the silhouette reads as fur rather than spikes.
    keep_clear: (point, radius) pairs where no clump grows (the face)."""
    rng = random.Random(seed)
    bm.faces.ensure_lookup_table()
    c = Vector(center)
    faces = []
    for f in bm.faces:
        m = f.calc_center_median()
        if m.z <= min_z:
            continue
        if any((m - Vector(p)).length < r for p, r in keep_clear):
            continue
        faces.append(f)
    rng.shuffle(faces)
    for f in faces[:count]:
        centre = f.calc_center_median()
        out = (centre - c).normalized()
        n = (out * 0.45 + Vector((rng.uniform(-.15, .15) - 0.15, rng.uniform(-.15, .15), -1.0))).normalized()
        res = bmesh.ops.extrude_discrete_faces(bm, faces=[f])
        nf = res["faces"][0]
        k = rng.uniform(0.6, 1.2)
        for v in nf.verts:
            v.co = centre + (v.co - centre) * width + out * 0.01
        tip = centre + n * length * k + out * length * 0.25
        bmesh.ops.pointmerge(bm, verts=list(nf.verts), merge_co=tip)
    return bm


def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=False,
                              export_apply=True, export_yup=True, export_materials='EXPORT')
