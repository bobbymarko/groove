class_name PlantGen
extends RefCounted
## Procedural plants and rocks for the realistic look, built from code in the
## manner of Abyssal Garden (MIT, Noniv/abyssal-garden): tubes swept along
## jittered curves, recursive branching, leaves and needles as solid blades,
## normals bent toward the crown's outside so a crown shades as one rounded mass.
##
## Every mesh has two surfaces at most, bark (0) and foliage (1). Vertex data:
##   COLOR.rgb  base colour       COLOR.a  baked ambient occlusion (0 dark .. 1 open)
##   UV         x around / across, y metres along (bark pattern, blade shading)
##   UV2        x height above the root in metres (sway), y flutter weight (0 wood .. 1 leaf)


class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, col: Color, a: Vector2, b: Vector2) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(a)
		uv2.append(b)
		return v.size() - 1

	## Clockwise front faces, as Godot expects.
	func tri(a: int, b: int, cc: int) -> void:
		idx.append(a)
		idx.append(cc)
		idx.append(b)

	func empty() -> bool:
		return idx.is_empty()

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


static func _mesh(bark: Builder, leaf: Builder, bark_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not bark.empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark.arrays())
		m.surface_set_material(m.get_surface_count() - 1, bark_mat)
	if not leaf.empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf.arrays())
		m.surface_set_material(m.get_surface_count() - 1, leaf_mat)
	return m


## Sweep a tube along pts with radius per point (parallel-transported frames).
static func tube(b: Builder, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, col: Color,
		ao_base: float, flutter: float, cap_ground := 0.0) -> void:
	var count := pts.size()
	if count < 2:
		return
	var t0 := (pts[1] - pts[0]).normalized()
	var nrm := Vector3.RIGHT if absf(t0.dot(Vector3.UP)) > 0.9 else Vector3.UP
	nrm = (nrm - t0 * nrm.dot(t0)).normalized()
	var along := 0.0
	var first := b.v.size()
	for i in count:
		var tg := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bn := tg.cross(nrm)
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		var k := float(i) / float(count - 1)
		var ao := clampf(ao_base + (1.0 - ao_base) * k, 0.0, 1.0)
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var dir := nrm * cos(a) + bn * sin(a)
			var p := pts[i] + dir * radii[i]
			if cap_ground > 0.0 and i == 0:
				p.y -= cap_ground
			b.add(p, dir, col, Vector2(float(s) / float(sides) * radii[i] * TAU, along), Vector2(maxf(pts[i].y, 0.0), flutter))
	for i in count - 1:
		for s in sides:
			var r0 := first + i * (sides + 1) + s
			var r1 := r0 + sides + 1
			b.tri(r0, r1, r0 + 1)
			b.tri(r0 + 1, r1, r1 + 1)


## A blade or frond: a strip along pts, cross-section left edge, raised middle,
## right edge. width(k) shapes it; normals lean outward by `round` for volume.
static func blade(b: Builder, pts: PackedVector3Array, side: Vector3, widths: PackedFloat32Array, col: Color,
		ao0: float, ao1: float, flutter: float, round_dir: Vector3, roundness: float, crease: float) -> void:
	var count := pts.size()
	var first := b.v.size()
	var along := 0.0
	for i in count:
		var tg := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var up := side.cross(tg).normalized()
		if up.y < 0.0:
			up = -up
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		var k := float(i) / float(count - 1)
		var w := widths[i]
		var ao := lerpf(ao0, ao1, k)
		var nrm := (up + round_dir * roundness).normalized()
		var h := Vector2(maxf(pts[i].y, 0.0), flutter * k)
		var lift := up * w * crease
		b.add(pts[i] - side * w - lift * 0.5, (nrm - side * 0.4).normalized(), col, Vector2(-1.0, along), h)
		b.add(pts[i] + lift * 0.5, nrm, col.lightened(0.04), Vector2(0.0, along), h)
		b.add(pts[i] + side * w - lift * 0.5, (nrm + side * 0.4).normalized(), col, Vector2(1.0, along), h)
		b.c[b.c.size() - 1].a = ao
		b.c[b.c.size() - 2].a = ao
		b.c[b.c.size() - 3].a = ao
	for i in count - 1:
		var r0 := first + i * 3
		var r1 := r0 + 3
		b.tri(r0, r1, r0 + 1)
		b.tri(r0 + 1, r1, r1 + 1)
		b.tri(r0 + 1, r1 + 1, r0 + 2)
		b.tri(r0 + 2, r1 + 1, r1 + 2)


## A thin flat blade (grass): two vertices per row, normals mostly up so a
## meadow shades like a surface rather than a heap of slivers.
static func grass_blade(b: Builder, pts: PackedVector3Array, side: Vector3, widths: PackedFloat32Array, col: Color,
		ao0: float, ao1: float) -> void:
	var count := pts.size()
	var first := b.v.size()
	for i in count:
		var k := float(i) / float(count - 1)
		var tg := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var face := side.cross(tg).normalized()
		var nrm := (face * 0.35 + Vector3.UP).normalized()
		var c := col
		c.a = lerpf(ao0, ao1, k)
		var h := Vector2(pts[i].y, k)
		b.add(pts[i] - side * widths[i], nrm, c, Vector2(-1.0, k), h)
		b.add(pts[i] + side * widths[i], nrm, c, Vector2(1.0, k), h)
	for i in count - 1:
		var r0 := first + i * 2
		b.tri(r0, r0 + 2, r0 + 1)
		b.tri(r0 + 1, r0 + 2, r0 + 3)


static func _col(base: Color, rng: RandomNumberGenerator, spread: float, ao: float) -> Color:
	var c := Color(base.r * rng.randf_range(1.0 - spread, 1.0 + spread),
		base.g * rng.randf_range(1.0 - spread, 1.0 + spread),
		base.b * rng.randf_range(1.0 - spread, 1.0 + spread), ao)
	return c


# ---- spruce ---------------------------------------------------------------------

## A spruce or fir: tapered trunk, whorls of drooping fronds whose reach follows
## a cone, two side sprigs per frond, a leader at the top.
## detail 1 is the close-up tree; lower values build the distant version from the
## same seed (fewer, broader fronds, no sprigs), so the silhouette matches.
static func spruce(seed_value: int, bark_mat: Material, leaf_mat: Material, needle := Color(0.06, 0.14, 0.07), detail := 1.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := Builder.new()
	var leaf := Builder.new()
	var H := rng.randf_range(10.0, 15.0)
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	var r0 := H * 0.022
	for i in 9:
		var k := float(i) / 8.0
		trunk.append(Vector3(0.0, H * k, 0.0) + lean * k * k)
		radii.append(lerpf(r0, 0.02, pow(k, 0.8)) * (1.0 + 0.4 * maxf(0.0, 0.12 - k) / 0.12))
	tube(bark, trunk, radii, 7 if detail >= 1.0 else 4, Color(0.24, 0.18, 0.14), 0.45, 0.0, 0.2)
	var y0 := H * rng.randf_range(0.08, 0.16)
	var rmax := H * rng.randf_range(0.24, 0.3)
	var y := y0
	var spin := 0.0
	while y < H - 0.3:
		var u := (y - y0) / (H - y0)
		var reach := rmax * pow(1.0 - u, 0.95) * (0.55 + 0.45 * smoothstep(0.0, 0.1, u))
		var axis := Vector3(0.0, y, 0.0) + lean * (y / H) * (y / H)
		var count := rng.randi_range(5, 8)
		spin += rng.randf_range(0.4, 1.2)
		if detail < 1.0:
			count = maxi(4, count - 2)
		for j in count:
			var ang := spin + TAU * float(j) / float(count) + rng.randf_range(-0.25, 0.25)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var L := reach * rng.randf_range(0.8, 1.12) + 0.25
			_frond(leaf, rng, axis, dir, L, needle, u, 1.0 if detail >= 1.0 else 1.7, detail >= 1.0)
		y += rng.randf_range(0.32, 0.5) * (0.75 + 0.5 * (1.0 - u)) / maxf(detail, 0.45)
	# Leader: a short upright frond pair.
	var top := Vector3(0.0, H - 0.5, 0.0) + lean
	for s in 2:
		var side := Vector3(cos(s * PI * 0.5), 0.0, sin(s * PI * 0.5))
		var pts := PackedVector3Array([top, top + Vector3(0.0, 0.3, 0.0), top + Vector3(0.0, 0.6, 0.0)])
		blade(leaf, pts, side, PackedFloat32Array([0.16, 0.08, 0.0]), needle, 0.9, 1.0, 1.0, Vector3.UP, 0.5, 0.3)
	return _mesh(bark, leaf, bark_mat, leaf_mat)


## One spruce branch: a frond that droops and lifts again at the tip, a ragged
## edge, and sprigs off both sides along its length.
static func _frond(leaf: Builder, rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, L: float, needle: Color,
		u: float, scale: float, sprigs_on := true) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var rise := rng.randf_range(-0.08, 0.06)
	var droop := rng.randf_range(0.3, 0.6) * L
	var upturn := rng.randf_range(0.1, 0.3) * L
	var pts := PackedVector3Array()
	var widths := PackedFloat32Array()
	var segs := 7 if sprigs_on else 4
	var phase := rng.randf() * 6.0
	for i in segs + 1:
		var k := float(i) / float(segs)
		var sag := droop * (0.25 * k + 0.75 * k * k) - upturn * k * k * k * 0.6   # sags, then flicks up a little at the tip
		pts.append(origin + dir * L * k + Vector3.UP * (rise * L * k - sag))
		var w := L * 0.24 * sin(PI * pow(k, 0.6)) * (1.0 + 0.3 * sin(k * 27.0 + phase)) * scale
		widths.append(maxf(w, 0.0) + (0.05 if i == 0 else 0.0))
	var col := _col(needle, rng, 0.14, 1.0)
	var ao0 := 0.12 + 0.3 * u
	blade(leaf, pts, side, widths, col, ao0, 1.0, 1.0, dir, 0.7, 0.4)
	if L < 0.5 or not sprigs_on:
		return
	var sprigs := clampi(int(L * 3.0), 2, 7)
	for j in sprigs:
		var s := -1.0 if j % 2 == 0 else 1.0
		var at := lerpf(0.2, 0.85, (float(j) + rng.randf()) / float(sprigs))
		var seg := at * float(segs)
		var o := pts[int(floor(seg))].lerp(pts[mini(int(floor(seg)) + 1, segs)], seg - floor(seg))
		var d2 := (dir + side * s * rng.randf_range(0.7, 1.3) + Vector3.DOWN * rng.randf_range(0.1, 0.4)).normalized()
		var L2 := L * rng.randf_range(0.22, 0.38) * (1.15 - at * 0.5)
		var sub := PackedVector3Array()
		var sw := PackedFloat32Array()
		for i in 4:
			var k := float(i) / 3.0
			sub.append(o + d2 * L2 * k + Vector3.DOWN * L2 * 0.25 * k * k)
			sw.append(L2 * 0.38 * sin(PI * pow(k, 0.6)) + (0.03 if i == 0 else 0.0))
		blade(leaf, sub, d2.cross(Vector3.UP).normalized(), sw, col.darkened(rng.randf_range(0.0, 0.12)),
				lerpf(ao0, 1.0, at) * 0.9, 1.0, 1.0, (d2 + dir).normalized(), 0.7, 0.35)


# ---- broadleaf ------------------------------------------------------------------

## A broadleaf tree (oak-ish, or a birch with `birch`): a trunk that forks into
## limbs, branches recursing three levels, leaf clusters along the outer twigs.
static func broadleaf(seed_value: int, bark_mat: Material, leaf_mat: Material, leaf_col: Color, bark_col: Color,
		birch := false, bare := false, detail := 1.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := Builder.new()
	var leaf := Builder.new()
	var H := rng.randf_range(7.0, 11.0) * (1.25 if birch else 1.0)
	var fork := H * rng.randf_range(0.3, 0.42) * (1.3 if birch else 1.0)
	var r0 := H * (0.018 if birch else 0.03)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 6:
		var k := float(i) / 5.0
		pts.append(Vector3(0.0, fork * k, 0.0) + lean * k * k * 0.5)
		radii.append(r0 * (1.0 - 0.25 * k) * (1.0 + 0.5 * maxf(0.0, 0.15 - k) / 0.15))
	tube(bark, pts, radii, 8, bark_col, 0.4, 0.0, 0.2)
	var crown_c := Vector3(0.0, fork + (H - fork) * 0.5, 0.0) + lean * 0.5
	var limbs := rng.randi_range(2, 3) if birch else rng.randi_range(3, 4)
	var spin := rng.randf() * TAU
	for i in limbs:
		var a := spin + TAU * float(i) / float(limbs) + rng.randf_range(-0.3, 0.3)
		var out := rng.randf_range(0.25, 0.5) if birch else rng.randf_range(0.5, 0.85)
		var d := Vector3(cos(a) * out, 1.0, sin(a) * out).normalized()
		_branch(bark, leaf, rng, pts[pts.size() - 1], d, (H - fork) * rng.randf_range(0.5, 0.7), radii[radii.size() - 1] * 0.75,
				3, bark_col, leaf_col, crown_c, H, birch, bare, detail)
	return _mesh(bark, leaf, bark_mat, leaf_mat)


static func _branch(bark: Builder, leaf: Builder, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, L: float,
		r: float, depth: int, bark_col: Color, leaf_col: Color, crown_c: Vector3, H: float, birch: bool, bare: bool, detail := 1.0) -> void:
	var pts := PackedVector3Array([start])
	var radii := PackedFloat32Array([r])
	var d := dir
	var p := start
	var segs := 3
	for i in segs:
		d = (d + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.08, 0.15), rng.randf_range(-0.25, 0.25))).normalized()
		if birch and depth <= 1:
			d = (d + Vector3.DOWN * 0.35).normalized()    # birch twigs weep
		p += d * L / float(segs)
		pts.append(p)
		radii.append(r * (1.0 - 0.3 * float(i + 1) / float(segs)))
	if detail >= 1.0 or depth >= 2:
		tube(bark, pts, radii, maxi(3, depth + 3) if detail >= 1.0 else 3, bark_col, 0.5, 0.15 * float(3 - depth), 0.0)
	if depth <= 2 and not bare:
		_leaves(leaf, rng, pts, crown_c, H, leaf_col, birch, detail)
	if depth == 0:
		return
	var kids := rng.randi_range(2, 3)
	for i in kids:
		var at := rng.randf_range(0.45, 1.0)
		var seg := clampi(int(at * segs), 1, segs)
		var o := pts[seg]
		var away := (o - crown_c)
		away.y = 0.0
		var nd := (d + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.6), rng.randf_range(-0.8, 0.8)) + away.normalized() * 0.4).normalized()
		_branch(bark, leaf, rng, o, nd, L * rng.randf_range(0.55, 0.75), radii[seg] * 0.7, depth - 1, bark_col, leaf_col, crown_c, H, birch, bare, detail)


## Leaves along a twig: small diamonds, normals bent away from the crown centre.
static func _leaves(leaf: Builder, rng: RandomNumberGenerator, twig: PackedVector3Array, crown_c: Vector3, H: float,
		leaf_col: Color, birch: bool, detail := 1.0) -> void:
	var count := int((55 if birch else 70) * detail * detail)
	var size := (0.2 if birch else 0.3) / maxf(detail, 0.3)
	for i in count:
		var k := rng.randf_range(0.25, 1.0)
		var f := k * float(twig.size() - 1)
		var a := twig[int(floor(f))]
		var b := twig[mini(int(floor(f)) + 1, twig.size() - 1)]
		var p := a.lerp(b, f - floor(f)) + Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.45, 0.35), rng.randf_range(-0.55, 0.55))
		var outward := (p - crown_c).normalized()
		var nrm := (outward * 0.75 + Vector3.UP * 0.4).normalized()
		var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.2), rng.randf_range(-1.0, 1.0)).normalized()
		var across := axis.cross(nrm).normalized()
		var s := size * rng.randf_range(0.7, 1.3)
		var depth := clampf((p - crown_c).length() / (H * 0.35), 0.0, 1.0)
		var ao := clampf(0.25 + 0.75 * depth, 0.0, 1.0) * clampf(0.6 + 0.4 * (p.y / H), 0.0, 1.0)
		var col := _col(leaf_col, rng, 0.15, ao)
		var h := Vector2(p.y, 1.0)
		var base := leaf.add(p, nrm, col, Vector2(0.0, 0.0), h)
		var l := leaf.add(p + axis * s * 0.45 - across * s * 0.3, nrm, col, Vector2(-1.0, 0.5), h)
		var tip := leaf.add(p + axis * s, nrm, col, Vector2(0.0, 1.0), h)
		var r := leaf.add(p + axis * s * 0.45 + across * s * 0.3, nrm, col, Vector2(1.0, 0.5), h)
		leaf.tri(base, l, tip)
		leaf.tri(base, tip, r)


# ---- small plants -----------------------------------------------------------------

## A bush: a few stems from the ground, leaves bunched over them.
static func bush(seed_value: int, bark_mat: Material, leaf_mat: Material, leaf_col: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := Builder.new()
	var leaf := Builder.new()
	var H := rng.randf_range(0.7, 1.5)
	var c := Vector3(0.0, H * 0.55, 0.0)
	for i in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5).normalized()
		var pts := PackedVector3Array([Vector3.ZERO, d * H * 0.5 + Vector3(rng.randf_range(-0.1, 0.1), 0.0, 0.0), d * H])
		tube(bark, pts, PackedFloat32Array([0.025, 0.018, 0.008]), 3, Color(0.25, 0.2, 0.15), 0.4, 0.3)
		_leaves(leaf, rng, pts, c, H * 2.0, leaf_col, false)
	return _mesh(bark, leaf, bark_mat, leaf_mat)


## A clump of grass blades; `flowers` adds small coloured heads.
static func grass(seed_value: int, leaf_mat: Material, col: Color, height: float, blades: int, flowers := Color(0, 0, 0, 0)) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	for i in blades:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.14)
		var lean_dir := Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0.0, sin(a + rng.randf_range(-0.6, 0.6)))
		var h := height * rng.randf_range(0.5, 1.15)
		var bend := rng.randf_range(0.1, 0.45)
		var pts := PackedVector3Array()
		var w := PackedFloat32Array()
		var width := rng.randf_range(0.004, 0.008) * (height / 0.5)
		for s in 5:
			var k := float(s) / 4.0
			pts.append(base + Vector3.UP * h * k + lean_dir * h * bend * k * k)
			w.append(width * (1.0 - k * 0.92))
		var side := lean_dir.cross(Vector3.UP).normalized()
		grass_blade(b, pts, side, w, _col(col, rng, 0.18, 1.0), 0.35, 1.0)
		if flowers.a > 0.0 and i % 4 == 0:
			var top := pts[4]
			var fc := _col(flowers, rng, 0.08, 1.0)
			var centre := b.add(top + Vector3.UP * 0.01, Vector3.UP, fc, Vector2(0.0, 0.0), Vector2(top.y, 1.0))
			for p in 5:
				var pa := TAU * float(p) / 5.0
				var pb := TAU * (float(p) + 0.5) / 5.0
				var e0 := b.add(top + Vector3(cos(pa), 0.15, sin(pa)) * 0.035, Vector3.UP, fc, Vector2(1.0, 1.0), Vector2(top.y, 1.0))
				var e1 := b.add(top + Vector3(cos(pb), 0.15, sin(pb)) * 0.035, Vector3.UP, fc, Vector2(1.0, 1.0), Vector2(top.y, 1.0))
				b.tri(centre, e0, e1)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, leaf_mat)
	return m


## A rock: a lumpy sphere with a few flat fractured faces, sunk into the ground.
static func rock(seed_value: int, mat: Material, col: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.frequency = 0.9
	fn.fractal_octaves = 4
	var planes: Array[Vector4] = []
	for i in 4:
		var pn := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.72, 0.92)))
	var sphere := SphereMesh.new()
	sphere.radial_segments = 20
	sphere.rings = 12
	var src: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	var squash := rng.randf_range(0.55, 0.85)
	for i in verts.size():
		var p := verts[i] * 2.0                    # unit radius
		var r := 1.0 + fn.get_noise_3dv(p * 1.3) * 0.45
		p *= r
		for pl in planes:
			var pn := Vector3(pl.x, pl.y, pl.z)
			var d := p.dot(pn)
			if d > pl.w:
				p -= pn * (d - pl.w)
		p.y *= squash
		out[i] = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	for i in idx.size():
		var p := out[idx[i]]
		var ao := clampf(0.55 + 0.45 * (p.length() - 0.7), 0.3, 1.0) * clampf(0.5 + p.y, 0.35, 1.0)
		st.set_color(Color(col.r, col.g, col.b, ao))
		st.set_uv2(Vector2(0.0, 0.0))
		st.add_vertex(p)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m
