class_name BridgeGen
## A timber trail bridge over a side stream, built from boxes along the trail's
## own line (it follows the trail's bends and grade): plank deck on two
## stringers, posts and two rails each side, a timber bent with a cross brace
## on each bank, and stone abutments at the ends. Runs on the terrain worker.

const WOOD := Color(0.42, 0.3, 0.2, 1.0)
const STONE := Color(0.45, 0.44, 0.41, 0.0)
const DECK_HALF := 1.3        # 2.6 m wide (the trail is 1.5 m)
const RAIL_SIDE := 1.25


## zc: where the stream crosses; half: reach along the trail either side;
## deck_top: deck height against the trail's; creek_half: the water's half width
## (the bents stand just outside it); ground: func(x, z, t) -> terrain height.
static func build(zc: float, half: float, deck_top: float, creek_half: float, t: Trail, ground: Callable) -> Dictionary:
	var b := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	# Planks across the trail, 0.24 m apart.
	var s := -half
	var k := 0
	while s <= half:
		var f := _frame(zc + s, deck_top, t)
		var tone := 0.85 + 0.3 * fposmod(sin(k * 91.7) * 4375.85, 1.0)
		_box(b, f.p - f.up * 0.045 + f.side * (fposmod(k * 0.37, 0.1) - 0.05), f.side * DECK_HALF, f.up * 0.045, f.fwd * 0.11, WOOD * Color(tone, tone, tone, 1.0))
		s += 0.24
		k += 1
	# Stringers and rails, 1 m pieces between frames so they follow the bends.
	var posts: Array = []
	s = -half
	while s < half - 0.01:
		var s1 := minf(s + 1.0, half)
		var a := _frame(zc + s, deck_top, t)
		var c := _frame(zc + s1, deck_top, t)
		for side in [-1.0, 1.0]:
			var pa: Vector3 = a.p + a.side * 0.95 * side - a.up * 0.29
			var pc: Vector3 = c.p + c.side * 0.95 * side - c.up * 0.29
			_box(b, (pa + pc) * 0.5, (pc - pa) * 0.52, a.up * 0.2, a.side * 0.1, WOOD * Color(0.8, 0.8, 0.8, 1.0))
		s = s1
	# Posts every 2 m, rails between them at 0.55 m and 1.05 m.
	var n := int(round(half * 2.0 / 2.0))
	for side in [-1.0, 1.0]:
		var prev := {}
		for j in n + 1:
			var f := _frame(zc - half + j * (half * 2.0 / n), deck_top, t)
			var base: Vector3 = f.p + f.side * RAIL_SIDE * side
			_box(b, base + Vector3.UP * 0.53, Vector3.UP * 0.57, f.fwd * 0.065, f.side * 0.065, WOOD)
			if not prev.is_empty():
				for hgt in [0.55, 1.05]:
					var p0: Vector3 = prev.base + Vector3.UP * hgt
					var p1: Vector3 = base + Vector3.UP * hgt
					_box(b, (p0 + p1) * 0.5, (p1 - p0) * 0.5, Vector3.UP * (0.05 if hgt > 1.0 else 0.04), f.side * 0.045, WOOD * Color(0.95, 0.95, 0.95, 1.0))
			prev = {"base": base}
	# A bent on each bank: two posts to the ground, a cap beam, one diagonal brace.
	for side in [-1.0, 1.0]:
		var f := _frame(zc + side * (creek_half + 1.2), deck_top, t)
		var cap: Vector3 = f.p - f.up * 0.6
		var feet: Array[Vector3] = []
		for lr in [-1.0, 1.0]:
			var top: Vector3 = cap + f.side * 0.95 * lr
			var g := float(ground.call(top.x, top.z, t)) - 0.4
			var foot := Vector3(top.x, minf(g, top.y - 0.3), top.z)
			feet.append(foot)
			_box(b, (top + foot) * 0.5, (top - foot) * 0.5, f.fwd * 0.09, f.side * 0.09, WOOD * Color(0.75, 0.75, 0.75, 1.0))
		_box(b, cap, f.side * 1.15, f.up * 0.1, f.fwd * 0.1, WOOD * Color(0.8, 0.8, 0.8, 1.0))
		var ta: Vector3 = cap - f.side * 0.95
		var fb: Vector3 = feet[1] + (cap + f.side * 0.95 - feet[1]) * 0.15
		_box(b, (ta + fb) * 0.5, (fb - ta) * 0.5, f.fwd * 0.06, (fb - ta).cross(f.fwd).normalized() * 0.06, WOOD * Color(0.85, 0.85, 0.85, 1.0))
	# Stone abutments where the deck meets the banks.
	for side in [-1.0, 1.0]:
		var f := _frame(zc + side * (half - 1.0), deck_top, t)
		_box(b, f.p - f.up * 1.05, f.side * 1.7, f.up * 0.95, f.fwd * 1.0, STONE)
	return b


static func mesh(b: Dictionary) -> ArrayMesh:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = b.v
	a[Mesh.ARRAY_NORMAL] = b.n
	a[Mesh.ARRAY_COLOR] = b.c
	a[Mesh.ARRAY_TEX_UV] = b.uv
	a[Mesh.ARRAY_INDEX] = b.i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## The deck's frame at distance z: centre point on the deck top, forward along
## the trail, side across it, up out of the deck.
static func _frame(z: float, deck_top: float, t: Trail) -> Dictionary:
	var p := Vector3(t.x_at(z), t.h_at(z) + deck_top, z)
	var fwd := Vector3(t.dx_at(z), t.h_at(z + 0.5) - t.h_at(z - 0.5), 1.0).normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	var up := fwd.cross(side).normalized()
	if up.y < 0.0:
		up = -up
	return {"p": p, "fwd": fwd, "side": side, "up": up}


## A box from its centre and three half-extent vectors; ax is its length (the
## grain runs along it). UV in metres.
static func _box(b: Dictionary, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color) -> void:
	var axes := [ax, ay, az]
	for i in 3:
		var nrm: Vector3 = axes[i]
		var u: Vector3 = axes[(i + 1) % 3]
		var w: Vector3 = axes[(i + 2) % 3]
		for sgn in [-1.0, 1.0]:
			var centre: Vector3 = c + nrm * sgn
			var nn: Vector3 = nrm.normalized() * sgn
			var base: int = b.v.size()
			var lu: float = u.length()
			var lw: float = w.length()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				b.v.append(centre + u * corner.x + w * corner.y)
				b.n.append(nn)
				b.c.append(col)
				# Grain along ax: whichever face axis is ax goes to UV.x.
				var along: float = corner.x * lu if i == 2 else corner.y * lw
				var across: float = corner.y * lw if i == 2 else corner.x * lu
				b.uv.append(Vector2(along, across) + Vector2(c.x + c.z, c.y) * 0.37)
			# Godot's front faces wind clockwise seen from outside.
			if u.cross(w).dot(nn) > 0.0:
				b.i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			else:
				b.i.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
