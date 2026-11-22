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

## The leaf atlas: 4 x 6 square cells.
const ATLAS_COLS := 4
const ATLAS_ROWS := 6
const LEAF_A := 0        ## broadleaf clusters, three arrangements
const LEAF_B := 1
const LEAF_C := 2
const LEAF_SMALL := 3    ## fine small leaves (palo verde, creosote, a birch's upper crown)
const BIRCH_A := 4       ## a birch's hanging twigs: fine, airy, small leaves
const BIRCH_B := 5
const TWIG_A := 6        ## bare twigs
const TWIG_B := 7
const SPRUCE_A := 8      ## a spruce bough from above
const SPRUCE_B := 9
const HANG_A := 10       ## the twigs hanging under a bough, from the side
const HANG_B := 11
const GRASS_A := 12      ## a tuft of grass from the side
const GRASS_B := 13
const FERN_A := 14       ## a fern's frond from above (lance-shaped: lady fern, male fern)
const FERN_B := 15       ## a bracken frond on its stalk (three-cornered, twice divided)
const HERB_A := 16       ## cow parsley from the side, in its own colours: ferny leaves, white umbels
const HERB_B := 17       ## fireweed from the side, in its own colours: lance leaves, magenta spires
const LITTER_A := 18     ## fallen leaves lying on the ground, from above
const LITTER_B := 19
const SEED_A := 20       ## dry stalks with their seed heads, from the side
const THORN_A := 21      ## a tangle of thorny twigs with a few small leaves
const HERB_C := 22       ## a low leafy herb from the side (dock, nettle, bilberry: broad leaves, no flowers)
const TRUE_COLOUR: Array[int] = [HERB_A, HERB_B]   ## cells drawn in their own colours (their cards are white)


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

	## A triangle whose corners come anticlockwise as seen from its front
	## (stored clockwise, as Godot expects front faces). The tubes and blades
	## once passed theirs the other way round: every trunk, limb and stem was
	## inside out, so the bark showed the inside of its far wall, lit from the
	## wrong side, and wood riding in a card surface (which turns a back
	## face's normal round) took no sunlight at all and went black.
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
			b.tri(r0, r0 + 1, r1)
			b.tri(r0 + 1, r1 + 1, r1)


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
		b.tri(r0, r0 + 1, r1)
		b.tri(r0 + 1, r1 + 1, r1)
		b.tri(r0 + 1, r0 + 2, r1 + 1)
		b.tri(r0 + 2, r1 + 2, r1 + 1)




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

## A card bent along a path, showing an atlas cell from its bottom (the path's
## start) to its top. `side`: the card's right; hw: half its width; `drop`
## lowers its two edges against its middle (a tent, three vertices across;
## 0: flat, two across). Shade runs from ao0 at the start to ao1, flutter from flut0 to flut1.
## crop: the share of the cell's width shown, about its middle (a narrow shape
## in a square cell: no sense drawing the empty sides).
static func ribbon(b: Builder, pts: PackedVector3Array, side: Vector3, hw: float, drop: float, cell: int, col: Color,
		ao0: float, ao1: float, bend: Vector3, flut0: float, flut1: float, crop := 1.0) -> void:
	var r := cell_uv(cell)
	r = Rect2(r.position.x + r.size.x * (1.0 - crop) * 0.5, r.position.y, r.size.x * crop, r.size.y)
	var n := pts.size()
	var first := b.v.size()
	var across := 3 if drop != 0.0 else 2
	var lean := clampf(drop / maxf(hw, 0.001), -1.0, 1.0) * 0.8
	for i in n:
		var k := float(i) / float(n - 1)
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := side.cross(tg).normalized()
		var sd := tg.cross(nrm).normalized()
		var cc := col
		cc.a = lerpf(ao0, ao1, pow(k, 0.7))
		var vv := lerpf(r.end.y, r.position.y, k)
		var h := Vector2(maxf(pts[i].y, 0.0), lerpf(flut0, flut1, k))
		if across == 3:
			b.add_card(pts[i] - sd * hw - nrm * drop, (nrm - sd * lean).normalized(), sd, cc, Vector2(r.position.x, vv), h, bend)
			b.add_card(pts[i], nrm, sd, cc, Vector2(r.position.x + r.size.x * 0.5, vv), h, bend)
			b.add_card(pts[i] + sd * hw - nrm * drop, (nrm + sd * lean).normalized(), sd, cc, Vector2(r.end.x, vv), h, bend)
		else:
			b.add_card(pts[i] - sd * hw, nrm, sd, cc, Vector2(r.position.x, vv), h, bend)
			b.add_card(pts[i] + sd * hw, nrm, sd, cc, Vector2(r.end.x, vv), h, bend)
	for i in n - 1:
		var nrm := b.n[first + i * across + (1 if across == 3 else 0)]
		for a in across - 1:
			var p0 := first + i * across + a
			var p1 := p0 + across
			b.tri_facing(p0, p1, p0 + 1, nrm)
			b.tri_facing(p0 + 1, p1, p1 + 1, nrm)


## A card hanging from the line tl..tr (an atlas cell whose top edge is that
## line): its two bottom corners are tl + fall_l and tr + fall_r.
static func curtain(b: Builder, tl: Vector3, tr: Vector3, fall_l: Vector3, fall_r: Vector3, cell: int, col: Color,
		ao_top: float, ao_bottom: float, bend: Vector3, flut_top: float) -> void:
	var r := cell_uv(cell)
	var along := (tr - tl).normalized()
	var face := along.cross((fall_l + fall_r) * -0.5).normalized()
	var f := b.v.size()
	var cc := col
	cc.a = ao_top
	b.add_card(tl, face, along, cc, Vector2(r.position.x, r.position.y), Vector2(maxf(tl.y, 0.0), flut_top), bend)
	b.add_card(tr, face, along, cc, Vector2(r.end.x, r.position.y), Vector2(maxf(tr.y, 0.0), flut_top), bend)
	cc.a = ao_bottom
	b.add_card(tl + fall_l, face, along, cc, Vector2(r.position.x, r.end.y), Vector2(maxf(tl.y + fall_l.y, 0.0), 1.0), bend)
	b.add_card(tr + fall_r, face, along, cc, Vector2(r.end.x, r.end.y), Vector2(maxf(tr.y + fall_r.y, 0.0), 1.0), bend)
	b.tri_facing(f, f + 1, f + 2, face)
	b.tri_facing(f + 1, f + 3, f + 2, face)


## A spruce: a tapered trunk, drooping boughs whose reach follows a narrow cone,
## dead twigs up the bare trunk under the crown, a slender leader. No two boughs
## leave the trunk at the same height or reach the same length (whorls of equal
## boughs read as a stack of plates), and each bough has depth: a tent-shaped
## spray, side sprays hanging off it, and curtains of twigs below (see _bough).
## lod 1 keeps every other bough as one broad card with its skirt; lod 2 (the
## shadow caster) a few boughs of every third whorl; all from the same dice.
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
	var y0 := H * rng.randf_range(0.1, 0.24)
	var rmax := H * rng.randf_range(0.2, 0.26)
	var y := y0
	var spin := 0.0
	var w := 0
	while y < H - 0.9:
		var u := (y - y0) / (H - y0)
		var reach := rmax * pow(1.0 - u, 0.85) * (0.6 + 0.4 * smoothstep(0.0, 0.12, u))
		# Each whorl has its own dice, so the far version's boughs are the close-up's.
		var wr := RandomNumberGenerator.new()
		wr.seed = seed_value * 7919 + w
		var count := wr.randi_range(4, 6)
		spin += rng.randf_range(0.4, 1.2)
		var gap := rng.randf_range(0.42, 0.62) * (0.75 + 0.5 * (1.0 - u))
		for j in count:
			var ang := spin + TAU * float(j) / float(count) + wr.randf_range(-0.4, 0.4)
			var yb := minf(y + wr.randf_range(-0.45, 0.45) * gap, H - 0.8)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var L := reach * wr.randf_range(0.72, 1.12) + 0.4
			if wr.randf() < 0.14:
				L *= 1.25          # the odd long bough breaks the cone's outline
			var axis := Vector3(0.0, yb, 0.0) + lean * (yb / H) * (yb / H)
			# The far versions keep every other bough of every whorl; the shadow
			# caster makes do with a few boughs of every third whorl (and the core).
			var keep := (j + w) % 2 == 0 if lod == 1 else (w % 3 == 0 and j % 2 == 0)
			_bough(leaf, wr, axis, dir, L * (1.0 if lod == 0 else 1.1), needle, u, lod, gap * (1.0 if lod == 0 else 2.3), lod == 0 or keep)
		if lod == 0 and u < 0.85:
			# Close up, shorter boughs between the whorls fill the inside, so the eye
			# meets needles, not a bare pole, when it looks in under the big boughs.
			var ir := RandomNumberGenerator.new()
			ir.seed = seed_value * 104729 + w
			var inner := Vector3(0.0, y + gap * 0.5, 0.0) + lean * (y / H) * (y / H)
			for j in 3:
				var ang := spin + 1.0 + TAU * float(j) / 3.0 + ir.randf_range(-0.4, 0.4)
				_bough(leaf, ir, inner, Vector3(cos(ang), 0.0, sin(ang)), reach * ir.randf_range(0.4, 0.6) + 0.3, needle, u * 0.5, 3, 0.0, true)
		y += gap
		w += 1
	# Dead twigs up the bare trunk under the crown: what is left of the boughs the wood shaded out.
	var dr := RandomNumberGenerator.new()
	dr.seed = seed_value * 31 + 5
	var yd := dr.randf_range(1.0, 1.6)
	var nd := 0
	while yd < y0 + 0.5:
		var a := dr.randf() * TAU
		var d := Vector3(cos(a), dr.randf_range(-0.3, 0.1), sin(a)).normalized()
		var ld := dr.randf_range(0.7, 1.7)
		var tilt := dr.randf_range(-0.7, 0.7)
		if lod == 0 or (lod == 1 and nd % 2 == 0):
			var o := Vector3(0.0, yd, 0.0) + lean * (yd / H) * (yd / H)
			var right := (d.cross(Vector3.UP).normalized() * cos(tilt) + Vector3.UP * sin(tilt)) * ld * 0.42
			card(leaf, o, right, d * ld, TWIG_A if nd % 2 == 0 else TWIG_B, Color(1.0, 1.0, 1.0), [0.45, 0.45, 0.85, 0.85], o - d, 0.2)
		yd += dr.randf_range(0.3, 0.75)
		nd += 1
	# Further off, a dark core of inner branches round the trunk, so the gaps
	# between boughs show green depth, not sky and a bare pole.
	var core := PackedVector3Array()
	var core_r := PackedFloat32Array()
	for i in 6:
		var k := float(i) / 5.0
		var yy := lerpf(y0 + 0.3, H - 1.0, k)
		core.append(Vector3(0.0, yy, 0.0) + lean * (yy / H) * (yy / H))
		core_r.append(rmax * 0.3 * pow(1.0 - k, 0.9) * (0.5 + 0.5 * smoothstep(0.0, 0.2, k)) + 0.05)
	if lod > 0:      # (close up the inner boughs do this, and the trunk may show)
		first = leaf.v.size()
		tube(leaf, core, core_r, 5, Color(needle.r * 0.55, needle.g * 0.55, needle.b * 0.55), 0.3, 0.3, 0.0)
		leaf.mark_solid(first)
		for i in range(first, leaf.c.size()):
			leaf.c[i].a = 0.32
	# The leader: a slender spire above the last boughs (two crossed upright cards).
	var top := Vector3(0.0, H - 1.05, 0.0) + lean * 0.85
	var lc := _col(needle, rng, 0.1, 1.0)
	for s in (2 if lod == 0 else 1):
		var side := Vector3(cos(s * PI * 0.5), 0.0, sin(s * PI * 0.5))
		card(leaf, top, side * 0.33, Vector3.UP * 1.45, SPRUCE_A if s == 0 else SPRUCE_B, lc, [0.8, 0.8, 1.0, 1.0], top - Vector3.UP * 2.0, 1.0)
	return _mesh(bark if lod == 0 else null, leaf, bark_mat, leaf_mat)


## One spruce bough. Its line droops from the trunk and lifts again at the tip.
## Close up (lod 0) a short bough is a narrow tent of needles along that line,
## two side sprays leaving it part way out with their outer edges hanging, a
## curtain of twigs under it and a skirt across its tip. A long one is built
## of more, smaller pieces instead (_bough_long), so that no card shows the
## atlas much past its sharpness: stretched over three or four metres a spray's
## needles became slabs and a curtain's hanging twigs a picket fence.
## lod 1: one broad flat card and the skirt. lod 2: the card alone. lod 3: a
## short inner bough (the tent alone). Every die is thrown whether or not the
## bough is drawn, so each version of a tree throws the same ones.
static func _bough(leaf: Builder, rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, L: float, needle: Color,
		u: float, lod: int, gap: float, draw: bool) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	# Low boughs slope well down, the young ones near the top reach out and up.
	var rise := lerpf(-0.55, 0.3, u) + rng.randf_range(-0.1, 0.1)
	var droop := rng.randf_range(0.7, 1.3) * lerpf(0.36, 0.1, u) * L
	var upturn := rng.randf_range(0.12, 0.3) * L
	var roll := rng.randf_range(-0.2, 0.2)
	var col := _col(needle, rng, 0.14, 1.0)
	var cell := SPRUCE_A if rng.randf() < 0.5 else SPRUCE_B
	var hang_cell := HANG_A if rng.randf() < 0.5 else HANG_B
	var hang := rng.randf_range(0.4, 0.6) * L
	var at: Array[float] = [rng.randf_range(0.22, 0.4), rng.randf_range(0.3, 0.5)]
	var turn: Array[float] = [rng.randf_range(0.55, 0.9), rng.randf_range(0.55, 0.9)]
	var len: Array[float] = [rng.randf_range(0.48, 0.68), rng.randf_range(0.48, 0.68)]
	if not draw:
		return
	var ao0 := 0.12 + 0.3 * minf(u, 1.0)
	var bend := (dir * 0.55 + Vector3.UP * 0.75).normalized()
	# The bough's line, by how far along it (0 at the trunk .. 1 at the tip).
	var line := func(k: float) -> Vector3:
		var sag := droop * (0.25 * k + 0.75 * k * k) - upturn * k * k * k * 0.6   # sags, then flicks up a little at the tip
		return origin + dir * L * k + Vector3.UP * (rise * L * k - sag)
	if lod == 0 and L > LONG_BOUGH:
		_bough_long(leaf, line, dir, L, col, cell, hang_cell, hang, roll, ao0, bend, gap)
		return
	var close := lod == 0 or lod == 3
	var segs := 3 if lod == 0 else 2
	var hw := L * ((0.27 if lod == 0 else 0.42) if close else 0.55)
	var pts := PackedVector3Array()
	for i in segs + 1:
		pts.append(line.call(float(i) / float(segs)))
	# Further off a bough is one flat card: rolled well over to one side or the
	# other, so it shows a face (not an edge, a line with sky above and below)
	# to an eye level with it.
	var tip_over := roll if close else signf(roll) * (0.4 + absf(roll) * 2.0)
	ribbon(leaf, pts, (side + Vector3.UP * tip_over).normalized(), hw, hw * 0.42 if close else 0.0, cell, col, ao0, 1.0, bend, 0.0, 1.0)
	if L < 0.55 or lod >= 2:
		return
	var hc := col.darkened(0.12)
	var ao1 := lerpf(ao0, 1.0, 0.5)
	# A skirt across the bough's outer part, facing out: the hanging twigs that
	# make a spruce's side (boughs pointing at the eye would otherwise be edge-on).
	var sk := pts[segs - 1].lerp(pts[segs], 0.35)
	var sw := side * L * (0.4 if close else 0.5)
	# Long enough to reach the boughs below, so the tree's side closes.
	var fall := maxf(hang * 1.15, gap * 1.25)
	var drop := Vector3.DOWN * fall + dir * fall * 0.18
	curtain(leaf, sk + sw, sk - sw, drop, drop, hang_cell, hc, 0.95, 0.75, (dir * 0.75 + Vector3.UP * 0.45).normalized(), 0.5)
	if lod > 0:
		return
	# Close up, a curtain along the bough as well: twigs hanging under its outer two thirds.
	var hb := (dir * 0.8 + Vector3.UP * 0.3).normalized()
	curtain(leaf, pts[1], pts[segs], Vector3.DOWN * hang, Vector3.DOWN * hang * 0.8, hang_cell, hc, ao1 * 0.9, ao1 * 0.75, hb, 0.4)
	if L < 0.95:
		return
	# Side sprays: the bough forks, and each fork's outer edge hangs lower than its inner one.
	for s in 2:
		var sgn := 1.0 if s == 0 else -1.0
		var o: Vector3 = line.call(at[s])
		var sdir := dir.rotated(Vector3.UP, sgn * turn[s])
		var ls := L * len[s]
		var sp := PackedVector3Array()
		for i in 3:
			var kk := float(i) * 0.5
			sp.append(o + sdir * ls * kk + Vector3.UP * ((rise - 0.12) * ls * kk - 0.3 * ls * kk * kk))
		var ss := (sdir.cross(Vector3.UP).normalized() + Vector3.UP * 0.45 * sgn).normalized()
		ribbon(leaf, sp, ss, L * 0.2, 0.0, SPRUCE_B if cell == SPRUCE_A else SPRUCE_A, col.darkened(0.06), ao1, 1.0, bend, 0.3, 1.0)


const LONG_BOUGH := 1.7          ## a bough longer than this is built of smaller pieces close up (metres)

## A long bough close up, as a real one grows: a bare woody axis out from the
## trunk; at its end a spray of needles a metre or two long (a tent, as a short
## bough is); side sprays about a metre long leaving the axis alternately, each
## tilted and drooping its own way; under the axis short curtains of hanging
## twigs, each swung a little off the bough's line so they never stand in one
## plane; and a narrow skirt across the tip. No piece shows an atlas cell more
## than about two metres across. `line`: the bough's line (0 trunk .. 1 tip).
## It throws its own dice (the far versions of the tree throw none of them).
static func _bough_long(leaf: Builder, line: Callable, dir: Vector3, L: float, col: Color, cell: int, hang_cell: int,
		hang: float, roll: float, ao0: float, bend: Vector3, gap: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3(L, hang, roll))
	var side := dir.cross(Vector3.UP).normalized()
	var other := SPRUCE_B if cell == SPRUCE_A else SPRUCE_A
	var other_hang := HANG_B if hang_cell == HANG_A else HANG_A
	var hc := col.darkened(0.12)
	var ao1 := lerpf(ao0, 1.0, 0.5)
	# The end spray, and the wood that carries it.
	var T := clampf(L * 0.55, 1.3, 2.1)
	var k0 := 1.0 - T / L
	var tip := PackedVector3Array([line.call(k0), line.call(k0 + (1.0 - k0) * 0.5), line.call(1.0)])
	ribbon(leaf, tip, (side + Vector3.UP * roll).normalized(), T * 0.29, T * 0.12, cell, col, lerpf(ao0, 1.0, k0), 1.0, bend, k0, 1.0)
	var first := leaf.v.size()
	tube(leaf, PackedVector3Array([line.call(0.0), line.call(k0 + 0.04)]), PackedFloat32Array([0.035 + L * 0.006, 0.02]), 3, Color(0.2, 0.15, 0.11), 0.35, 0.0)
	leaf.mark_solid(first)
	# Side sprays, alternately left and right, shorter toward the tip.
	var count := clampi(roundi((L - T * 0.5) / 0.8), 2, 5)
	for s in count:
		var k := lerpf(0.14, k0 + 0.12, (float(s) + rng.randf_range(0.15, 0.85)) / float(count))
		var sgn := 1.0 if s % 2 == 0 else -1.0
		var o: Vector3 = line.call(k)
		var along: Vector3 = (line.call(k + 0.05) - o).normalized()
		var sdir := dir.rotated(Vector3.UP, sgn * rng.randf_range(0.6, 1.05))
		var ls := clampf((L * (1.0 - k) * 0.6 + 0.45) * rng.randf_range(0.8, 1.2), 0.7, 1.7)
		var slope := along.y - rng.randf_range(0.05, 0.3)
		var sag := rng.randf_range(0.15, 0.4)
		var sp := PackedVector3Array()
		for i in 3:
			var kk := float(i) * 0.5
			sp.append(o + sdir * ls * kk + Vector3.UP * (slope * ls * kk - sag * ls * kk * kk))
		# (its outer edge hangs lower than its inner one, by its own amount)
		var ss := (sdir.cross(Vector3.UP).normalized() + Vector3.UP * sgn * rng.randf_range(0.15, 0.75)).normalized()
		ribbon(leaf, sp, ss, ls * rng.randf_range(0.3, 0.38), 0.0, other if s % 2 == 0 else cell, _col(col.darkened(0.05), rng, 0.08, 1.0),
				lerpf(ao0, 1.0, k * 0.7), 1.0, bend, k, 1.0)
	# Curtains of hanging twigs under the axis.
	var hb := (dir * 0.8 + Vector3.UP * 0.3).normalized()
	var hung := clampi(int(ceil(L * 0.78 / 1.5)), 2, 3)
	for c in hung:
		var ka := lerpf(0.2, 1.0, float(c) / float(hung))
		var kb := lerpf(0.2, 1.0, float(c + 1) / float(hung))
		var pa: Vector3 = line.call(ka)
		var pb: Vector3 = line.call(kb)
		var mid := (pa + pb) * 0.5
		var half := ((pb - pa) * 0.5 * rng.randf_range(0.85, 1.1)).rotated(Vector3.UP, rng.randf_range(-0.45, 0.45))
		var h := clampf(hang * rng.randf_range(0.7, 1.1), 0.45, 1.05)
		var k := (ka + kb) * 0.5
		curtain(leaf, mid - half, mid + half, Vector3.DOWN * h, Vector3.DOWN * h * rng.randf_range(0.7, 1.0), hang_cell if c % 2 == 0 else other_hang, hc,
				lerpf(ao0, 1.0, k) * 0.9, lerpf(ao0, 1.0, k) * 0.75, hb, 0.4)
	# The skirt across the tip, facing out; long enough to reach the boughs below.
	var sk: Vector3 = line.call(1.0 - 0.2 * T / L)
	var sw := side * minf(L * 0.4, 0.7)
	var fall := clampf(maxf(hang * 1.15, gap * 1.25), 0.5, 1.15)
	var drop := Vector3.DOWN * fall + dir * fall * 0.18
	curtain(leaf, sk + sw, sk - sw, drop, drop, other_hang, hc, 0.95, 0.75, (dir * 0.75 + Vector3.UP * 0.45).normalized(), 0.5)


## A young spruce, 1 to 3.5 m: bushy, boughs to the ground, a long leader.
## lod 1 (far off): three crossed upright cards.
static func young_spruce(seed_value: int, leaf_mat: Material, needle: Color, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var leaf := _cards()
	var H := rng.randf_range(1.3, 3.4)
	var rmax := H * rng.randf_range(0.27, 0.35)
	if lod > 0:
		for s in 3:
			var a := PI * float(s) / 3.0 + rng.randf()
			card(leaf, Vector3(0.0, -0.05, 0.0), Vector3(cos(a), 0.0, sin(a)) * rmax * 1.1, Vector3.UP * (H + 0.15), SPRUCE_A if s % 2 == 0 else SPRUCE_B,
					_col(needle, rng, 0.1, 1.0), [0.4, 0.4, 1.0, 1.0], Vector3(0.0, H * 0.4, 0.0), 1.0)
		return _mesh(null, leaf, null, leaf_mat)
	tube(leaf, PackedVector3Array([Vector3(0.0, -0.1, 0.0), Vector3(0.0, H * 0.5, 0.0), Vector3(0.0, H, 0.0)]),
			PackedFloat32Array([H * 0.016, H * 0.01, 0.006]), 4, Color(0.24, 0.18, 0.14), 0.4, 0.0)
	leaf.mark_solid(0)
	# Its body: two crossed upright cards, dark, so the little tree is a dense
	# cone from any side; the boughs stand out of it.
	var turn := rng.randf() * TAU
	for s in 2:
		var a := turn + PI * 0.5 * float(s)
		card(leaf, Vector3(0.0, 0.0, 0.0), Vector3(cos(a), 0.0, sin(a)) * rmax * 0.8, Vector3.UP * H * 0.97, SPRUCE_A if s == 0 else SPRUCE_B,
				_col(needle.darkened(0.3), rng, 0.08, 1.0), [0.3, 0.3, 0.75, 0.75], Vector3(0.0, H * 0.4, 0.0), 0.6)
	var y := 0.1
	var spin := rng.randf() * TAU
	while y < H - 0.3:
		var u := y / H
		var reach := rmax * pow(1.0 - u, 0.9) + 0.12
		var count := rng.randi_range(4, 6)
		spin += rng.randf_range(0.5, 1.1)
		var gap := rng.randf_range(0.22, 0.3) * (0.65 + 0.2 * H)
		for j in count:
			var ang := spin + TAU * float(j) / float(count) + rng.randf_range(-0.3, 0.3)
			# A young tree's boughs reach up and out (u past 1 is _bough's steepest
			# rise and least droop); each a tent of needles, never a flat plate.
			_bough(leaf, rng, Vector3(0.0, y + rng.randf_range(-0.4, 0.4) * gap, 0.0), Vector3(cos(ang), 0.0, sin(ang)), reach * rng.randf_range(0.85, 1.2),
					needle, 1.05 + 0.3 * u, 3, 0.0, true)
		y += gap
	var lc := _col(needle, rng, 0.1, 1.0)
	for s in 2:
		var side := Vector3(cos(s * PI * 0.5), 0.0, sin(s * PI * 0.5))
		card(leaf, Vector3(0.0, H - 0.45, 0.0), side * 0.16, Vector3.UP * 0.75, SPRUCE_A, lc, [0.8, 0.8, 1.0, 1.0], Vector3(0.0, H - 1.0, 0.0), 1.0)
	return _mesh(null, leaf, null, leaf_mat)


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
		t.card_size = 1.3
		t.cards_per = [8, 6, 3]
	if bare:
		t.cells = [TWIG_A, TWIG_B]
		t.cards_per = [2, 1, 0]
		t.card_size = 1.5
	var rng := t.rng
	var H := rng.randf_range(7.0, 11.0) * (1.25 if birch else 1.0)
	t.H = H
	var fork := H * rng.randf_range(0.3, 0.42) * (1.08 if birch else 1.0)
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
		# (a birch's branches keep close to the way their limb goes: a tall narrow crown, not an umbrella)
		var wide := 0.6 if t.birch else 1.0
		var nd := (d + Vector3(rng.randf_range(-0.8, 0.8) * wide, rng.randf_range(0.0, 0.6), rng.randf_range(-0.8, 0.8) * wide) + away.normalized() * 0.4 * wide).normalized()
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
		# A birch: airy masses of small leaves on the branches, and fine twigs
		# hanging from their outer parts (more of them the further out the branch).
		var hangs := t.birch and rng.randf() < (0.72 if depth == 0 else 0.45)
		if t.birch and not hangs:
			cell = LEAF_SMALL
		t.count += 1
		if t.lod > 0 and t.count % (3 if t.lod == 1 else 9) != 0:
			continue
		if t.lod > 0:
			s *= 1.85 if t.lod == 1 else 1.5
		var outward := (p - t.crown_c).normalized()
		var up := (twig_dir * 0.5 + outward * 0.6 + rnd * 0.55 + (Vector3.DOWN * 1.9 if hangs else Vector3.UP * 0.2)).normalized()
		var face := (outward * 0.7 + Vector3.UP * 0.45 + rnd2 * 0.8).normalized()
		if t.lod == 2:
			# The shadow caster: broad cards lying across the crown, facing the sky.
			up = (outward * Vector3(1.0, 0.0, 1.0) + rnd * 0.4).normalized()
			face = (Vector3.UP + rnd2 * 0.3).normalized()
		var right := up.cross(face)
		if right.length() < 0.1:
			right = up.cross(Vector3.RIGHT)
		right = right.normalized()
		var hw := s * (0.46 if hangs else (0.42 if t.birch else 0.5))
		var hh := s * (1.3 if hangs else (0.84 if t.birch else 1.0))
		var o := p - up * hh * 0.4
		var aos := []
		for cp: Vector3 in [o - right * hw, o + right * hw, o - right * hw + up * hh, o + right * hw + up * hh]:
			aos.append(_crown_ao(cp, t.crown_c, t.H))
		card(t.leaf, o, right * hw, up * hh, cell, col, aos, t.crown_c, 1.0)


# ---- small plants -----------------------------------------------------------------

## A bush: stems from the ground, cards of leaves bunched over them (one surface).
## form 0: a small upright bush; 1: a broad rounded shrub (hazel, willow), its
## stems spreading. lod 1 (far off): no stems, half the cards, larger.
static func bush(seed_value: int, leaf_mat: Material, leaf_col: Color, cells: Array = [LEAF_A, LEAF_B, LEAF_C], card_size := 0.85,
		form := 0, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var H := rng.randf_range(0.7, 1.5) if form == 0 else rng.randf_range(1.4, 2.3)
	var spread := 0.5 if form == 0 else rng.randf_range(0.85, 1.2)
	var c := Vector3(0.0, H * 0.45, 0.0)
	var n := 0
	for i in (rng.randi_range(4, 7) if form == 0 else rng.randi_range(8, 11)):
		var a := rng.randf() * TAU
		var lean := spread * (1.0 if form == 0 else rng.randf_range(0.35, 1.0))
		var d := Vector3(cos(a) * lean, 1.0, sin(a) * lean).normalized()
		var reach := H * (1.0 if form == 0 else rng.randf_range(0.8, 1.1))
		# A shrub's stems bow outward and lift again at their ends.
		var pts := PackedVector3Array([Vector3.ZERO, d * reach * 0.5 + Vector3(rng.randf_range(-0.1, 0.1), -0.08 * float(form) * lean, 0.0), d * reach + Vector3.UP * 0.12 * float(form) * lean])
		if lod == 0:
			var first := b.v.size()
			tube(b, pts, PackedFloat32Array([0.025, 0.018, 0.008]) if form == 0 else PackedFloat32Array([0.035, 0.024, 0.01]), 3, Color(0.25, 0.2, 0.15), 0.4, 0.3)
			b.mark_solid(first)
		for k in (3 if form == 0 else 4):
			var s := card_size * (H / 1.1 if form == 0 else 1.1) * rng.randf_range(0.8, 1.25)
			var p := pts[1].lerp(pts[2], rng.randf_range(0.0, 1.0)) + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.2, 0.15), rng.randf_range(-0.25, 0.25)) * s
			var outward := (p - c).normalized()
			var up := (d * 0.6 + outward * 0.5 + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
			var face := (outward * 0.6 + Vector3.UP * 0.6 + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.4, 0.8), rng.randf_range(-0.8, 0.8))).normalized()
			var cell: int = cells[rng.randi() % cells.size()]
			var col := _col(leaf_col, rng, 0.15, 1.0)
			n += 1
			if lod > 0:
				if n % 2 == 0:
					continue
				s *= 1.5
			var right := up.cross(face)
			if right.length() < 0.1:
				right = up.cross(Vector3.RIGHT)
			right = right.normalized() * s * 0.5
			var o := p - up * s * 0.45
			var aos := []
			for cp: Vector3 in [o - right, o + right, o - right + up * s, o + right + up * s]:
				aos.append(clampf(0.35 + 0.65 * (cp.y / H), 0.25, 1.0))
			card(b, o, right, up * s, cell, col, aos, c, 1.0)
	return _mesh(null, b, null, leaf_mat)


## A thorn thicket (bramble, wild rose): canes that arch out of the root and
## come back down, tangles of thorny twigs along them with a few small leaves.
## lod 1: the tangles alone, half of them, larger.
static func thorn(seed_value: int, leaf_mat: Material, leaf_col: Color, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var n := 0
	var c := Vector3(0.0, 0.3, 0.0)
	for i in rng.randi_range(6, 9):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		var reach := rng.randf_range(1.1, 2.3)
		var top := rng.randf_range(0.6, 1.3)
		var pts := PackedVector3Array()
		for k in 5:
			var t := float(k) / 4.0 * 0.88
			pts.append(d * reach * t + Vector3.UP * top * sin(PI * pow(t, 0.8)) + Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06)))
		if lod == 0:
			var first := b.v.size()
			tube(b, pts, PackedFloat32Array([0.013, 0.012, 0.01, 0.008, 0.005]), 3, Color(0.3, 0.19, 0.16), 0.45, 0.3)
			b.mark_solid(first)
		for k in 3:
			var at := rng.randf_range(0.8, 3.9)
			var s := rng.randf_range(0.65, 1.0)
			var rnd := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.0), rng.randf_range(-1.0, 1.0))
			var rnd2 := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.0, 1.0))
			var cell := THORN_A if rng.randf() < 0.75 else TWIG_B
			var col := _col(leaf_col, rng, 0.15, 1.0)
			n += 1
			if lod > 0:
				if n % 2 == 0:
					continue
				s *= 1.5
			var p := pts[int(at)].lerp(pts[mini(int(at) + 1, 4)], at - floor(at))
			var up := (rnd + (pts[mini(int(at) + 1, 4)] - pts[int(at)]).normalized() * 0.6).normalized()
			var right := up.cross(rnd2)
			if right.length() < 0.1:
				right = up.cross(Vector3.RIGHT)
			right = right.normalized() * s * 0.5
			var o := p - up * s * 0.3
			var aos := []
			for cp: Vector3 in [o - right, o + right, o - right + up * s, o + right + up * s]:
				aos.append(clampf(0.4 + 0.6 * cp.y / 1.2, 0.3, 1.0))
			card(b, o, right, up * s, cell, col, aos, c, 0.8)
	return _mesh(null, b, null, leaf_mat)


## A sapling, 1.5 to 3.5 m: a thin stem, a few side twigs, sprays of leaves (one surface).
static func sapling(seed_value: int, leaf_mat: Material, leaf_col: Color, bark_col: Color, cells: Array = [LEAF_A, LEAF_B, LEAF_C], hang := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var H := rng.randf_range(1.6, 3.4)
	var pts := PackedVector3Array([Vector3(0.0, -0.1, 0.0)])
	var radii := PackedFloat32Array([0.012 + H * 0.006])
	for i in 4:
		var k := float(i + 1) / 4.0
		pts.append(Vector3(rng.randf_range(-0.12, 0.12) * k, H * k, rng.randf_range(-0.12, 0.12) * k))
		radii.append(lerpf(radii[0], 0.004, k))
	tube(b, pts, radii, 4, bark_col, 0.5, 0.2)
	b.mark_solid(0)
	var c := Vector3(0.0, H * 0.6, 0.0)
	var sprays := rng.randi_range(5, 8)
	for i in sprays:
		# Side twigs up the stem's upper two thirds, the last spray at its tip.
		var k := lerpf(0.35, 1.0, float(i) / float(sprays - 1))
		var at := k * 4.0
		var o := pts[mini(int(at), 3)].lerp(pts[mini(int(at) + 1, 4)], at - floor(at)) if i < sprays - 1 else pts[4]
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(0.3, 0.9), sin(a)).normalized()
		var reach := rng.randf_range(0.3, 0.75) * (1.2 - 0.6 * k)
		if i < sprays - 1:
			var first := b.v.size()
			tube(b, PackedVector3Array([o, o + d * reach]), PackedFloat32Array([0.008, 0.004]), 3, bark_col, 0.6, 0.5)
			b.mark_solid(first)
		for j in 2:
			var s := rng.randf_range(0.5, 0.8)
			var p := o + d * reach * (1.0 if i < sprays - 1 else 0.0) * rng.randf_range(0.5, 1.0)
			var rnd := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.8), rng.randf_range(-1.0, 1.0))
			var up := (d + rnd * 0.6 + (Vector3.DOWN * 1.2 if hang else Vector3.UP * 0.3)).normalized()
			var face := ((p - c).normalized() * 0.6 + Vector3.UP * 0.5 + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.8, 0.8))).normalized()
			var right := up.cross(face)
			if right.length() < 0.1:
				right = up.cross(Vector3.RIGHT)
			right = right.normalized() * s * 0.5
			var q := p - up * s * 0.3
			card(b, q, right, up * s, cells[rng.randi() % cells.size()], _col(leaf_col, rng, 0.15, 1.0),
					[0.55, 0.55, 1.0, 1.0], c, 1.0)
	return _mesh(null, b, null, leaf_mat)


## A fern: a shuttlecock of fronds arching out of the root. `bracken`: a few
## stalks instead, each carrying a broad frond that leans out and nods over
## (folded a little along its midrib: held flat and level it showed the eye
## its edge, a green plate hovering over the grass).
static func fern(seed_value: int, leaf_mat: Material, col: Color, bracken := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var count := rng.randi_range(3, 4) if bracken else rng.randi_range(5, 8)
	var spin := rng.randf() * TAU
	for i in count:
		var a := spin + TAU * float(i) / float(count) + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var L := rng.randf_range(0.8, 1.25) if bracken else rng.randf_range(0.65, 1.15)
		var lift := rng.randf_range(1.2, 1.45) if bracken else rng.randf_range(0.85, 1.3)
		var over := rng.randf_range(0.2, 0.7) if bracken else rng.randf_range(-0.55, -0.15)
		var segs := 5 if bracken else 4
		var p := dir * 0.03 if not bracken else Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		var pts := PackedVector3Array([p])
		for k in segs:
			var t := (float(k) + 0.5) / float(segs)
			# A fern's frond arches over all the way; a bracken's stalk stands, then the frond turns out level.
			var ang := lerpf(lift, over, pow(t, 1.3)) if not bracken else lerpf(lift, over, smoothstep(0.25, 0.9, t))
			p += (dir * cos(ang) + Vector3.UP * sin(ang)) * L / float(segs)
			pts.append(p)
		# (the lance-shaped frond fills little more than half its cell's width)
		ribbon(b, pts, dir.cross(Vector3.UP).normalized(), L * (0.3 if bracken else 0.135), L * 0.07 if bracken else 0.0, FERN_B if bracken else FERN_A, _col(col, rng, 0.14, 1.0),
				0.35, 1.0, (dir * 0.45 + Vector3.UP * 0.85).normalized(), 0.1, 1.0, 1.0 if bracken else 0.62)
	return _mesh(null, b, null, leaf_mat)


## A clump of tall herbs or dry stalks: upright cards standing close together,
## each turned its own way. H: their height; wide: a card's width against its
## height; foot: the shade at their foot (dry stalks and bunch grass stand in the open: little).
static func herb(seed_value: int, leaf_mat: Material, cells: Array, H: float, stems: int, col := Color.WHITE, wide := 0.8, foot := 0.4) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var turn := rng.randf() * TAU
	for i in stems:
		var a := rng.randf() * TAU
		var pos := Vector3(cos(a), 0.0, sin(a)) * sqrt(rng.randf()) * H * 0.3
		# Spread evenly round the compass (with a little play), so no eye sees every card edge-on.
		var yaw := turn + PI * float(i) / float(stems) + rng.randf_range(-0.3, 0.3)
		var h := H * rng.randf_range(0.7, 1.12)
		var up := (Vector3.UP + Vector3(rng.randf_range(-0.14, 0.14), 0.0, rng.randf_range(-0.14, 0.14))).normalized() * h
		var right := Vector3(cos(yaw), 0.0, sin(yaw)) * h * wide * 0.5
		# Lit like the ground they stand on (bent normals nearly straight up), dark at the foot.
		card(b, pos - Vector3.UP * 0.03, right, up, cells[rng.randi() % cells.size()], _col(col, rng, 0.08, 1.0), [foot, foot, 1.0, 1.0], pos - Vector3.UP * H * 3.0, 1.0)
	return _mesh(null, b, null, leaf_mat)


## A patch of fallen leaves (or needles and bits) lying on the ground: a square
## metre, a little uneven, a hand above the soil so it does not fight with it.
static func litter(seed_value: int, leaf_mat: Material, col: Color, cell: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var r := cell_uv(cell)
	for j in 3:
		for i in 3:
			var p := Vector3(float(i) * 0.5 - 0.5, 0.035 + (rng.randf_range(0.0, 0.03) if i == 1 and j == 1 else 0.0), float(j) * 0.5 - 0.5)
			b.add_card(p, Vector3.UP, Vector3.RIGHT, Color(col.r, col.g, col.b, 0.9), Vector2(lerpf(r.position.x, r.end.x, float(i) * 0.5), lerpf(r.position.y, r.end.y, float(j) * 0.5)),
					Vector2.ZERO, Vector3.UP)
	for j in 2:
		for i in 2:
			var q := j * 3 + i
			b.tri_facing(q, q + 1, q + 3, Vector3.UP)
			b.tri_facing(q + 1, q + 4, q + 3, Vector3.UP)
	return _mesh(null, b, null, leaf_mat)


# ---- deadwood -------------------------------------------------------------------

## A length of trunk as rings round the y axis, so the bark's seam hides as it
## does on a standing tree (real_bark reads the girth from the distance to
## that axis). rings: [y, radius, shade]. `lobes`: buttress ridges at the foot,
## fading out by lobe_top. No sway (UV2 0). Returns the first vertex of the last ring.
static func _trunk(b: Builder, rings: Array, sides: int, col: Color, rng: RandomNumberGenerator, lobes := 0, lobe_top := 0.0, wobble := 0.0) -> int:
	var first := b.v.size()
	var ph := rng.randf() * TAU
	for i in rings.size():
		var y := float(rings[i][0])
		var r := float(rings[i][1])
		var off := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * wobble
		for s in sides + 1:
			var a := TAU * float(s % sides) / float(sides)
			var rr := r
			if lobes > 0 and y < lobe_top:
				rr *= 1.0 + 0.32 * (1.0 - maxf(y, 0.0) / lobe_top) * (0.5 + 0.5 * cos(float(lobes) * a + ph))
			var dir := Vector3(cos(a), 0.0, sin(a))
			b.add(off + Vector3(0.0, y, 0.0) + dir * rr, dir, Color(col.r, col.g, col.b, float(rings[i][2])), Vector2(float(s) / float(sides) * r * TAU, y), Vector2.ZERO)
	for i in rings.size() - 1:
		for s in sides:
			var r0 := first + i * (sides + 1) + s
			var r1 := r0 + sides + 1
			var face := b.n[r0] + b.n[r0 + 1]
			b.tri_facing(r0, r1, r0 + 1, face)
			b.tri_facing(r0 + 1, r1, r1 + 1, face)
	return first + (rings.size() - 1) * (sides + 1)


## Close a ring of `sides` vertices starting at `ring` with a fan (cut or broken wood).
static func _cap(b: Builder, ring: int, sides: int, sink: float, face: Vector3, col: Color) -> void:
	var mid := Vector3.ZERO
	for s in sides:
		mid += b.v[ring + s]
	mid = mid / float(sides) - face * sink
	var c := b.add(mid, face, Color(col.r * 0.6, col.g * 0.55, col.b * 0.5, 0.7), Vector2(0.0, 0.0), Vector2.ZERO)
	var first := b.v.size()
	for s in sides:
		var p := b.v[ring + s]
		b.add(p, face, col, Vector2((p.x - mid.x) * 2.0, (p.z - mid.z) * 2.0), Vector2.ZERO)
	for s in sides:
		b.tri_facing(c, first + s, first + (s + 1) % sides, face)


## A fallen trunk, built standing on the origin (its middle at y 0) and laid
## down where it is placed: a little crooked, broken off jagged at the thin
## end, stubs of limbs, pale wood at the ends. lod 1: a plain tapered tube.
static func fallen_log(seed_value: int, bark_mat: Material, bark_col: Color, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var L := rng.randf_range(3.2, 6.5)
	var r0 := rng.randf_range(0.19, 0.33)
	var r1 := r0 * rng.randf_range(0.6, 0.8)
	var sides := 9 if lod == 0 else 5
	var count := 6 if lod == 0 else 3
	var rings := []
	for i in count:
		var k := float(i) / float(count - 1)
		rings.append([lerpf(-L * 0.5, L * 0.5, k), lerpf(r0, r1, k) * (1.0 + (0.12 if i == 0 else 0.0)), 0.85])
	var wood := Color(0.52, 0.42, 0.29)
	var last := _trunk(b, rings, sides, bark_col, rng, 0, 0.0, 0.035 if lod == 0 else 0.0)
	# The thin end broke: splinters of uneven length.
	for s in sides + 1:
		b.v[last + s].y += (sin(float(s % sides) * 2.1 + r0 * 40.0) * 0.5 + 0.5) * r1 * 1.6
	_cap(b, 0, sides, 0.0, Vector3.DOWN, wood)
	_cap(b, last, sides, r1 * 1.2, Vector3.UP, wood.darkened(0.35))
	var stubs := rng.randi_range(2, 4)
	for i in stubs:
		var y := rng.randf_range(-L * 0.3, L * 0.42)
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(0.2, 0.9), sin(a)).normalized()
		var len := rng.randf_range(0.2, 0.7)
		if lod == 0:
			var o := Vector3(cos(a), 0.0, sin(a)) * r0 * 0.6 + Vector3.UP * y
			var first := b.v.size()
			tube(b, PackedVector3Array([o, o + d * len * 0.6, o + d * len]), PackedFloat32Array([0.05, 0.04, 0.025]), 5, bark_col, 0.8, 0.0)
			for k in range(first, b.uv2.size()):
				b.uv2[k] = Vector2.ZERO
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, bark_mat)
	return m


## A stump: what a fallen or felled tree left standing, roots spreading at its
## foot, its top broken or cut, pale against the bark.
static func stump(seed_value: int, bark_mat: Material, bark_col: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var H := rng.randf_range(0.3, 0.95)
	var r := rng.randf_range(0.17, 0.32)
	var sides := 10
	var rings := [[-0.3, r * 1.7, 0.4], [0.0, r * 1.5, 0.5], [0.14, r * 1.18, 0.75], [minf(0.4, H * 0.7), r, 0.95], [H, r * 0.94, 1.0]]
	var last := _trunk(b, rings, sides, bark_col, rng, rng.randi_range(4, 6), 0.3)
	# Broken, not sawn: one side stands up in a splinter.
	var high := rng.randi() % sides
	var snag := rng.randf_range(0.0, 0.35) if rng.randf() < 0.6 else 0.0
	for s in sides + 1:
		var away := absi(((s % sides) - high + sides + sides / 2) % sides - sides / 2)
		b.v[last + s].y += rng.randf_range(-0.03, 0.05) + snag * maxf(0.0, 1.0 - float(away) / 2.5)
	b.v[last + sides] = b.v[last]
	_cap(b, last, sides, 0.04, Vector3.UP, Color(0.5, 0.41, 0.28))
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, bark_mat)
	return m


## A dead branch on the ground: a crooked limb lying along x, its twigs
## spread flat beside it and a few sticking up (one card surface; the material's
## wood colour is the twigs').
static func dead_branch(seed_value: int, twig_mat: Material, wood_col: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := _cards()
	var L := rng.randf_range(1.4, 3.0)
	var pts := PackedVector3Array()
	for i in 4:
		var k := float(i) / 3.0
		pts.append(Vector3((k - 0.5) * L, 0.04 + 0.14 * sin(PI * k) * rng.randf_range(0.3, 1.0), rng.randf_range(-0.12, 0.12)))
	tube(b, pts, PackedFloat32Array([0.035, 0.028, 0.02, 0.009]), 4, wood_col, 0.6, 0.0)
	b.mark_solid(0)
	for i in b.uv2.size():
		b.uv2[i] = Vector2.ZERO
	for i in 5:
		var at := rng.randf_range(0.6, 2.9)
		var o := pts[int(at)].lerp(pts[mini(int(at) + 1, 3)], at - floor(at))
		var sgn := 1.0 if i % 2 == 0 else -1.0
		var s := rng.randf_range(0.6, 1.15) * (1.2 - at * 0.15)
		var up := Vector3(rng.randf_range(0.2, 0.7), rng.randf_range(0.02, 0.5) if i < 4 else 0.9, sgn * rng.randf_range(0.5, 1.0)).normalized()
		var right := up.cross(Vector3.UP + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)))
		if right.length() < 0.1:
			right = Vector3.RIGHT
		right = right.normalized() * s * 0.42
		var first := b.v.size()
		card(b, o, right, up * s, TWIG_A if i % 2 == 0 else TWIG_B, Color(1.0, 1.0, 1.0), [0.6, 0.6, 0.95, 0.95], o - Vector3.UP, 0.0)
		for k in range(first, b.uv2.size()):
			b.uv2[k] = Vector2.ZERO
	return _mesh(null, b, null, twig_mat)


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
	var made: Array[Builder] = []
	made.resize(out.size())
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
			SPRUCE_A:
				b = _cell_spruce(rng)
			HANG_A:
				b = _cell_hang(rng)
			SPRUCE_B, HANG_B:
				# The A cell's mirror image: these four hold far more needles than any
				# other cell, and building them is most of the atlas's time.
				b = _mirrored(made[cell - 1])
			GRASS_A, GRASS_B:
				b = _cell_grass(rng)
			FERN_A:
				b = Builder.new()
				_frond2(b, rng, Vector2.ZERO, Vector2(0.0, 1.0), 0.96, 0.25, 1, 0.4, 0.052, Color.WHITE, 0.012, 0.021)
				_fit(b)
			FERN_B:
				b = _cell_bracken(rng)
			HERB_A:
				b = _cell_umbel(rng)
			HERB_B:
				b = _cell_fireweed(rng)
			HERB_C:
				b = Builder.new()
				for i in 5:
					var d := Vector2(0.0, 1.0).rotated((float(i) - 2.0) * 0.3 + rng.randf_range(-0.1, 0.1))
					_spray(b, rng, Vector2(rng.randf_range(-0.03, 0.03), 0.0), d, rng.randf_range(0.5, 0.85), 0, 0.17, 0.05, 0, 0.12)
				_fit(b)
			LITTER_A, LITTER_B:
				b = _cell_litter(rng)
			SEED_A:
				b = _cell_seed(rng)
			THORN_A:
				b = Builder.new()
				for i in 3:
					_bare2(b, rng, Vector2(rng.randf_range(-0.05, 0.05), 0.0), Vector2(0.0, 1.0).rotated((float(i) - 1.0) * 0.45), 0.3, 0.008, 3, 0.6)
				_fit(b)
		made[cell] = b
		if b != null and not b.empty():
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
			out[cell] = m
	return out


## A cell's shapes mirrored left to right (the atlas is drawn two-sided, so the turned triangles do not matter).
static func _mirrored(src: Builder) -> Builder:
	var b := Builder.new()
	b.v = src.v.duplicate()
	b.n = src.n.duplicate()
	for i in b.v.size():
		b.v[i].x = -b.v[i].x
		b.n[i].x = -b.n[i].x
	b.c = src.c
	b.uv = src.uv
	b.uv2 = src.uv2
	b.idx = src.idx
	return b


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
static func _leaf2(b: Builder, rng: RandomNumberGenerator, p: Vector2, dir: Vector2, L: float, w: float, tone := Color.WHITE) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var roll := rng.randf_range(-0.5, 0.5)
	var pitch := rng.randf_range(-0.4, 0.4)
	var n0 := Vector3(perp.x * roll + dir.x * pitch, perp.y * roll + dir.y * pitch, 1.0).normalized()
	var nl := (n0 - Vector3(perp.x, perp.y, 0.0) * 0.4).normalized()
	var nr := (n0 + Vector3(perp.x, perp.y, 0.0) * 0.4).normalized()
	var z := rng.randf() * 0.08
	var grey := rng.randf_range(0.66, 1.0) * (0.8 + 2.5 * z)
	var a := _leaf_a(0.4 + 7.5 * z)
	var col := Color(grey * rng.randf_range(0.94, 1.05) * tone.r, grey * tone.g, grey * rng.randf_range(0.82, 1.0) * tone.b, a)
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


## A birch's hanging twigs: a few long fine ones fanning a little from where
## they leave the branch, side twiglets off them, and small leaves on short
## stalks with air between (not strung along the twig like beads: that read as
## streaks in the crown).
static func _cell_birch(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	for i in 4:
		var d := Vector2(0.0, 1.0).rotated((float(i) - 1.5) * 0.2 + rng.randf_range(-0.08, 0.08))
		_birch_twig(b, rng, Vector2(rng.randf_range(-0.02, 0.02), 0.0), d, rng.randf_range(0.68, 0.98), 1)
	_fit(b, 0.47, 0.96)
	return b


static func _birch_twig(b: Builder, rng: RandomNumberGenerator, o: Vector2, dir: Vector2, L: float, depth: int) -> void:
	var segs := 5
	var pts := PackedVector2Array([o])
	var d := dir
	var q := o
	for i in segs:
		d = d.rotated(rng.randf_range(-0.09, 0.09))
		q += d * L / float(segs)
		pts.append(q)
	_twig2(b, pts, 0.0028 + 0.0016 * depth, 0.0014, -0.01, 0.9)
	var t := 0.08
	var side := 1.0
	while t < 1.0:
		var f := t * float(segs)
		var i0 := mini(int(f), segs - 1)
		var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
		var td := (pts[i0 + 1] - pts[i0]).normalized()
		var ld := td.rotated(side * rng.randf_range(0.45, 1.1))
		_leaf2(b, rng, p + ld * rng.randf_range(0.01, 0.02), ld.rotated(rng.randf_range(-0.35, 0.35)), rng.randf_range(0.04, 0.056), 0.021)
		side = -side
		t += rng.randf_range(0.05, 0.085) / L
	_leaf2(b, rng, pts[segs], d, 0.05, 0.021)
	if depth <= 0:
		return
	var tt := 0.1
	var s := 1.0 if rng.randf() < 0.5 else -1.0
	while tt < 0.82:
		var f := tt * float(segs)
		var i0 := mini(int(f), segs - 1)
		var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
		var td := (pts[i0 + 1] - pts[i0]).normalized()
		_birch_twig(b, rng, p, td.rotated(s * rng.randf_range(0.3, 0.65)), L * rng.randf_range(0.28, 0.46) * (1.0 - tt * 0.35), 0)
		s = -s
		tt += rng.randf_range(0.09, 0.16)


## Bare twigs, forking `depth` times. `leaves`: the chance of a small leaf at
## each joint of the outer twigs (a thorn bush keeps a few).
static func _bare2(b: Builder, rng: RandomNumberGenerator, p: Vector2, dir: Vector2, L: float, w: float, depth: int, leaves := 0.0) -> void:
	var pts := PackedVector2Array([p])
	var d := dir
	var q := p
	for i in 3:
		d = d.rotated(rng.randf_range(-0.2, 0.2))
		q += d * L / 3.0
		pts.append(q)
	_twig2(b, pts, w, w * 0.62, 0.001 * depth, rng.randf_range(0.8, 1.0))
	if leaves > 0.0 and depth <= 1:
		for i in range(1, 4):
			if rng.randf() < leaves:
				_leaf2(b, rng, pts[i], d.rotated(rng.randf_range(-1.2, 1.2)), rng.randf_range(0.04, 0.06), 0.02)
	if depth == 0:
		return
	for i in rng.randi_range(2, 3):
		var o := pts[rng.randi_range(1, 3)]
		var s := 1.0 if i % 2 == 0 else -1.0
		_bare2(b, rng, o, d.rotated(s * rng.randf_range(0.3, 0.8)), L * rng.randf_range(0.55, 0.78), w * 0.6, depth - 1, leaves)


## Needles both sides of a twig's stretch from a to c, raked forward.
static func _needles2(b: Builder, rng: RandomNumberGenerator, a: Vector2, c: Vector2, length: float, step: float, grey: float) -> void:
	var seg := c - a
	var L := seg.length()
	if L < 0.001:
		return
	var d := seg / L
	var count := int(L / step) + 1
	var bw := length * 0.17
	for i in count:
		var q := a + d * L * (float(i) + rng.randf()) / float(count)
		for s: float in [-1.0, 1.0]:
			# (every needle at its own rake and length: a brush, not a comb)
			var nd := d.rotated(s * rng.randf_range(0.4, 1.2))
			var ln := length * rng.randf_range(0.55, 1.2)
			var z := rng.randf() * 0.05
			var g := grey * rng.randf_range(0.7, 1.05) * (0.8 + 4.0 * z)
			var col := Color(g * 0.95, g, g * 0.9, _leaf_a(0.45 + 11.0 * z))
			var nrm := Vector3(nd.x * 0.5 + s * d.y * 0.2, nd.y * 0.5 - s * d.x * 0.2, 0.8).normalized()
			var i0 := b.add(Vector3(q.x - d.x * bw, q.y - d.y * bw, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
			b.add(Vector3(q.x + d.x * bw, q.y + d.y * bw, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
			var tip := q + nd * ln
			b.add(Vector3(tip.x, tip.y, z), nrm, Color(minf(col.r * 1.15, 1.0), minf(col.g * 1.15, 1.0), col.b, col.a), Vector2.ZERO, Vector2.ZERO)
			b.tri(i0, i0 + 1, i0 + 2)


## A spruce twig with its needles and (depth > 0) side twigs; `curl` bends it
## as it goes. Short needles, close set, on a thin dark core of inner needles
## (a broad pale core under long needles read, magnified, as flat slats with a
## herringbone of twigs). Side twigs leave at `fork` radians, give or take a
## quarter, one every `every` of the twig's length or so (close enough that
## neighbours' needles meet: the mass is needles, with twigs barely showing);
## uneven in length, and now and then one is missing.
static func _spruce_twig(b: Builder, rng: RandomNumberGenerator, o: Vector2, dir: Vector2, L: float, depth: int, curl: float, grey: float, fork := 0.72, every := 0.07) -> void:
	var segs := 4
	var pts := PackedVector2Array([o])
	var d := dir
	var q := o
	for i in segs:
		d = d.rotated(curl + rng.randf_range(-0.07, 0.07))
		q += d * L / float(segs)
		pts.append(q)
	_body2(b, pts, 0.012 if depth > 0 else 0.009, 0.004, grey * 0.45)
	_twig2(b, pts, 0.003 + 0.002 * depth, 0.0016, -0.01, 0.85)
	for i in segs:
		# New growth at the tips is paler.
		_needles2(b, rng, pts[i], pts[i + 1], 0.02, 0.0052, grey * lerpf(0.82, 1.12, float(i) / float(segs - 1)))
	if depth <= 0:
		return
	var t := rng.randf_range(0.1, 0.18)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	while t < 0.92:
		var f := t * float(segs)
		var i0 := mini(int(f), segs - 1)
		var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
		var td := (pts[i0 + 1] - pts[i0]).normalized()
		if rng.randf() > 0.1:
			_spruce_twig(b, rng, p, td.rotated(side * fork * rng.randf_range(0.75, 1.25)), L * 0.44 * (1.0 - t * 0.55) * rng.randf_range(0.6, 1.2), depth - 1, -side * 0.05, grey, fork)
		side = -side
		t += every * rng.randf_range(0.7, 1.3)


## A spruce bough from above: a stem with side twigs raked forward, longest a
## third of the way out, all in needles; the twigs uneven, so its outline is ragged.
static func _cell_spruce(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var bow := rng.randf_range(-0.03, 0.03)
	var main := PackedVector2Array()
	for i in 9:
		var k := float(i) / 8.0
		main.append(Vector2(bow * sin(PI * k), 0.97 * k))
	_body2(b, main, 0.016, 0.005, 0.45)
	_twig2(b, main, 0.009, 0.003, -0.012, 0.85)
	for i in 8:
		_needles2(b, rng, main[i], main[i + 1], 0.022, 0.0055, 0.9)
	var t := 0.05
	var s := 1.0
	while t < 0.95:
		var reach := (0.47 * pow(1.0 - t, 0.7) * smoothstep(-0.3, 0.12, t) + 0.025) * rng.randf_range(0.72, 1.05)
		var ang := lerpf(1.1, 0.65, t) + rng.randf_range(-0.1, 0.1)
		_spruce_twig(b, rng, Vector2(bow * sin(PI * t / 0.97), t), Vector2(0.0, 1.0).rotated(-s * ang), reach, 1, s * 0.07, rng.randf_range(0.82, 1.0))
		s = -s
		t += rng.randf_range(0.026, 0.044)
	_fit(b)
	return b


## The twigs hanging under a bough, from the side. No rail along the top (the
## card hangs from a bough that is drawn by other cards, or from nothing at
## all across a bough's tip, where a ruled top edge with evenly spaced twigs
## under it read as a fence): the twigs start at uneven heights, stand unevenly
## apart with gaps, hang to very different lengths, each a little its own way,
## and their side twigs hang too.
static func _cell_hang(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var top := 0.955
	var x := -0.45 + rng.randf() * 0.04
	while x < 0.46:
		if rng.randf() < 0.1:
			x += rng.randf_range(0.05, 0.1)        # a gap
			continue
		var y0 := top - rng.randf() * rng.randf() * 0.2
		var reach := lerpf(0.16, 0.9, pow(rng.randf(), 1.3)) * (1.0 - 0.45 * absf(x))
		_spruce_twig(b, rng, Vector2(x, y0), Vector2(rng.randf_range(-0.3, 0.3), -1.0).normalized(), reach, 1, rng.randf_range(-0.07, 0.07), rng.randf_range(0.8, 1.0), 0.4, 0.085)
		x += rng.randf_range(0.014, 0.05)
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


## A soft green stalk or midrib in a cell (a twig that takes the leaf's colour, not the wood's).
static func _stem2(b: Builder, pts: PackedVector2Array, w0: float, w1: float, tone: Color, z := -0.004) -> void:
	var count := pts.size()
	var first := b.v.size()
	var col := Color(tone.r * 0.8, tone.g * 0.8, tone.b * 0.8, _leaf_a(0.7))
	for i in count:
		var k := float(i) / float(count - 1)
		var d := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var perp := Vector2(-d.y, d.x)
		var w := maxf(lerpf(w0, w1, k), 0.0016)
		b.add(Vector3(pts[i].x - perp.x * w, pts[i].y - perp.y * w, z), Vector3(-perp.x * 0.6, -perp.y * 0.6, 0.8).normalized(), col, Vector2.ZERO, Vector2.ZERO)
		b.add(Vector3(pts[i].x + perp.x * w, pts[i].y + perp.y * w, z), Vector3(perp.x * 0.6, perp.y * 0.6, 0.8).normalized(), col, Vector2.ZERO, Vector2.ZERO)
	for i in count - 1:
		var r0 := first + i * 2
		b.tri(r0, r0 + 1, r0 + 2)
		b.tri(r0 + 1, r0 + 3, r0 + 2)


## One flat triangle in a cell.
static func _tri2(b: Builder, p0: Vector2, p1: Vector2, p2: Vector2, z: float, col: Color, nrm := Vector3(0.0, 0.0, 1.0)) -> void:
	var i0 := b.add(Vector3(p0.x, p0.y, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
	b.add(Vector3(p1.x, p1.y, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
	b.add(Vector3(p2.x, p2.y, z), nrm, col, Vector2.ZERO, Vector2.ZERO)
	b.tri(i0, i0 + 1, i0 + 2)


## A small flat blob (a floret, a bud, a seed): a diamond of two triangles.
static func _dot2(b: Builder, p: Vector2, r: float, z: float, col: Color) -> void:
	_tri2(b, p + Vector2(-r, 0.0), p + Vector2(0.0, r), p + Vector2(r, 0.0), z, col)
	_tri2(b, p + Vector2(-r, 0.0), p + Vector2(r, 0.0), p + Vector2(0.0, -r), z, col)


## A frond, or one division of one: a midrib from o along dir, L long, with
## leaflets both sides, the longest (`reach`) `peak` of the way up (0: at the
## foot, a three-cornered frond). depth 0: each leaflet is one pointed lobe;
## deeper: a small frond of its own, its own leaflets no longer than `sub`
## (kept short, so there is air between one division and the next: a frond
## whose divisions touch blurs to a plain blade a few metres off).
## `gap`: the spacing of leaflets along the rib.
static func _frond2(b: Builder, rng: RandomNumberGenerator, o: Vector2, dir: Vector2, L: float, reach: float, depth: int,
		peak: float, gap: float, tone: Color, curl := 0.0, sub := 0.02) -> void:
	var segs := 5
	var pts := PackedVector2Array([o])
	var d := dir
	var q := o
	for i in segs:
		d = d.rotated(curl + rng.randf_range(-0.03, 0.03))
		q += d * L / float(segs)
		pts.append(q)
	_stem2(b, pts, 0.0028 + 0.0022 * depth, 0.0012, tone)
	var t := (0.5 if depth == 0 else 1.0) * gap / L
	while t < 0.99:
		var f := t * float(segs)
		var i0 := mini(int(f), segs - 1)
		var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
		var td := (pts[i0 + 1] - pts[i0]).normalized()
		var w := pow(1.0 - t, 0.8) if peak <= 0.0 else pow(maxf(sin(PI * pow(t, log(0.5) / log(peak))), 0.0), 0.75)
		var ln := reach * w * rng.randf_range(0.88, 1.08) + 0.003
		var ang := lerpf(1.3, 0.75, t)
		for s: float in [-1.0, 1.0]:
			var ld := td.rotated(s * ang)
			if depth > 0 and ln > 0.03:
				_frond2(b, rng, p, ld, ln, minf(ln * 0.3, sub * float(depth)), depth - 1, 0.0, gap * 0.42, tone, -s * 0.05, sub)
			else:
				var z := rng.randf() * 0.03
				var g := rng.randf_range(0.68, 1.0) * (0.85 + 4.0 * z)
				var col := Color(g * 0.96 * tone.r, g * tone.g, g * 0.88 * tone.b, _leaf_a(0.45 + 16.0 * z))
				var nrm := Vector3(ld.x * 0.45, ld.y * 0.45, 0.8).normalized()
				_tri2(b, p - td * gap * 0.55, p + td * gap * 0.55, p + ld * ln, z, col, nrm)
		t += gap / L


## A bracken frond on its stalk: bare for the lowest third, then a broad
## three-cornered blade of side branches, the longest at the foot, each with
## small oval leaflets both sides that just overlap (real leaf shapes: the
## fern's pointed lobes at this size read as a lattice of arrowheads).
static func _cell_bracken(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var stipe := 0.28
	var top := 0.7
	_stem2(b, PackedVector2Array([Vector2.ZERO, Vector2(0.0, stipe), Vector2(0.0, stipe + top)]), 0.008, 0.002, Color.WHITE)
	var t := 0.0
	while t < 0.97:
		var o := Vector2(0.0, stipe + top * t)
		var reach := 0.47 * pow(1.0 - t, 0.85) + 0.02
		for sgn: float in [-1.0, 1.0]:
			var d := Vector2(0.0, 1.0).rotated(-sgn * lerpf(1.25, 0.8, t) + rng.randf_range(-0.05, 0.05))
			var pts := PackedVector2Array([o])
			for k in 4:
				d = d.rotated(sgn * 0.06)        # each branch curves up toward the frond's tip
				pts.append(pts[k] + d * reach / 4.0)
			_stem2(b, pts, 0.004, 0.0015, Color.WHITE)
			var u := 0.1
			var side := 1.0
			while u < 1.0:
				var f := u * 4.0
				var i0 := mini(int(f), 3)
				var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
				var td := (pts[i0 + 1] - pts[i0]).normalized()
				var ln := (0.075 * pow(1.0 - u, 0.6) + 0.018) * minf(reach / 0.25, 1.0)
				_leaf2(b, rng, p, td.rotated(side * rng.randf_range(0.95, 1.25)), ln, ln * 0.3)
				side = -side
				u += 0.02 / reach
			_leaf2(b, rng, pts[4], d, 0.03, 0.01)
		t += lerpf(0.105, 0.06, t)
	_fit(b)
	return b


## Cow parsley from the side, in its own colours: a few stems forking toward
## the top, ferny leaves low down, a flat white umbel on every tip.
static func _cell_umbel(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var green := Color(0.17, 0.3, 0.085)
	var stalk := Color(0.27, 0.36, 0.14)
	for i in 3:
		var d := Vector2(0.0, 1.0).rotated((float(i) - 1.0) * 0.2 + rng.randf_range(-0.07, 0.07))
		var H := rng.randf_range(0.5, 0.74)
		var pts := PackedVector2Array([Vector2(rng.randf_range(-0.03, 0.03), 0.0)])
		for k in 4:
			d = d.rotated(rng.randf_range(-0.07, 0.07))
			pts.append(pts[k] + d * H / 4.0)
		_stem2(b, pts, 0.0065, 0.0035, stalk)
		for k in 2:
			var at := rng.randf_range(0.5, 2.2)
			var p := pts[int(at)].lerp(pts[int(at) + 1], at - floor(at))
			var s := 1.0 if (k + i) % 2 == 0 else -1.0
			_frond2(b, rng, p, d.rotated(s * rng.randf_range(0.75, 1.15)), rng.randf_range(0.2, 0.3), 0.075, 1, 0.3, 0.03, green, -s * 0.07, 0.03)
		var forks := rng.randi_range(2, 3)
		for k in forks:
			var fd := d.rotated((float(k) - float(forks - 1) * 0.5) * 0.55 + rng.randf_range(-0.12, 0.12))
			var tip := pts[4] + fd * rng.randf_range(0.1, 0.24)
			_stem2(b, PackedVector2Array([pts[4], tip]), 0.0035, 0.0025, stalk)
			# (off-white and no brighter: white florets at full strength shone out of a night meadow)
			_umbel2(b, rng, tip, fd, rng.randf_range(0.065, 0.095), Color(0.62, 0.62, 0.55), stalk, 1.0)
	_fit(b)
	return b


## An umbel from the side: rays fanning from the stem's tip to a nearly flat
## top, a cluster of florets (`florets` 0: none, a dry skeleton) on each.
static func _umbel2(b: Builder, rng: RandomNumberGenerator, o: Vector2, dir: Vector2, r: float, bloom: Color, stalk: Color, florets: float) -> void:
	var rays := 9
	for i in rays:
		var a := lerpf(-1.0, 1.0, float(i) / float(rays - 1)) + rng.randf_range(-0.05, 0.05)
		var tip := o + dir.rotated(a) * r * 0.7 / cos(a * 0.75)      # a low dome, not a ball
		_stem2(b, PackedVector2Array([o, tip]), 0.0016 if florets > 0.0 else 0.0028, 0.0013 if florets > 0.0 else 0.0022, stalk)
		for k in int(5.0 * florets) + (1 if florets <= 0.0 else 0):
			var z := 0.01 + rng.randf() * 0.03
			var g := rng.randf_range(0.8, 1.0) if florets > 0.0 else rng.randf_range(0.5, 0.8)
			var spread := 0.016 if florets > 0.0 else 0.0
			_dot2(b, tip + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.6)) * spread, rng.randf_range(0.007, 0.011) if florets > 0.0 else 0.0085,
					z, Color(bloom.r * g, bloom.g * g, bloom.b * g, _leaf_a(0.6 + 12.0 * z)))


## Fireweed from the side, in its own colours: straight stems, narrow leaves
## all the way up, a tapering spire of magenta flowers with dark buds at its tip.
static func _cell_fireweed(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var green := Color(0.16, 0.29, 0.085)
	var stalk := Color(0.33, 0.27, 0.15)
	var bloom := Color(0.6, 0.12, 0.4)
	for i in 3:
		var H := rng.randf_range(0.72, 0.97)
		var d := Vector2(0.0, 1.0).rotated(rng.randf_range(-0.07, 0.07))
		var pts := PackedVector2Array([Vector2([-0.26, 0.02, 0.27][i] + rng.randf_range(-0.04, 0.04), 0.0)])
		for k in 5:
			d = d.rotated(rng.randf_range(-0.035, 0.035))
			pts.append(pts[k] + d * H / 5.0)
		_stem2(b, pts, 0.006, 0.002, stalk)
		var t := 0.06
		var side := 1.0
		while t < 0.985:
			var f := t * 5.0
			var i0 := mini(int(f), 4)
			var p := pts[i0].lerp(pts[i0 + 1], f - float(i0))
			var td := (pts[i0 + 1] - pts[i0]).normalized()
			if t < 0.6:
				_leaf2(b, rng, p, td.rotated(side * rng.randf_range(1.0, 1.5)), 0.16 * (1.0 - 0.55 * t) * rng.randf_range(0.85, 1.1), 0.0125, green)
				t += 0.03 / H
			elif t < 0.9:
				# A flower: four petals round a short stalk.
				var c := p + td.rotated(side * rng.randf_range(1.0, 1.4)) * rng.randf_range(0.022, 0.04) * (1.25 - t)
				for k in 4:
					var a := TAU * float(k) / 4.0 + rng.randf() * 0.8
					var z := 0.02 + rng.randf() * 0.03
					var g := rng.randf_range(0.75, 1.1)
					_dot2(b, c + Vector2(cos(a), sin(a)) * 0.011, 0.0115, z, Color(bloom.r * g, bloom.g * g * rng.randf_range(0.8, 1.3), bloom.b * g, _leaf_a(0.5 + 10.0 * z)))
				t += 0.021 / H
			else:
				_dot2(b, p + td.rotated(side * 1.3) * 0.009, 0.0075 * (1.6 - t), 0.02, Color(bloom.r * 0.6, bloom.g * 0.5, bloom.b * 0.75, _leaf_a(0.7)))
				t += 0.014 / H
			side = -side
	_fit(b)
	return b


## Fallen leaves lying on the ground, from above: a few loose clumps of
## different sizes off the patch's middle and strays between them, so the
## patch has no outline of its own (one even disc of leaves read as a mat
## laid on the grass); each leaf a little different in colour (the card's own
## colour multiplies it: gold to brown).
static func _cell_litter(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	var tones: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.55), Color(0.7, 0.5, 0.36), Color(1.0, 0.62, 0.34), Color(0.45, 0.36, 0.3), Color(0.85, 0.95, 0.6),
			Color(0.6, 0.42, 0.3), Color(0.8, 0.7, 0.5)]
	var clumps: Array[Vector3] = []          # x, y, radius
	for k in 4:
		clumps.append(Vector3(rng.randf_range(-0.27, 0.27), 0.5 + rng.randf_range(-0.27, 0.27), rng.randf_range(0.07, 0.2)))
	for i in 60:
		var p := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(0.1, 0.9))     # a stray
		if i < 46:
			var c := clumps[rng.randi() % clumps.size()]
			var a := rng.randf() * TAU
			var r := pow(rng.randf(), 0.8) * c.z
			p = Vector2(clampf(c.x + cos(a) * r, -0.41, 0.41), clampf(c.y + sin(a) * r, 0.09, 0.91))
		_leaf2(b, rng, p, Vector2.from_angle(rng.randf() * TAU), rng.randf_range(0.04, 0.068), rng.randf_range(0.015, 0.024), tones[rng.randi() % tones.size()])
	return b


## Dry stalks with their seed heads, from the side: the skeletons of umbels,
## and plumes nodding to one side.
static func _cell_seed(rng: RandomNumberGenerator) -> Builder:
	var b := Builder.new()
	for i in 7:
		var H := rng.randf_range(0.45, 0.93)
		var d := Vector2(0.0, 1.0).rotated(rng.randf_range(-0.22, 0.22))
		var pts := PackedVector2Array([Vector2(rng.randf_range(-0.32, 0.32), 0.0)])
		for k in 4:
			d = d.rotated(rng.randf_range(-0.08, 0.08))
			pts.append(pts[k] + d * H / 4.0)
		var g := rng.randf_range(0.7, 1.0)
		var tone := Color(g, g, g)
		_stem2(b, pts, 0.006, 0.0035, tone)
		if i % 2 == 0:
			_umbel2(b, rng, pts[4], d, rng.randf_range(0.07, 0.11), Color(0.75, 0.7, 0.62), tone, 0.0)
		else:
			# A plume: short threads off the last stretch, all hanging the same way.
			var s := 1.0 if rng.randf() < 0.5 else -1.0
			for k in 9:
				var p := pts[3].lerp(pts[4], float(k) / 8.0)
				var e := p + d.rotated(s * rng.randf_range(0.9, 1.5)) * rng.randf_range(0.03, 0.07)
				_stem2(b, PackedVector2Array([p, e]), 0.003, 0.0022, tone)
				_dot2(b, e, 0.008, 0.02, Color(g, g, g, _leaf_a(0.9)))
	_fit(b)
	return b


## The plain colour behind a cell in the atlas (its edges blur into it in the small copies).
static func atlas_backdrop(cell: int) -> Color:
	match cell:
		HERB_A:
			return Color(0.3, 0.4, 0.2)
		HERB_B:
			return Color(0.3, 0.26, 0.2)
	return Color(0.62, 0.62, 0.56)


## A boulder: a sphere pushed about by noise, then broken by flat faces
## (planes it is cut back to), with hard edges where faces meet and smooth
## shading across each. form 0: a rounded block with a few broken faces;
## 1: a slab, flat-topped and low; 2: a block split along three sets of joints,
## its corners knocked off; 3: a shard, long and tilted. lod 1: the same shape
## from a coarse sphere (far off, and the small stones round a big one).
static func rock(seed_value: int, mat: Material, col: Color, form := 0, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.frequency = 0.9
	fn.fractal_octaves = 3
	var planes: Array[Vector4] = []
	var stretch := Vector3(1.0, rng.randf_range(0.6, 0.85), 1.0)
	var lump := 0.42
	match form:
		1:
			var up := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized()
			planes.append(Vector4(up.x, up.y, up.z, rng.randf_range(0.34, 0.46)))
			for i in 5:
				var a := TAU * float(i) / 5.0 + rng.randf_range(-0.4, 0.4)
				var pn := Vector3(cos(a), rng.randf_range(-0.15, 0.35), sin(a)).normalized()
				planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.7, 0.95)))
			stretch = Vector3(rng.randf_range(1.1, 1.5), 1.0, rng.randf_range(0.85, 1.1))
			lump = 0.3
		2:
			var frame := Basis(Vector3(rng.randf_range(-1.0, 1.0), 2.5, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf() * TAU)
			for axis: Vector3 in [frame.x, frame.y, frame.z]:
				for sgn: float in [1.0, -1.0]:
					var pn := (axis * sgn + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))).normalized()
					planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.5, 0.74)))
			for i in 3:
				var pn := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.1, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
				planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.78, 0.9)))
			stretch = Vector3(1.0, rng.randf_range(0.75, 1.0), 1.0)
			lump = 0.25
		3:
			for i in 6:
				var pn := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.25, 0.5), rng.randf_range(-1.0, 1.0)).normalized()
				planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.5, 0.8)))
			stretch = Vector3(0.75, 1.45, 0.6)
		_:
			for i in 7:
				var pn := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
				planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.62, 0.9)))
	var tilt := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(0.3, 0.6)) if form == 3 else Basis.IDENTITY
	var sphere := SphereMesh.new()
	sphere.radial_segments = 22 if lod == 0 else 8
	sphere.rings = 12 if lod == 0 else 4
	var src: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var pos := PackedVector3Array()
	pos.resize(verts.size())
	for i in verts.size():
		var p := verts[i].normalized()
		p *= 1.0 + fn.get_noise_3dv(p * 1.3) * lump
		for pl in planes:
			var pn := Vector3(pl.x, pl.y, pl.z)
			var d := p.dot(pn)
			if d > pl.w:
				p -= pn * (d - pl.w)
		# A broken face is never quite flat.
		p *= 1.0 + fn.get_noise_3dv(p * 4.3 + Vector3(7.0, 3.0, 5.0)) * 0.045
		p = tilt * (p * stretch)
		p.y = maxf(p.y, -0.5)          # what lies in the ground is not worth its triangles' height
		pos[i] = p
	# Normals: each corner takes the faces round it that lie within the crease
	# angle of its own face, so broken edges stay sharp and faces shade smooth.
	var tris := idx.size() / 3
	var face_n := PackedVector3Array()
	face_n.resize(tris)
	var around := {}                   # welded position -> the faces that touch it
	for f in tris:
		var a := pos[idx[f * 3]]
		var n := (pos[idx[f * 3 + 1]] - a).cross(pos[idx[f * 3 + 2]] - a)
		if n.dot(a + pos[idx[f * 3 + 1]] + pos[idx[f * 3 + 2]]) < 0.0:
			n = -n
		face_n[f] = n                  # its length is twice the face's area: big faces weigh more
		for k in 3:
			var key := Vector3i((pos[idx[f * 3 + k]] * 2000.0).round())
			if not around.has(key):
				around[key] = []
			(around[key] as Array).append(f)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	for f in tris:
		var fl := face_n[f].length()
		if fl < 1e-9:
			continue                   # the sphere's poles: no area
		var fu := face_n[f] / fl
		for k in 3:
			var p := pos[idx[f * 3 + k]]
			var n := Vector3.ZERO
			for g: int in around[Vector3i((p * 2000.0).round())]:
				var gl := face_n[g].length()
				if gl > 1e-9 and face_n[g].dot(fu) / gl > 0.72:
					n += face_n[g]
			var ao := clampf(0.55 + 0.45 * (p.length() - 0.7), 0.3, 1.0) * clampf(0.5 + p.y, 0.35, 1.0)
			out_v.append(p)
			out_n.append(n.normalized())
			out_c.append(Color(col.r, col.g, col.b, ao))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_v
	arr[Mesh.ARRAY_NORMAL] = out_n
	arr[Mesh.ARRAY_COLOR] = out_c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
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
			b.tri(r0, r0 + 1, r1)
			b.tri(r0 + 1, r1 + 1, r1)


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


## A barrel cactus: short, fat, deeply ribbed, leaning a little, a ring of red
## flowers on top (in the skin's own surface: one draw). lod 1: a plain keg.
static func barrel(seed_value: int, mat: Material, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var h := rng.randf_range(0.45, 1.1)
	var r := rng.randf_range(0.26, 0.38)
	var tilt := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(0.05, 0.2))
	var col := _column(Vector3(0, -0.1, 0), Vector3(0, h, 0) + tilt, r, 4 if lod == 0 else 1)
	ribbed_tube(b, col[0], col[1], 32 if lod == 0 else 9, 18, 0.11 if lod == 0 else 0.0, Color(0.3, 0.36, 0.2) if lod == 0 else Color(0.27, 0.325, 0.18))
	var top := Vector3(0, h + r * 0.85, 0) + tilt
	for i in (9 if lod == 0 else 3):
		var a := TAU * float(i) / (9.0 if lod == 0 else 3.0)
		var p := top + Vector3(cos(a), 0.0, sin(a)) * r * 0.45
		var pts := PackedVector3Array([p, p + Vector3(cos(a) * 0.04, 0.06, sin(a) * 0.04)])
		blade(b, pts, Vector3(-sin(a), 0, cos(a)), PackedFloat32Array([0.025, 0.04]) if lod == 0 else PackedFloat32Array([0.07, 0.1]), Color(0.85, 0.2, 0.12), 1.0, 1.0, 0.0, Vector3.UP, 0.5, 0.2)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, mat)
	return m


## Prickly pear: flat oval pads stacked off each other's rims, a few red fruit.
## lod 1: six-sided pads, no fruit.
static func prickly_pear(seed_value: int, mat: Material, lod := 0) -> ArrayMesh:
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
		_pad(b, centre, dir, across, hh, hw, Color(0.3, 0.42, 0.26).lightened(rng.randf_range(-0.05, 0.08)), 10 if lod == 0 else 6)
		if rng.randf() < 0.3:
			for k in 3:
				var fa := rng.randf_range(-0.9, 0.9)
				var fp := centre + dir * hh * cos(fa) + across * hw * sin(fa)
				if lod == 0:
					_pad(b, fp + dir * 0.03, dir, across, 0.035, 0.028, Color(0.6, 0.1, 0.18))
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, mat)
	return m


## One flat oval pad, a little thick, normals rounded toward its rim.
static func _pad(b: Builder, c: Vector3, up: Vector3, across: Vector3, hh: float, hw: float, col: Color, ring := 10) -> void:
	var face := up.cross(across).normalized()
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
## lod 1: every joint a plain three-sided stick.
static func cholla(seed_value: int, mat: Material, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	var col := Color(0.5, 0.5, 0.3)
	var top := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.4, 0.75), rng.randf_range(-0.1, 0.1))
	tube(b, PackedVector3Array([Vector3(0, -0.1, 0), top * 0.5, top]), PackedFloat32Array([0.08, 0.07, 0.065]), 6 if lod == 0 else 3, col.darkened(0.25), 0.4, 0.0)
	_joints(b, rng, top, Vector3.UP, 3, col, lod)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, mat)
	return m


static func _joints(b: Builder, rng: RandomNumberGenerator, o: Vector3, dir: Vector3, depth: int, col: Color, lod := 0) -> void:
	for i in rng.randi_range(2, 3):
		var d := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.5), rng.randf_range(-0.9, 0.9))).normalized()
		var L := rng.randf_range(0.14, 0.26)
		var end := o + d * L
		if lod == 0:
			tube(b, PackedVector3Array([o, o.lerp(end, 0.5), end, end + d * 0.03]), PackedFloat32Array([0.045, 0.055, 0.05, 0.02]), 5, col, 0.7, 0.0)
		else:
			tube(b, PackedVector3Array([o, end + d * 0.02]), PackedFloat32Array([0.058, 0.05]), 3, col, 0.7, 0.0)
		if depth > 0:
			_joints(b, rng, end, d, depth - 1, col, lod)


## Ocotillo: a fan of long thin whips from one root, small leaves up them, red
## flower tips (whips, leaves and flowers in one surface of solid blades: one
## draw). lod 1: three-sided whips, a flower each, no leaves.
static func ocotillo(seed_value: int, leaf_mat: Material, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Builder.new()
	for i in rng.randi_range(10, 18):
		var a := rng.randf() * TAU
		var lean := rng.randf_range(0.12, 0.45)
		var d := Vector3(cos(a) * lean, 1.0, sin(a) * lean).normalized()
		var L := rng.randf_range(2.4, 5.0)
		var bow := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.1, 0.35)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var base := Vector3(cos(a), 0, sin(a)) * 0.06
		var steps := 5 if lod == 0 else 3
		for k in steps:
			var t := float(k) / float(steps - 1)
			pts.append(base + d * L * t + bow * sin(PI * t))
			radii.append(lerpf(0.032, 0.01, t) * (1.0 if lod == 0 else 1.25))
		tube(b, pts, radii, 4 if lod == 0 else 3, Color(0.36, 0.33, 0.28), 0.5, 0.25)
		for k in 14:
			var t := rng.randf_range(0.25, 0.95)
			var p := base + d * L * t + bow * sin(PI * t)
			var ld := (Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 0.8), rng.randf_range(-1, 1))).normalized()
			if lod == 0:
				blade(b, PackedVector3Array([p, p + ld * 0.04]), ld.cross(Vector3.UP).normalized(), PackedFloat32Array([0.012, 0.0]),
						Color(0.3, 0.42, 0.14), 0.8, 1.0, 1.0, ld, 0.4, 0.0)
		var tip := pts[pts.size() - 1]
		for k in 5:
			var fd := (d + Vector3(rng.randf_range(-0.4, 0.4), 0.2, rng.randf_range(-0.4, 0.4))).normalized()
			if lod == 0 or k == 0:
				blade(b, PackedVector3Array([tip - d * 0.15, tip + fd * 0.05]), fd.cross(Vector3.UP).normalized(), PackedFloat32Array([0.018, 0.006]) if lod == 0 else PackedFloat32Array([0.035, 0.012]),
						Color(0.85, 0.18, 0.1), 1.0, 1.0, 1.0, fd, 0.4, 0.0)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	m.surface_set_material(0, leaf_mat)
	return m


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
static func creosote(seed_value: int, leaf_mat: Material, lod := 0) -> ArrayMesh:
	return bush(seed_value, leaf_mat, Color(0.22, 0.27, 0.11), [LEAF_SMALL], 0.75, 0, lod)
