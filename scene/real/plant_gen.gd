class_name PlantGen
extends RefCounted
## Procedural plants and rocks for the realistic look, built from code in the
## manner of Abyssal Garden (MIT, Noniv/abyssal-garden): trunks and limbs are
## tubes swept along jittered curves with recursive branching; foliage is flat
## cards, each showing a whole cluster of leaves (a spruce bough, a spray of
## twigs) from the leaf atlas, whose source shapes are also built here
## (atlas_cells) and drawn into textures once by PlantBake.
##
## A tree has a close-up version (lod 0: bark surface 0, cards surface 1), a
## middle-distance one (lod 1: far fewer, larger cards, the wood riding in
## the same surface) and a shadow caster (lod 2: a handful of big cards
## facing the sky, so the sun's shadow maps are not filled many times over)
## from the same seed, so their outlines match.
## Vertex data:
##   COLOR.rgb  base colour       COLOR.a  baked ambient occlusion (0 dark .. 1 open)
##   UV         bark: x around, y metres along; cards: the atlas (x < 0: solid wood in a card surface)
##   UV2        x height above the root in metres (sway), y flutter weight (0 wood .. 1 leaf)
##   cards also: NORMAL the card's face, TANGENT its right, CUSTOM0 the normal bent to the crown's outside

## The leaf atlas: 4 x 4 square cells.
const ATLAS_COLS := 4
const ATLAS_ROWS := 4
const LEAF_A := 0        ## broadleaf clusters, three arrangements
const LEAF_B := 1
const LEAF_C := 2
const LEAF_SMALL := 3    ## fine small leaves (palo verde, creosote)
const BIRCH_A := 4       ## long hanging sprays of small leaves
const BIRCH_B := 5
const TWIG_A := 6        ## bare twigs
const TWIG_B := 7
const SPRUCE_A := 8      ## a spruce bough from above
const SPRUCE_B := 9
const HANG_A := 10       ## the twigs hanging under a bough, from the side
const HANG_B := 11
const GRASS_A := 12      ## a tuft of grass from the side
const GRASS_B := 13


class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var cards := false                  ## a card surface: tangents and bent normals too
	var tg := PackedFloat32Array()
	var bent := PackedFloat32Array()

	func add(p: Vector3, nrm: Vector3, col: Color, a: Vector2, b: Vector2) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(a)
		uv2.append(b)
		if cards:
			tg.append(1.0); tg.append(0.0); tg.append(0.0); tg.append(1.0)
			bent.append(nrm.x); bent.append(nrm.y); bent.append(nrm.z)
		return v.size() - 1

	## A card's corner: face normal, tangent (the card's right) and the bent normal.
	func add_card(p: Vector3, face: Vector3, right: Vector3, col: Color, a: Vector2, b: Vector2, bend: Vector3) -> int:
		v.append(p)
		n.append(face)
		c.append(col)
		uv.append(a)
		uv2.append(b)
		tg.append(right.x); tg.append(right.y); tg.append(right.z); tg.append(1.0)
		bent.append(bend.x); bent.append(bend.y); bent.append(bend.z)
		return v.size() - 1

	## Clockwise front faces, as Godot expects.
	func tri(a: int, b: int, cc: int) -> void:
		idx.append(a)
		idx.append(cc)
		idx.append(b)

	## A triangle whose front faces along `face`, whatever order its corners come in.
	func tri_facing(a: int, b: int, cc: int, face: Vector3) -> void:
		if (v[b] - v[a]).cross(v[cc] - v[a]).dot(face) > 0.0:
			idx.append(a); idx.append(cc); idx.append(b)
		else:
			idx.append(a); idx.append(b); idx.append(cc)

	## Everything added since `from` is solid wood inside a card surface.
	func mark_solid(from: int) -> void:
		for i in range(from, uv.size()):
			uv[i] = Vector2(-1.0, uv[i].y)

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
		if cards:
			arr[Mesh.ARRAY_TANGENT] = tg
			arr[Mesh.ARRAY_CUSTOM0] = bent
		return arr

	func flags() -> int:
		return (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) if cards else 0

	func tri_count() -> int:
		return idx.size() / 3


static func _mesh(bark: Builder, leaf: Builder, bark_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	for pair: Array in [[bark, bark_mat], [leaf, leaf_mat]]:
		var b: Builder = pair[0]
		if b == null or b.empty():
			continue
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays(), [], {}, b.flags())
		m.surface_set_material(m.get_surface_count() - 1, pair[1])
	return m


static func _cards() -> Builder:
	var b := Builder.new()
	b.cards = true
	return b


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




static func _col(base: Color, rng: RandomNumberGenerator, spread: float, ao: float) -> Color:
	var c := Color(base.r * rng.randf_range(1.0 - spread, 1.0 + spread),
		base.g * rng.randf_range(1.0 - spread, 1.0 + spread),
		base.b * rng.randf_range(1.0 - spread, 1.0 + spread), ao)
	return c


# ---- cards ----------------------------------------------------------------------

## Where a cell sits in the leaf atlas (a hair inside its edges, so its
## neighbours never bleed in).
static func cell_uv(cell: int) -> Rect2:
	var w := 1.0 / ATLAS_COLS
	var h := 1.0 / ATLAS_ROWS
	var inset := 0.006
	return Rect2((float(cell % ATLAS_COLS) + inset) * w, (float(cell / ATLAS_COLS) + inset) * h, w * (1.0 - 2.0 * inset), h * (1.0 - 2.0 * inset))


## One flat card showing an atlas cell: `o` the middle of its bottom edge
## (where the cluster's twig starts), `right` half its width, `up` its height.
## aos: baked occlusion at bottom-left, bottom-right, top-left, top-right.
static func card(b: Builder, o: Vector3, right: Vector3, up: Vector3, cell: int, col: Color, aos: Array,
		crown_c: Vector3, flutter: float) -> void:
	var r := cell_uv(cell)
	var face := right.cross(up).normalized()
	var rn := right.normalized()
	var corners := [o - right, o + right, o - right + up, o + right + up]
	var uvs := [Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)]
	var first := b.v.size()
	for i in 4:
		var p: Vector3 = corners[i]
		var bend := ((p - crown_c).normalized() * 0.8 + Vector3.UP * 0.35).normalized()
		var cc := col
		cc.a = float(aos[i])
		b.add_card(p, face, rn, cc, uvs[i], Vector2(maxf(p.y, 0.0), flutter * (0.35 if i < 2 else 1.0)), bend)
	b.tri_facing(first, first + 2, first + 3, face)
	b.tri_facing(first, first + 3, first + 1, face)


## How open to the sky a point of a crown is: dark deep inside and low down.
static func _crown_ao(p: Vector3, crown_c: Vector3, H: float) -> float:
	var depth := clampf((p - crown_c).length() / (H * 0.35), 0.0, 1.0)
	return clampf(0.25 + 0.75 * depth, 0.0, 1.0) * clampf(0.6 + 0.4 * (p.y / H), 0.0, 1.0)


# ---- spruce ---------------------------------------------------------------------

## A spruce or fir: tapered trunk, whorls of drooping boughs whose reach follows
## a cone, a dark core of inner branches, a leader at the top. Each bough is a
## bent card of needles with a skirt of hanging twigs across its outer part
## (and, close up, a curtain along it). lod 1 keeps every other bough, broader
## and flat; lod 2 (the shadow caster) a few boughs of every third whorl; all
## from the same seed.
static func spruce(seed_value: int, bark_mat: Material, leaf_mat: Material, needle := Color(0.06, 0.14, 0.07), lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var leaf := _cards()
	var bark := Builder.new() if lod == 0 else leaf
	var H := rng.randf_range(10.0, 15.0)
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	var r0 := H * 0.022
	var rings := 9 if lod == 0 else 5
	for i in rings:
		var k := float(i) / float(rings - 1)
		trunk.append(Vector3(0.0, H * k, 0.0) + lean * k * k)
		radii.append(lerpf(r0, 0.02, pow(k, 0.8)) * (1.0 + 0.4 * maxf(0.0, 0.12 - k) / 0.12))
	var first := bark.v.size()
	tube(bark, trunk, radii, 7 if lod == 0 else 4, Color(0.24, 0.18, 0.14), 0.45, 0.0, 0.2)
	if lod > 0:
		bark.mark_solid(first)
	var y0 := H * rng.randf_range(0.08, 0.16)
	var rmax := H * rng.randf_range(0.24, 0.3)
	var y := y0
	var spin := 0.0
	var w := 0
	while y < H - 0.7:
		var u := (y - y0) / (H - y0)
		var reach := rmax * pow(1.0 - u, 0.95) * (0.55 + 0.45 * smoothstep(0.0, 0.1, u))
		var axis := Vector3(0.0, y, 0.0) + lean * (y / H) * (y / H)
		# Each whorl has its own dice, so the far version's whorls are the close-up's.
		var wr := RandomNumberGenerator.new()
		wr.seed = seed_value * 7919 + w
		var count := wr.randi_range(5, 7)
		spin += rng.randf_range(0.4, 1.2)
		var gap := rng.randf_range(0.4, 0.6) * (0.75 + 0.5 * (1.0 - u))
		for j in count:
			var ang := spin + TAU * float(j) / float(count) + wr.randf_range(-0.25, 0.25)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var L := (reach * wr.randf_range(0.8, 1.12) + 0.4) * (1.0 if lod == 0 else 1.12)
			# The far versions keep every other bough of every whorl (not whole whorls: that reads as stacked plates).
			# The shadow caster makes do with a few boughs of every third whorl (and the core).
			var keep := (j + w) % 2 == 0 if lod == 1 else (w % 3 == 0 and j % 2 == 0)
			_bough(leaf, wr, axis, dir, L, needle, u, lod, gap * (1.0 if lod == 0 else 2.3), lod == 0 or keep)
		if lod == 0 and u < 0.85:
			# Close up, shorter boughs between the whorls fill the inside, so the eye
			# meets needles, not a bare pole, when it looks in under the big boughs.
			var ir := RandomNumberGenerator.new()
			ir.seed = seed_value * 104729 + w
			var inner := Vector3(0.0, y + gap * 0.5, 0.0) + lean * (y / H) * (y / H)
			for j in 3:
				var ang := spin + 1.0 + TAU * float(j) / 3.0 + ir.randf_range(-0.4, 0.4)
				_bough(leaf, ir, inner, Vector3(cos(ang), 0.0, sin(ang)), reach * ir.randf_range(0.4, 0.6) + 0.3, needle, u * 0.5, 0, 0.0, true)
		y += gap
		w += 1
	# Further off, a dark core of inner branches round the trunk, so the gaps
	# between boughs show green depth, not sky and a bare pole.
	var core := PackedVector3Array()
	var core_r := PackedFloat32Array()
	for i in 6:
		var k := float(i) / 5.0
		var yy := lerpf(y0 + 0.3, H - 1.0, k)
		core.append(Vector3(0.0, yy, 0.0) + lean * (yy / H) * (yy / H))
		core_r.append(rmax * 0.28 * pow(1.0 - k, 0.9) * (0.5 + 0.5 * smoothstep(0.0, 0.2, k)) + 0.05)
	if lod > 0:      # (close up the inner boughs do this, and the trunk may show)
		first = leaf.v.size()
		tube(leaf, core, core_r, 5, Color(needle.r * 0.55, needle.g * 0.55, needle.b * 0.55), 0.3, 0.3, 0.0)
		leaf.mark_solid(first)
		for i in range(first, leaf.c.size()):
			leaf.c[i].a = 0.32
	# Leader: two crossed upright cards.
	var top := Vector3(0.0, H - 1.5, 0.0) + lean * 0.8
	var lc := _col(needle, rng, 0.1, 1.0)
	for s in (2 if lod == 0 else 1):
		var side := Vector3(cos(s * PI * 0.5), 0.0, sin(s * PI * 0.5))
		card(leaf, top, side * 0.6, Vector3.UP * 1.9, SPRUCE_A if s == 0 else SPRUCE_B, lc, [0.8, 0.8, 1.0, 1.0], top - Vector3.UP * 2.0, 1.0)
	return _mesh(bark if lod == 0 else null, leaf, bark_mat, leaf_mat)


## One spruce bough: it droops and lifts again at the tip, its sides hang a
## little, and (close up) a curtain of twigs hangs below.
static func _bough(leaf: Builder, rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, L: float, needle: Color,
		u: float, lod: int, gap: float, draw: bool) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	# Low boughs slope well down, the young ones near the top reach out and up.
	var rise := lerpf(-0.5, 0.12, u) + rng.randf_range(-0.08, 0.08)
	var droop := rng.randf_range(0.15, 0.35) * L
	var upturn := rng.randf_range(0.1, 0.3) * L
	var roll := rng.randf_range(-0.2, 0.2)
	var col := _col(needle, rng, 0.14, 1.0)
	var cell := SPRUCE_A if rng.randf() < 0.5 else SPRUCE_B
	var hang_cell := HANG_A if rng.randf() < 0.5 else HANG_B
	var hang := rng.randf_range(0.4, 0.6) * L
	if not draw:
		return
	var segs := 3 if lod == 0 else 2
	var hw := L * 0.46 * (1.0 if lod == 0 else 1.45)
	var r := cell_uv(cell)
	var ao0 := 0.12 + 0.3 * u
	var bend := (dir * 0.55 + Vector3.UP * 0.75).normalized()
	var pts := PackedVector3Array()
	for i in segs + 1:
		var k := float(i) / float(segs)
		var sag := droop * (0.25 * k + 0.75 * k * k) - upturn * k * k * k * 0.6   # sags, then flicks up a little at the tip
		pts.append(origin + dir * L * k + Vector3.UP * (rise * L * k - sag))
	var first := leaf.v.size()
	var across := 3 if lod == 0 else 2
	for i in segs + 1:
		var k := float(i) / float(segs)
		var tgt := (pts[mini(i + 1, segs)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := side.cross(tgt).normalized()
		var sd := (side + nrm * roll).normalized()
		var fold := hw * 0.24
		var cc := col
		cc.a = lerpf(ao0, 1.0, pow(k, 0.7))
		var vv := lerpf(r.end.y, r.position.y, k)
		var h := Vector2(maxf(pts[i].y, 0.0), k)
		if across == 3:
			leaf.add_card(pts[i] - sd * hw - nrm * fold, (nrm - sd * 0.35).normalized(), sd, cc, Vector2(r.position.x, vv), h, bend)
			leaf.add_card(pts[i], nrm, sd, cc, Vector2(r.position.x + r.size.x * 0.5, vv), h, bend)
			leaf.add_card(pts[i] + sd * hw - nrm * fold, (nrm + sd * 0.35).normalized(), sd, cc, Vector2(r.end.x, vv), h, bend)
		else:
			leaf.add_card(pts[i] - sd * hw - nrm * fold * 0.5, nrm, sd, cc, Vector2(r.position.x, vv), h, bend)
			leaf.add_card(pts[i] + sd * hw - nrm * fold * 0.5, nrm, sd, cc, Vector2(r.end.x, vv), h, bend)
	for i in segs:
		var nrm := leaf.n[first + i * across + (1 if across == 3 else 0)]
		for a in across - 1:
			var p0 := first + i * across + a
			var p1 := p0 + across
			leaf.tri_facing(p0, p1, p0 + 1, nrm)
			leaf.tri_facing(p0 + 1, p1, p1 + 1, nrm)
	if L < 0.55 or lod == 2:
		return
	var hr := cell_uv(hang_cell)
	var hc := col.darkened(0.12)
	var ao1 := lerpf(ao0, 1.0, 0.5)
	# A skirt across the bough's outer part, facing out: the hanging twigs that
	# make a spruce's side (boughs pointing at the eye would otherwise be edge-on).
	var sk := pts[segs - 1].lerp(pts[segs], 0.35)
	var sw := side * hw * 0.9
	# Long enough to reach the whorl below, so the tree's side closes.
	var fall := maxf(hang * 1.15, gap * 1.25)
	var drop := Vector3.DOWN * fall + dir * fall * 0.18
	var sb := (dir * 0.75 + Vector3.UP * 0.45).normalized()
	var f3 := leaf.v.size()
	hc.a = 0.95
	leaf.add_card(sk - sw, dir, -side, hc, Vector2(hr.end.x, hr.position.y), Vector2(maxf(sk.y, 0.0), 0.5), sb)
	leaf.add_card(sk + sw, dir, -side, hc, Vector2(hr.position.x, hr.position.y), Vector2(maxf(sk.y, 0.0), 0.5), sb)
	hc.a = 0.75
	leaf.add_card(sk - sw + drop, dir, -side, hc, Vector2(hr.end.x, hr.end.y), Vector2(maxf(sk.y - hang, 0.0), 1.0), sb)
	leaf.add_card(sk + sw + drop, dir, -side, hc, Vector2(hr.position.x, hr.end.y), Vector2(maxf(sk.y - hang, 0.0), 1.0), sb)
	leaf.tri_facing(f3, f3 + 1, f3 + 2, dir)
	leaf.tri_facing(f3 + 1, f3 + 3, f3 + 2, dir)
	if lod > 0:
		return
	# Close up, a curtain along the bough as well: twigs hanging under its outer two thirds.
	var tl := pts[1]
	var tr := pts[segs]
	var along := (tr - tl).normalized()
	var face := along.cross(Vector3.UP).normalized()
	var hb := (dir * 0.8 + Vector3.UP * 0.3).normalized()
	var f2 := leaf.v.size()
	hc.a = ao1 * 0.9
	leaf.add_card(tl, face, along, hc, Vector2(hr.position.x, hr.position.y), Vector2(maxf(tl.y, 0.0), 0.4), hb)
	hc.a = 0.95
	leaf.add_card(tr, face, along, hc, Vector2(hr.end.x, hr.position.y), Vector2(maxf(tr.y, 0.0), 0.9), hb)
	hc.a = ao1 * 0.7
	leaf.add_card(tl + Vector3.DOWN * hang, face, along, hc, Vector2(hr.position.x, hr.end.y), Vector2(maxf(tl.y - hang, 0.0), 1.0), hb)
	hc.a = 0.8
	leaf.add_card(tr + Vector3.DOWN * hang * 0.8, face, along, hc, Vector2(hr.end.x, hr.end.y), Vector2(maxf(tr.y - hang, 0.0), 1.0), hb)
	leaf.tri_facing(f2, f2 + 1, f2 + 2, face)
	leaf.tri_facing(f2 + 1, f2 + 3, f2 + 2, face)


# ---- broadleaf ------------------------------------------------------------------

## What a branching tree is being built with.
class Crown:
	var rng: RandomNumberGenerator
	var wood: Builder                 ## trunk and limbs (lod 1: the card surface itself)
	var leaf: Builder
	var lod := 0
	var bark_col := Color(0.26, 0.21, 0.16)
	var leaf_col := Color(0.12, 0.24, 0.05)
	var crown_c := Vector3.ZERO
	var H := 8.0
	var birch := false
	var bare := false
	var cells: Array = [LEAF_A, LEAF_B, LEAF_C]
	var card_size := 1.3
	var cards_per: Array = [6, 5, 3]   ## cards on a leafy branch, by its depth (0 the outer twigs)
	var count := 0                     ## cards so far (lod 1 keeps every third, larger)


## A broadleaf tree (oak-ish, or a birch with `birch`): a trunk that forks into
## limbs, branches recursing three levels, cards of leaf clusters around the
## outer branches (bare: sprays of twigs instead).
static func broadleaf(seed_value: int, bark_mat: Material, leaf_mat: Material, leaf_col: Color, bark_col: Color,
		birch := false, bare := false, lod := 0) -> ArrayMesh:
	var t := Crown.new()
	t.rng = RandomNumberGenerator.new()
	t.rng.seed = seed_value
	t.leaf = _cards()
	t.wood = Builder.new() if lod == 0 else t.leaf
	t.lod = lod
	t.bark_col = bark_col
	t.leaf_col = leaf_col
	t.birch = birch
	t.bare = bare
	if birch:
		t.cells = [BIRCH_A, BIRCH_B]
		t.card_size = 1.25
	if bare:
		t.cells = [TWIG_A, TWIG_B]
		t.cards_per = [2, 1, 0]
		t.card_size = 1.5
	var rng := t.rng
	var H := rng.randf_range(7.0, 11.0) * (1.25 if birch else 1.0)
	t.H = H
	var fork := H * rng.randf_range(0.3, 0.42) * (1.3 if birch else 1.0)
	var r0 := H * (0.018 if birch else 0.03)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 6:
		var k := float(i) / 5.0
		pts.append(Vector3(0.0, fork * k, 0.0) + lean * k * k * 0.5)
		radii.append(r0 * (1.0 - 0.25 * k) * (1.0 + 0.5 * maxf(0.0, 0.15 - k) / 0.15))
	var first := t.wood.v.size()
	tube(t.wood, pts, radii, 8 if lod == 0 else 5, bark_col, 0.4, 0.0, 0.2)
	if lod > 0:
		t.wood.mark_solid(first)
	t.crown_c = Vector3(0.0, fork + (H - fork) * 0.5, 0.0) + lean * 0.5
	var limbs := rng.randi_range(2, 3) if birch else rng.randi_range(3, 4)
	var spin := rng.randf() * TAU
	for i in limbs:
		var a := spin + TAU * float(i) / float(limbs) + rng.randf_range(-0.3, 0.3)
		var out := rng.randf_range(0.25, 0.5) if birch else rng.randf_range(0.5, 0.85)
		var d := Vector3(cos(a) * out, 1.0, sin(a) * out).normalized()
		_branch(t, pts[pts.size() - 1], d, (H - fork) * rng.randf_range(0.5, 0.7), radii[radii.size() - 1] * 0.75, 3)
	return _mesh(t.wood if lod == 0 else null, t.leaf, bark_mat, leaf_mat)


static func _branch(t: Crown, start: Vector3, dir: Vector3, L: float, r: float, depth: int) -> void:
	var rng := t.rng
	var pts := PackedVector3Array([start])
	var radii := PackedFloat32Array([r])
	var d := dir
	var p := start
	var segs := 3
	for i in segs:
		d = (d + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.08, 0.15), rng.randf_range(-0.25, 0.25))).normalized()
		if t.birch and depth <= 1:
			d = (d + Vector3.DOWN * 0.35).normalized()    # birch twigs weep
		p += d * L / float(segs)
		pts.append(p)
		radii.append(r * (1.0 - 0.3 * float(i + 1) / float(segs)))
	# The finest twigs are drawn in the cards; the far version keeps only the limbs.
	if depth >= (1 if t.lod == 0 else 2):
		var sides: int = [3, 3, 4, 6][depth] if t.lod == 0 else depth + 1
		var first := t.wood.v.size()
		tube(t.wood, pts, radii, sides, t.bark_col, 0.5, 0.15 * float(3 - depth), 0.0)
		if t.lod > 0:
			t.wood.mark_solid(first)
	if depth <= 2:
		_leaf_cards(t, pts, depth)
	if depth == 0:
		return
	var kids := rng.randi_range(2, 3)
	for i in kids:
		var at := rng.randf_range(0.45, 1.0)
		var seg := clampi(int(at * segs), 1, segs)
		var o := pts[seg]
		var away := (o - t.crown_c)
		away.y = 0.0
		var nd := (d + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.6), rng.randf_range(-0.8, 0.8)) + away.normalized() * 0.4).normalized()
		_branch(t, o, nd, L * rng.randf_range(0.55, 0.75), radii[seg] * 0.7, depth - 1)


## Cards of leaves around a branch: each grows out and a little up (a birch's
## hang), facing mostly outward so the crown's outside is covered.
static func _leaf_cards(t: Crown, twig: PackedVector3Array, depth: int) -> void:
	var rng := t.rng
	var last := twig.size() - 1
	var twig_dir := (twig[last] - twig[0]).normalized()
	for i in int(t.cards_per[depth]):
		var k := rng.randf_range(0.3, 1.0)
		var f := k * float(last)
		var a := twig[int(floor(f))]
		var b := twig[mini(int(floor(f)) + 1, last)]
		var s := t.card_size * rng.randf_range(0.8, 1.25)
		var p := a.lerp(b, f - floor(f)) + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.3, 0.25), rng.randf_range(-0.35, 0.35)) * s
		var rnd := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var rnd2 := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var cell: int = t.cells[rng.randi() % t.cells.size()]
		var col := _col(t.leaf_col, rng, 0.13, 1.0)
		if rng.randf() < 0.12:
			col = col.lerp(Color(col.r * 1.5 + 0.03, col.g * 1.35 + 0.02, col.b, 1.0), 0.5)    # the odd paler, sunnier spray
		t.count += 1
		if t.lod > 0 and t.count % (3 if t.lod == 1 else 9) != 0:
			continue
		if t.lod > 0:
			s *= 1.85 if t.lod == 1 else 1.5
		var outward := (p - t.crown_c).normalized()
		var up := (twig_dir * 0.5 + outward * 0.6 + rnd * 0.55 + (Vector3.DOWN * 1.7 if t.birch else Vector3.UP * 0.2)).normalized()
		var face := (outward * 0.7 + Vector3.UP * 0.45 + rnd2 * 0.8).normalized()
		if t.lod == 2:
			# The shadow caster: broad cards lying across the crown, facing the sky.
			up = (outward * Vector3(1.0, 0.0, 1.0) + rnd * 0.4).normalized()
			face = (Vector3.UP + rnd2 * 0.3).normalized()
		var right := up.cross(face)
		if right.length() < 0.1:
			right = up.cross(Vector3.RIGHT)
		right = right.normalized()
		var hw := s * (0.36 if t.birch else 0.5)
		var hh := s * (1.25 if t.birch else 1.0)
		var o := p - up * hh * 0.4
		var aos := []
		for cp: Vector3 in [o - right * hw, o + right * hw, o - right * hw + up * hh, o + right * hw + up * hh]:
			aos.append(_crown_ao(cp, t.crown_c, t.H))
		card(t.leaf, o, right * hw, up * hh, cell, col, aos, t.crown_c, 1.0)


# ---- small plants -----------------------------------------------------------------

## A bush: a few stems from the ground, cards of leaves bunched over them (one surface).
static func bush(seed_value: int, leaf_mat: Material, leaf_col: Color, cells: Array = [LEAF_A, LEAF_B, LEAF_C], card_size := 0.85) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var H := rng.randf_range(0.7, 1.5)
	var c := Vector3(0.0, H * 0.45, 0.0)
	for i in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5).normalized()
		var pts := PackedVector3Array([Vector3.ZERO, d * H * 0.5 + Vector3(rng.randf_range(-0.1, 0.1), 0.0, 0.0), d * H])
		var first := b.v.size()
		tube(b, pts, PackedFloat32Array([0.025, 0.018, 0.008]), 3, Color(0.25, 0.2, 0.15), 0.4, 0.3)
		b.mark_solid(first)
		for k in 3:
			var s := card_size * (H / 1.1) * rng.randf_range(0.8, 1.25)
			var p := pts[1].lerp(pts[2], rng.randf_range(0.0, 1.0)) + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.2, 0.15), rng.randf_range(-0.25, 0.25)) * s
			var outward := (p - c).normalized()
			var up := (d * 0.6 + outward * 0.5 + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
			var face := (outward * 0.6 + Vector3.UP * 0.6 + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.4, 0.8), rng.randf_range(-0.8, 0.8))).normalized()
			var right := up.cross(face)
			if right.length() < 0.1:
				right = up.cross(Vector3.RIGHT)
			right = right.normalized() * s * 0.5
			var o := p - up * s * 0.45
			var aos := []
			for cp: Vector3 in [o - right, o + right, o - right + up * s, o + right + up * s]:
				aos.append(clampf(0.35 + 0.65 * (cp.y / H), 0.25, 1.0))
			card(b, o, right, up * s, cells[rng.randi() % cells.size()], _col(leaf_col, rng, 0.15, 1.0), aos, c, 1.0)
	return _mesh(null, b, null, leaf_mat)


# ---- the leaf atlas's source shapes ----------------------------------------------
# Each cell is drawn in x -0.5 .. 0.5, y 0 .. 1 (the cluster's twig starts at
# the bottom's middle), seen from +z; z only orders what lies over what.
# COLOR.rgb is a grey the card's own colour multiplies; COLOR.a is the shade,
# over 0.5 for leaf and under for wood (real_leaf.gdshaderinc reads it back).

static func _leaf_a(shade: float) -> float:
	return 0.5 + clampf(shade, 0.0, 1.0) * 0.5


static func _wood_a(shade: float) -> float:
	return clampf(shade, 0.0, 1.0) * 0.45


## One mesh per atlas cell (null where a cell is unused), in cell order.
static func atlas_cells() -> Array:
	var out := []
	out.resize(ATLAS_COLS * ATLAS_ROWS)
	var rng := RandomNumberGenerator.new()
	for cell in out.size():
		rng.seed = 9100 + cell
		var b: Builder = null
		match cell:
			LEAF_A:
				b = _cell_leaves(rng, 0.62, 0.1, 0.04, 2, 3)
			LEAF_B:
				b = _cell_leaves(rng, 0.7, 0.09, 0.036, 2, 3)
			LEAF_C:
				b = _cell_leaves(rng, 0.55, 0.11, 0.045, 2, 2)
			LEAF_SMALL:
				b = _cell_leaves(rng, 0.6, 0.045, 0.016, 3, 3)
			BIRCH_A, BIRCH_B:
				b = _cell_birch(rng)
			TWIG_A, TWIG_B:
				b = Builder.new()
				_bare2(b, rng, Vector2.ZERO, Vector2(0.0, 1.0), 0.36, 0.011, 4)
				_fit(b)
			SPRUCE_A, SPRUCE_B:
				b = _cell_spruce(rng)
			HANG_A, HANG_B:
				b = _cell_hang(rng)
			GRASS_A, GRASS_B:
				b = _cell_grass(rng)
		if b != null and not b.empty():
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
			out[cell] = m
	return out


## Scale and shift a cell's shapes to fill it (a small margin kept).
## `hang`: what hangs from the top edge keeps its top where it is.
static func _fit(b: Builder, max_x := 0.47, max_y := 0.96, hang := false) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in b.v:
		lo = lo.min(Vector2(p.x, p.y))
		hi = hi.max(Vector2(p.x, p.y))
	var s := minf(max_x / maxf(maxf(absf(lo.x), absf(hi.x)), 0.001), max_y / maxf(hi.y - lo.y, 0.001))
	for i in b.v.size():
		var p := b.v[i]
		b.v[i] = Vector3(p.x * s, (0.985 - (hi.y - p.y) * s) if hang else ((p.y - lo.y) * s + 0.015), p.z)


static func _twig2(b: Builder, pts: PackedVector2Array, w0: float, w1: float, z: float, grey: float) -> void:
	var count := pts.size()
	var first := b.v.size()
	var col := Color(grey, grey, grey, _wood_a(0.85))
	for i in count:
		var k := float(i) / float(count - 1)
		var d := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var perp := Vector2(-d.y, d.x)
		var w := maxf(lerpf(w0, w1, k), 0.0022)
		b.add(Vector3(pts[i].x - perp.x * w, pts[i].y - perp.y * w, z), Vector3(-perp.x * 0.6, -perp.y * 0.6, 0.8).normalized(), col, Vector2.ZERO, Vector2.ZERO)
		b.add(Vector3(pts[i].x + perp.x * w, pts[i].y + perp.y * w, z), Vector3(perp.x * 0.6, perp.y * 0.6, 0.8).normalized(), col, Vector2.ZERO, Vector2.ZERO)
	for i in count - 1:
		var r0 := first + i * 2
		b.tri(r0, r0 + 1, r0 + 2)
		b.tri(r0 + 1, r0 + 3, r0 + 2)


## The dense inner needles along a twig, as one soft dark strip under the drawn ones.
static func _body2(b: Builder, pts: PackedVector2Array, w0: float, w1: float, grey: float) -> void:
	var count := pts.size()
	var first := b.v.size()
	var col := Color(grey * 0.95, grey, grey * 0.9, _leaf_a(0.3))
	for i in count:
		var k := float(i) / float(count - 1)
		var d := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var perp := Vector2(-d.y, d.x)
		var w := lerpf(w0, w1, k)
		b.add(Vector3(pts[i].x - perp.x * w, pts[i].y - perp.y * w, -0.02), Vector3(-perp.x * 0.5, -perp.y * 0.5, 0.85).normalized(), col, Vector2.ZERO, Vector2.ZERO)
		b.add(Vector3(pts[i].x + perp.x * w, pts[i].y + perp.y * w, -0.02), Vector3(perp.x * 0.5, perp.y * 0.5, 0.85).normalized(), col, Vector2.ZERO, Vector2.ZERO)
	for i in count - 1:
		var r0 := first + i * 2
		b.tri(r0, r0 + 1, r0 + 2)
		b.tri(r0 + 1, r0 + 3, r0 + 2)


## A leaf: a pointed oval from p along dir, creased down its midrib, tilted at random.
static func _leaf2(b: Builder, rng: RandomNumberGenerator, p: Vector2, dir: Vector2, L: float, w: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var roll := rng.randf_range(-0.5, 0.5)
	var pitch := rng.randf_range(-0.4, 0.4)
	var n0 := Vector3(perp.x * roll + dir.x * pitch, perp.y * roll + dir.y * pitch, 1.0).normalized()
	var nl := (n0 - Vector3(perp.x, perp.y, 0.0) * 0.4).normalized()
	var nr := (n0 + Vector3(perp.x, perp.y, 0.0) * 0.4).normalized()
	var z := rng.randf() * 0.08
	var grey := rng.randf_range(0.66, 1.0) * (0.8 + 2.5 * z)
	var a := _leaf_a(0.4 + 7.5 * z)
	var col := Color(grey * rng.randf_range(0.94, 1.05), grey, grey * rng.randf_range(0.82, 1.0), a)
	var rib := Color(minf(col.r * 1.12, 1.0), minf(col.g * 1.12, 1.0), col.b, a)
	var edge := Color(col.r * 0.9, col.g * 0.92, col.b * 0.9, a)
	var first := b.v.size()
	var rows := 7
	for i in rows:
		var t := [0.0, 0.1, 0.26, 0.45, 0.66, 0.86, 1.0][i] as float
		var half := w * pow(sin(PI * pow(t, 0.72)), 0.85) * (1.06 if i % 2 == 0 else 0.94)
		var m := p + dir * L * t
		b.add(Vector3(m.x - perp.x * half, m.y - perp.y * half, z), nl, edge, Vector2.ZERO, Vector2.ZERO)
		b.add(Vector3(m.x, m.y, z + 0.002), n0, rib, Vector2.ZERO, Vector2.ZERO)
		b.add(Vector3(m.x + perp.x * half, m.y + perp.y * half, z), nr, edge, Vector2.ZERO, Vector2.ZERO)
	for i in rows - 1:
		var r0 := first + i * 3
		var r1 := r0 + 3
		b.tri(r0, r1, r0 + 1)
		b.tri(r0 + 1, r1, r1 + 1)
		b.tri(r0 + 1, r1 + 1, r0 + 2)
		b.tri(r0 + 2, r1 + 1, r1 + 2)


## A twig with leaves alternating up it and one at its tip; side twigs the same.
static func _spray(b: Builder, rng: RandomNumberGenerator, p: Vector2, dir: Vector2, L: float, depth: int,
		leaf_len: float, leaf_w: float, kids: int, wander := 0.18) -> void:
	var segs := 4
	var pts := PackedVector2Array([p])
	var d := dir
	var q := p
	for i in segs:
		d = d.rotated(rng.randf_range(-wander, wander))
		q += d * L / float(segs)
		pts.append(q)
	_twig2(b, pts, 0.004 + 0.0025 * depth, 0.002, -0.01, 0.9)
	var step := maxf(leaf_len * 0.42, 0.02)
	var t := leaf_len * 0.6
	var side := 1.0
	while t < L:
		var f := t / L * float(segs)
		var i0 := mini(int(f), segs - 1)
		var o := pts[i0].lerp(pts[i0 + 1], f - float(i0))
		var td := (pts[i0 + 1] - pts[i0]).normalized()
		_leaf2(b, rng, o, td.rotated(side * rng.randf_range(0.65, 1.2)), leaf_len * rng.randf_range(0.75, 1.15), leaf_w)
		side = -side
		t += step * rng.randf_range(0.8, 1.2)
	_leaf2(b, rng, pts[segs], d, leaf_len * 1.1, leaf_w)
	if depth > 0:
		for i in kids:
			var at := rng.randf_range(0.15, 0.75) * float(segs)
			var i0 := mini(int(at), segs - 1)
			var o := pts[i0].lerp(pts[i0 + 1], at - float(i0))
			var s := 1.0 if i % 2 == 0 else -1.0
			_spray(b, rng, o, d.rotated(s * rng.randf_range(0.5, 0.95)), L * rng.randf_range(0.5, 0.72), depth - 1, leaf_len, leaf_w, kids, wander)


static func _cell_leaves(rng: RandomNumberGenerator, L: float, leaf_len: float, leaf_w: float, depth: int, kids: int) -> Builder:
	var b := Builder.new()
	_spray(b, rng, Vector2.ZERO, Vector2(0.0, 1.0), L, depth, leaf_len, leaf_w, kids)
	_fit(b)
	return b


## A birch's spray: a few long thin twigs running nearly together, small leaves all the way.
static func _cell_birch(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	for i in 4:
		var d := Vector2(0.0, 1.0).rotated(rng.randf_range(-0.28, 0.28))
		_spray(b, rng, Vector2(rng.randf_range(-0.03, 0.03), 0.0), d, rng.randf_range(0.6, 0.95), 1 if i < 2 else 0, 0.07, 0.03, 2, 0.1)
	_fit(b, 0.47, 0.96)
	return b


static func _bare2(b: Builder, rng: RandomNumberGenerator, p: Vector2, dir: Vector2, L: float, w: float, depth: int) -> void:
	var pts := PackedVector2Array([p])
	var d := dir
	var q := p
	for i in 3:
		d = d.rotated(rng.randf_range(-0.2, 0.2))
		q += d * L / 3.0
		pts.append(q)
	_twig2(b, pts, w, w * 0.62, 0.001 * depth, rng.randf_range(0.8, 1.0))
	if depth == 0:
		return
	for i in rng.randi_range(2, 3):
		var o := pts[rng.randi_range(1, 3)]
		var s := 1.0 if i % 2 == 0 else -1.0
		_bare2(b, rng, o, d.rotated(s * rng.randf_range(0.3, 0.8)), L * rng.randf_range(0.55, 0.78), w * 0.6, depth - 1)


## Needles both sides of a twig's stretch from a to c, raked forward.
static func _needles2(b: Builder, rng: RandomNumberGenerator, a: Vector2, c: Vector2, length: float, step: float, grey: float) -> void:
	var seg := c - a
	var L := seg.length()
	if L < 0.001:
		return
	var d := seg / L
	var count := int(L / step) + 1
	var bw := 0.0045
	for i in count:
		var q := a + d * L * (float(i) + rng.randf()) / float(count)
		for s: float in [-1.0, 1.0]:
			var nd := d.rotated(s * rng.randf_range(0.55, 1.05))
			var ln := length * rng.randf_range(0.7, 1.15)
			var z := rng.randf() * 0.05
			var g := grey * rng.randf_range(0.7, 1.05) * (0.8 + 4.0 * z)
			var col := Color(g * 0.95, g, g * 0.9, _leaf_a(0.45 + 11.0 * z))
			var nrm := Vector3(nd.x * 0.5 + s * d.y * 0.2, nd.y * 0.5 - s * d.x * 0.2, 0.8).normalized()
			var i0 := b.add(Vector3(q.x - d.x * bw, q.y - d.y * bw, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
			b.add(Vector3(q.x + d.x * bw, q.y + d.y * bw, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
			var tip := q + nd * ln
			b.add(Vector3(tip.x, tip.y, z), nrm, Color(minf(col.r * 1.15, 1.0), minf(col.g * 1.15, 1.0), col.b, col.a), Vector2.ZERO, Vector2.ZERO)
			b.tri(i0, i0 + 1, i0 + 2)


## A spruce twig with its needles and (depth > 0) side twigs; `curl` bends it as it goes.
static func _spruce_twig(b: Builder, rng: RandomNumberGenerator, o: Vector2, dir: Vector2, L: float, depth: int, curl: float, grey: float) -> void:
	var segs := 4
	var pts := PackedVector2Array([o])
	var d := dir
	var q := o
	for i in segs:
		d = d.rotated(curl + rng.randf_range(-0.05, 0.05))
		q += d * L / float(segs)
		pts.append(q)
	_body2(b, pts, 0.034 if depth > 0 else 0.022, 0.012, grey * 0.62)
	_twig2(b, pts, 0.0035 + 0.0025 * depth, 0.0018, -0.01, 0.85)
	for i in segs:
		# New growth at the tips is paler.
		_needles2(b, rng, pts[i], pts[i + 1], 0.03, 0.0085, grey * lerpf(0.82, 1.12, float(i) / float(segs - 1)))
	if depth <= 0:
		return
	var t := 0.22
	var side := 1.0
	while t < 0.9:
		var f := t * float(segs)
		var i0 := mini(int(f), segs - 1)
		var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
		var td := (pts[i0 + 1] - pts[i0]).normalized()
		_spruce_twig(b, rng, p, td.rotated(side * rng.randf_range(0.6, 0.85)), L * 0.42 * (1.0 - t * 0.55), depth - 1, -side * 0.04, grey)
		side = -side
		t += rng.randf_range(0.13, 0.19)


## A spruce bough from above: a stem with side twigs raked forward, longest a
## third of the way out, all in needles.
static func _cell_spruce(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var bow := rng.randf_range(-0.03, 0.03)
	var main := PackedVector2Array()
	for i in 9:
		var k := float(i) / 8.0
		main.append(Vector2(bow * sin(PI * k), 0.97 * k))
	_body2(b, main, 0.045, 0.015, 0.6)
	_twig2(b, main, 0.011, 0.003, -0.012, 0.85)
	for i in 8:
		_needles2(b, rng, main[i], main[i + 1], 0.032, 0.009, 0.9)
	var t := 0.05
	var s := 1.0
	while t < 0.95:
		var reach := 0.47 * pow(1.0 - t, 0.7) * smoothstep(-0.3, 0.12, t) + 0.025
		var ang := lerpf(1.1, 0.65, t)
		_spruce_twig(b, rng, Vector2(bow * sin(PI * t / 0.97), t), Vector2(0.0, 1.0).rotated(-s * ang), reach, 1, s * 0.07, rng.randf_range(0.82, 1.0))
		s = -s
		t += rng.randf_range(0.03, 0.043)
	_fit(b)
	return b


## The twigs hanging under a bough, from the side: the bough runs along the top.
static func _cell_hang(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var top := 0.955
	_twig2(b, PackedVector2Array([Vector2(-0.48, top), Vector2(0.0, top - 0.01), Vector2(0.48, top)]), 0.008, 0.005, -0.012, 0.85)
	_needles2(b, rng, Vector2(-0.48, top), Vector2(0.48, top), 0.03, 0.01, 0.9)
	var x := -0.44
	while x < 0.46:
		var reach := rng.randf_range(0.3, 0.88) * (1.0 - 0.5 * absf(x))
		_spruce_twig(b, rng, Vector2(x, top), Vector2(rng.randf_range(-0.12, 0.25), -1.0).normalized(), reach, 1, rng.randf_range(-0.03, 0.03), rng.randf_range(0.8, 1.0))
		x += rng.randf_range(0.05, 0.085)
	_fit(b, 0.47, 0.96, true)
	return b


## A tuft of grass from the side: curved tapering blades, darker at the root.
static func _cell_grass(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	for i in 28:
		var x0 := rng.randf_range(-0.34, 0.34)
		var h := rng.randf_range(0.4, 0.95)
		var lean := rng.randf_range(-0.22, 0.22) + x0 * 0.35
		var w := rng.randf_range(0.011, 0.019)
		var z := rng.randf() * 0.05
		var g := rng.randf_range(0.75, 1.0)
		var first := b.v.size()
		for r in 6:
			var k := float(r) / 5.0
			var p := Vector2(x0 + lean * k * k * h, h * k)
			var half := w * (1.0 - pow(k, 1.5) * 0.93)
			var grey := g * lerpf(0.55, 1.0, k)
			var col := Color(grey, grey, grey * 0.92, _leaf_a(lerpf(0.3, 1.0, k)))
			b.add(Vector3(p.x - half, p.y, z), Vector3(-0.35, 0.0, 0.94), col, Vector2.ZERO, Vector2.ZERO)
			b.add(Vector3(p.x + half, p.y, z), Vector3(0.35, 0.0, 0.94), col, Vector2.ZERO, Vector2.ZERO)
		for r in 5:
			var r0 := first + r * 2
			b.tri(r0, r0 + 1, r0 + 2)
			b.tri(r0 + 1, r0 + 3, r0 + 2)
	_fit(b)
	return b


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



# ---- Sonoran desert (Tucson) -------------------------------------------------------

## A tube whose cross-section is pleated: `ribs` ridges `rib_depth` deep, the
## grooves baked darker (COLOR.a). For saguaros and barrel cacti.
static func ribbed_tube(b: Builder, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, ribs: int,
		rib_depth: float, col: Color) -> void:
	var count := pts.size()
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
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var rib := cos(float(ribs) * a)
			var dir := nrm * cos(a) + bn * sin(a)
			var r := radii[i] * (1.0 + rib_depth * rib)
			# Normal tilted across the pleat so each rib shades round.
			var side_dir := -nrm * sin(a) + bn * cos(a)
			var n := (dir - side_dir * sin(float(ribs) * a) * rib_depth * float(ribs) * 0.35).normalized()
			var c := col
			c.a = 0.55 + 0.45 * (rib * 0.5 + 0.5)
			b.add(pts[i] + dir * r, n, c, Vector2(a * radii[i], along), Vector2(maxf(pts[i].y, 0.0), 0.0))
	for i in count - 1:
		for s in sides:
			var r0 := first + i * (sides + 1) + s
			var r1 := r0 + sides + 1
			b.tri(r0, r1, r0 + 1)
			b.tri(r0 + 1, r1, r1 + 1)


## Column points rising from `base` to `top`, with a rounded crown.
static func _column(base: Vector3, top: Vector3, r: float, segs: int) -> Array:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in segs + 1:
		var k := float(i) / segs
		pts.append(base.lerp(top, k))
		radii.append(r)
	var up := (top - base).normalized()
	for c: float in [0.35, 0.62, 0.82, 0.95, 1.0]:
		pts.append(top + up * r * c * 0.9)
		radii.append(r * sqrt(maxf(1.0 - c * c, 0.0)) + 0.004)
	return [pts, radii]


## A saguaro: a pleated column 5-12 m tall, arms that leave sideways and turn
## up at an elbow, rounded crowns. Older (taller) ones have more arms.
## lod 1: the same shape with half the sides and no pleats.
static func saguaro(seed_value: int, mat: Material, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var H := rng.randf_range(5.0, 11.0)
	var r := rng.randf_range(0.24, 0.34)
	var col := Color(0.28, 0.35, 0.2)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
	var trunk := _column(Vector3(0, -0.3, 0), Vector3(0, H, 0) + lean, r, 10)
	ribbed_tube(b, trunk[0], trunk[1], 28 if lod == 0 else 13, 13, 0.07 if lod == 0 else 0.0, col)
	var arms := 0 if H < 6.0 else rng.randi_range(1, 2 + int((H - 6.0) / 1.6))
	var spin := rng.randf() * TAU
	for i in arms:
		var a := spin + TAU * float(i) / float(maxi(arms, 1)) + rng.randf_range(-0.6, 0.6)
		var d := Vector3(cos(a), 0.0, sin(a))
		var y0 := rng.randf_range(2.2, H * 0.65)
		var o := Vector3(0, y0, 0) + lean * (y0 / H)
		var ra := r * rng.randf_range(0.65, 0.8)
		var out := rng.randf_range(0.45, 0.8)
		var rise := rng.randf_range(1.0, minf(3.2, H - y0))
		var pts := PackedVector3Array([o, o + d * out * 0.55 + Vector3.UP * 0.04, o + d * out * 0.9 + Vector3.UP * 0.28,
			o + d * out + Vector3.UP * 0.65, o + d * out + Vector3.UP * (0.65 + rise * 0.5), o + d * out + Vector3.UP * (0.65 + rise)])
		var radii := PackedFloat32Array([ra, ra, ra, ra, ra, ra])
		var crown := _column(pts[pts.size() - 1], pts[pts.size() - 1] + Vector3.UP * 0.01, ra, 0)
		var cp: PackedVector3Array = crown[0]
		var cr: PackedFloat32Array = crown[1]
		for k in range(1, cp.size()):
			pts.append(cp[k])
			radii.append(cr[k])
		ribbed_tube(b, pts, radii, 20 if lod == 0 else 10, 10, 0.07 if lod == 0 else 0.0, col.lightened(rng.randf_range(0.0, 0.06)))
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, mat)
	return m


## A barrel cactus: short, fat, deeply ribbed, leaning a little, a ring of red flowers on top.
static func barrel(seed_value: int, mat: Material, flower_mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var h := rng.randf_range(0.45, 1.1)
	var r := rng.randf_range(0.26, 0.38)
	var tilt := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(0.05, 0.2))
	var col := _column(Vector3(0, -0.1, 0), Vector3(0, h, 0) + tilt, r, 4)
	ribbed_tube(b, col[0], col[1], 32, 18, 0.11, Color(0.3, 0.36, 0.2))
	var f := Builder.new()
	var top := Vector3(0, h + r * 0.85, 0) + tilt
	for i in 9:
		var a := TAU * float(i) / 9.0
		var p := top + Vector3(cos(a), 0.0, sin(a)) * r * 0.45
		var pts := PackedVector3Array([p, p + Vector3(cos(a) * 0.04, 0.06, sin(a) * 0.04)])
		blade(f, pts, Vector3(-sin(a), 0, cos(a)), PackedFloat32Array([0.025, 0.04]), Color(0.85, 0.2, 0.12), 1.0, 1.0, 0.0, Vector3.UP, 0.5, 0.2)
	return _mesh(b, f, mat, flower_mat)


## Prickly pear: flat oval pads stacked off each other's rims, a few red fruit.
static func prickly_pear(seed_value: int, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var pads: Array = []    # [centre, up-along, across, half height, half width]
	var count := rng.randi_range(7, 15)
	for i in count:
		var parent: Array = pads[rng.randi() % pads.size()] if not pads.is_empty() and i > 2 else []
		var hh := rng.randf_range(0.16, 0.24)
		var hw := hh * rng.randf_range(0.7, 0.85)
		var a := rng.randf() * TAU
		var across := Vector3(cos(a), 0.0, sin(a))
		var base := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var dir := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()
		if not parent.is_empty():
			var pc: Vector3 = parent[0]
			var pu: Vector3 = parent[1]
			var pa: Vector3 = parent[2]
			var t := rng.randf_range(-0.8, 0.8)
			base = pc + pu * float(parent[3]) * 0.85 + pa * float(parent[4]) * t * 0.6
			dir = (pu + pa * t * 0.8 + Vector3(rng.randf_range(-0.3, 0.3), 0.2, rng.randf_range(-0.3, 0.3))).normalized()
		across = (across - dir * across.dot(dir)).normalized()
		var centre := base + dir * hh
		pads.append([centre, dir, across, hh, hw])
		_pad(b, centre, dir, across, hh, hw, Color(0.3, 0.42, 0.26).lightened(rng.randf_range(-0.05, 0.08)))
		if rng.randf() < 0.3:
			for k in 3:
				var fa := rng.randf_range(-0.9, 0.9)
				var fp := centre + dir * hh * cos(fa) + across * hw * sin(fa)
				_pad(b, fp + dir * 0.03, dir, across, 0.035, 0.028, Color(0.6, 0.1, 0.18))
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, mat)
	return m


## One flat oval pad, a little thick, normals rounded toward its rim.
static func _pad(b: Builder, c: Vector3, up: Vector3, across: Vector3, hh: float, hw: float, col: Color) -> void:
	var face := up.cross(across).normalized()
	var ring := 10
	for side: float in [1.0, -1.0]:
		var mid := b.add(c + face * 0.022 * side, face * side, Color(col.r, col.g, col.b, 1.0), Vector2(0, 0), Vector2(c.y, 0))
		var first := b.v.size()
		for i in ring:
			var a := TAU * float(i) / ring
			var rim := up * cos(a) * hh + across * sin(a) * hw
			b.add(c + rim + face * 0.006 * side, (face * side + rim.normalized() * 0.8).normalized(), Color(col.r, col.g, col.b, 0.8),
					Vector2(sin(a), cos(a)), Vector2(c.y, 0))
		for i in ring:
			if side > 0.0:
				b.tri(mid, first + i, first + (i + 1) % ring)
			else:
				b.tri(mid, first + (i + 1) % ring, first + i)


## Cholla: a short trunk branching into fat jointed arms, covered in pale spines.
static func cholla(seed_value: int, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var col := Color(0.5, 0.5, 0.3)
	var top := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.4, 0.75), rng.randf_range(-0.1, 0.1))
	tube(b, PackedVector3Array([Vector3(0, -0.1, 0), top * 0.5, top]), PackedFloat32Array([0.08, 0.07, 0.065]), 6, col.darkened(0.25), 0.4, 0.0)
	_joints(b, rng, top, Vector3.UP, 3, col)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, mat)
	return m


static func _joints(b: Builder, rng: RandomNumberGenerator, o: Vector3, dir: Vector3, depth: int, col: Color) -> void:
	for i in rng.randi_range(2, 3):
		var d := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.5), rng.randf_range(-0.9, 0.9))).normalized()
		var L := rng.randf_range(0.14, 0.26)
		var end := o + d * L
		tube(b, PackedVector3Array([o, o.lerp(end, 0.5), end, end + d * 0.03]), PackedFloat32Array([0.045, 0.055, 0.05, 0.02]), 5, col, 0.7, 0.0)
		if depth > 0:
			_joints(b, rng, end, d, depth - 1, col)


## Ocotillo: a fan of long thin whips from one root, small leaves up them, red flower tips.
static func ocotillo(seed_value: int, stem_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stems := Builder.new()
	var leaves := Builder.new()
	for i in rng.randi_range(10, 18):
		var a := rng.randf() * TAU
		var lean := rng.randf_range(0.12, 0.45)
		var d := Vector3(cos(a) * lean, 1.0, sin(a) * lean).normalized()
		var L := rng.randf_range(2.4, 5.0)
		var bow := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.1, 0.35)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var base := Vector3(cos(a), 0, sin(a)) * 0.06
		for k in 5:
			var t := float(k) / 4.0
			pts.append(base + d * L * t + bow * sin(PI * t))
			radii.append(lerpf(0.032, 0.01, t))
		tube(stems, pts, radii, 4, Color(0.36, 0.33, 0.28), 0.5, 0.25)
		for k in 14:
			var t := rng.randf_range(0.25, 0.95)
			var p := base + d * L * t + bow * sin(PI * t)
			var ld := (Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 0.8), rng.randf_range(-1, 1))).normalized()
			blade(leaves, PackedVector3Array([p, p + ld * 0.04]), ld.cross(Vector3.UP).normalized(), PackedFloat32Array([0.012, 0.0]),
					Color(0.3, 0.42, 0.14), 0.8, 1.0, 1.0, ld, 0.4, 0.0)
		var tip := pts[pts.size() - 1]
		for k in 5:
			var fd := (d + Vector3(rng.randf_range(-0.4, 0.4), 0.2, rng.randf_range(-0.4, 0.4))).normalized()
			blade(leaves, PackedVector3Array([tip - d * 0.15, tip + fd * 0.05]), fd.cross(Vector3.UP).normalized(), PackedFloat32Array([0.018, 0.006]),
					Color(0.85, 0.18, 0.1), 1.0, 1.0, 1.0, fd, 0.4, 0.0)
	return _mesh(stems, leaves, stem_mat, leaf_mat)


## Palo verde: Arizona's green-barked tree, low and wide, a fine haze of tiny leaves.
static func palo_verde(seed_value: int, bark_mat: Material, leaf_mat: Material, lod := 0) -> ArrayMesh:
	var t := Crown.new()
	t.rng = RandomNumberGenerator.new()
	t.rng.seed = seed_value
	t.leaf = _cards()
	t.wood = Builder.new() if lod == 0 else t.leaf
	t.lod = lod
	t.bark_col = Color(0.4, 0.5, 0.24)
	t.leaf_col = Color(0.46, 0.52, 0.16)
	t.cells = [LEAF_SMALL]
	t.card_size = 1.0
	t.cards_per = [4, 3, 2]
	var rng := t.rng
	var H := rng.randf_range(4.0, 6.5)
	t.H = H
	var fork := rng.randf_range(0.5, 1.0)
	var first := t.wood.v.size()
	tube(t.wood, PackedVector3Array([Vector3(0, -0.2, 0), Vector3(0, fork, 0)]), PackedFloat32Array([0.14, 0.12]), 7 if lod == 0 else 4, t.bark_col, 0.5, 0.0)
	if lod > 0:
		t.wood.mark_solid(first)
	t.crown_c = Vector3(0, H * 0.65, 0)
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a) * 1.1, 1.0, sin(a) * 1.1).normalized()
		_branch(t, Vector3(0, fork, 0), d, H * 0.45, 0.09, 3)
	return _mesh(t.wood if lod == 0 else null, t.leaf, bark_mat, leaf_mat)


## Creosote: the desert's everywhere-bush, many stems, small dark olive leaves.
static func creosote(seed_value: int, leaf_mat: Material) -> ArrayMesh:
	return bush(seed_value, leaf_mat, Color(0.22, 0.27, 0.11), [LEAF_SMALL], 0.75)
