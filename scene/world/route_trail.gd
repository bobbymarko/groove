class_name RouteTrail
extends Trail
## The trail along a real route's shape (R42): every corner, switchback and
## loop, in the route's flat metre frame. Same calls as Trail, by trail
## distance z (the route's metre 0 sits at `start`, where every ride begins).
## Corners are rounded a little so the wheel never meets a kink. Past the end a
## loop carries on round; a point-to-point route turns back the way it came.

const STEP_R := 2.0          ## metres between path samples
const SMOOTH := 4            ## moving average over ±4 samples (±8 m), twice
const CELL := 32.0           ## nearest-point grid

var route: Route
var geo: Geo
var start := 20.0
var datum := 0.0             ## added to the route's heights to sit on the elevation data
var is_loop := false
var _px := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _grid: Dictionary = {}   ## Vector2i cell -> PackedInt32Array of sample indices
var _coarse: PackedInt32Array = []   ## every 25th sample, for far lookups


func _init(r: Route, g: Geo, dem: RouteDem = null) -> void:
	super()
	route = r
	geo = g
	var n := int(ceil(r.length / STEP_R)) + 1
	_px.resize(n)
	_pz.resize(n)
	for i in n:
		var p := g.to_local(r.latlon_at(minf(i * STEP_R, r.length)))
		_px[i] = p.x
		_pz[i] = p.y
	for pass_i in 2:
		var sx := _px.duplicate()
		var sz := _pz.duplicate()
		for i in n:
			var ax := 0.0
			var az := 0.0
			var c := 0
			for o in range(-SMOOTH, SMOOTH + 1):
				var k := clampi(i + o, 0, n - 1)
				ax += sx[k]
				az += sz[k]
				c += 1
			_px[i] = ax / c
			_pz[i] = az / c
	is_loop = Vector2(_px[0], _pz[0]).distance_to(Vector2(_px[n - 1], _pz[n - 1])) < 60.0
	for i in n:
		var key := Vector2i(floori(_px[i] / CELL), floori(_pz[i] / CELL))
		var cell: PackedInt32Array = _grid.get(key, PackedInt32Array())
		cell.append(i)
		_grid[key] = cell          # packed arrays are values: store the grown copy back
		if i % 25 == 0:
			_coarse.append(i)
	if dem != null and dem.has_data():
		# Sit the route's (smoothed GPX) heights on the elevation data.
		var diffs: Array[float] = []
		for i in range(0, n, 50):
			diffs.append(dem.height(_px[i], _pz[i]) - r.ele_at(i * STEP_R))
		diffs.sort()
		datum = diffs[diffs.size() / 2]


## Trail distance z -> (route metres, direction): loops wrap, others turn back.
func _route_s(z: float) -> Vector2:
	var s := z - start
	var L := route.length
	if s <= L or L <= 0.0:
		return Vector2(s, 1.0)
	if is_loop:
		return Vector2(fposmod(s, L), 1.0)
	var m := fposmod(s, 2.0 * L)
	return Vector2(m, 1.0) if m <= L else Vector2(2.0 * L - m, -1.0)


func _xz(s: float) -> Vector2:
	if s < 0.0:
		# Before the route's start: straight on back along its first heading.
		var d0 := Vector2(_px[1] - _px[0], _pz[1] - _pz[0]).normalized()
		return Vector2(_px[0], _pz[0]) + d0 * s
	var f := minf(s, route.length) / STEP_R
	var i := mini(int(f), _px.size() - 2)
	var t := clampf(f - i, 0.0, 1.0)
	return Vector2(lerpf(_px[i], _px[i + 1], t), lerpf(_pz[i], _pz[i + 1], t))


func h_at(z: float) -> float:
	var rs := _route_s(z)
	return route.ele_at(maxf(rs.x, 0.0)) + datum


func x_at(z: float) -> float:
	return _xz(_route_s(z).x).x


func dx_at(z: float) -> float:
	return (x_at(z + 0.5) - x_at(z - 0.5))


func position_at(z: float) -> Vector3:
	var rs := _route_s(z)
	var p := _xz(rs.x)
	return Vector3(p.x, h_at(z), p.y)


func heading_at(z: float) -> Vector3:
	var a := position_at(z - 1.0)
	var b := position_at(z + 1.0)
	return (b - a).normalized()


func grade_at(z: float) -> float:
	var rs := _route_s(z)
	return route.grade_at(maxf(rs.x, 0.0)) * rs.y


## Signed curvature (1/m) in the ground plane; positive turns toward +x of the travel direction's left… as Trail: bends right positive.
func curvature_at(z: float) -> float:
	var a := position_at(z - 3.0)
	var b := position_at(z)
	var c := position_at(z + 3.0)
	var t1 := Vector2(b.x - a.x, b.z - a.z).normalized()
	var t2 := Vector2(c.x - b.x, c.z - b.z).normalized()
	return (t1.y * t2.x - t1.x * t2.y) / 3.0


func river_base(z: float) -> float:
	return h_at(z)


## Nearest point of the path to (x, z) within `reach` metres:
## Vector3(trail z, signed lateral offset, 1) or Vector3(0, 0, 0) when none.
func nearest(x: float, z: float, reach: float) -> Vector3:
	var best := reach * reach
	var bi := -1
	var r := int(ceil(reach / CELL))
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	for gx in range(cx - r, cx + r + 1):
		for gz in range(cz - r, cz + r + 1):
			var cell: Variant = _grid.get(Vector2i(gx, gz))
			if cell == null:
				continue
			for i in cell as PackedInt32Array:
				var dx := _px[i] - x
				var dz := _pz[i] - z
				var d2 := dx * dx + dz * dz
				if d2 < best:
					best = d2
					bi = i
	if bi < 0:
		return Vector3.ZERO
	return _refine(bi, x, z)


## The nearest point however far (coarse search, then refined): Vector3(trail z, lateral, 1).
func nearest_far(x: float, z: float) -> Vector3:
	var best := INF
	var bi := 0
	for i in _coarse:
		var dx := _px[i] - x
		var dz := _pz[i] - z
		var d2 := dx * dx + dz * dz
		if d2 < best:
			best = d2
			bi = i
	var lo := maxi(bi - 25, 0)
	var hi := mini(bi + 25, _px.size() - 1)
	for i in range(lo, hi + 1):
		var dx := _px[i] - x
		var dz := _pz[i] - z
		var d2 := dx * dx + dz * dz
		if d2 < best:
			best = d2
			bi = i
	return _refine(bi, x, z)


## Project onto the segments either side of sample i.
func _refine(i: int, x: float, z: float) -> Vector3:
	var p := Vector2(x, z)
	var best := INF
	var out := Vector3.ZERO
	for j in [i - 1, i]:
		if j < 0 or j + 1 >= _px.size():
			continue
		var a := Vector2(_px[j], _pz[j])
		var b := Vector2(_px[j + 1], _pz[j + 1])
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			var side := signf(ab.x * (p.y - a.y) - ab.y * (p.x - a.x))
			out = Vector3((j + t) * STEP_R + start, d * (side if side != 0.0 else 1.0), 1.0)
	return out


func sample_count() -> int:
	return _px.size()


func sample_xz(i: int) -> Vector2:
	return Vector2(_px[i], _pz[i])


## Trail z of path sample i.
func sample_z(i: int) -> float:
	return i * STEP_R + start
