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
const SNAP_IN := 2.5          ## a later pass this close to an earlier one is the same road
const SNAP_OUT := 5.0
const SNAP_GAP := 30         ## ...but not the route's own last 60 m
const H_SMOOTH := 12         ## ground profile: moving average over ±12 samples (±24 m), twice

var route: Route
var geo: Geo
var start := 20.0
var datum := 0.0             ## added to the route's heights to sit on the elevation data
var is_loop := false
var _px := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _grid: Dictionary = {}   ## Vector2i cell -> PackedInt32Array of sample indices
var _coarse: PackedInt32Array = []   ## every 25th sample, for far lookups
## Height of each path sample, from the elevation data along the path (smoothed).
## It depends only on where the sample is, so where the route runs over the same
## road twice (Freewheel's start and finish) both passes share one height.
var _h := PackedFloat32Array()
var _repeat := PackedFloat32Array()  ## per sample: how fully it lies on an earlier pass (0..1)


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
	_build_grid()
	var snaps := _snap_repeats()
	_repeat = snaps[1]
	_build_grid()
	if dem != null and dem.has_data():
		_h.resize(n)
		for i in n:
			_h[i] = dem.height(_px[i], _pz[i])
		for pass_i in 2:
			_h = _box(_h, H_SMOOTH)
		# A repeated pass takes the first pass's heights too.
		for i in n:
			var at: float = snaps[0][i]
			if at >= 0.0:
				var j := int(at)
				var hj := lerpf(_h[j], _h[mini(j + 1, n - 1)], at - j)
				_h[i] = lerpf(_h[i], hj, snaps[1][i])


func _build_grid() -> void:
	_grid.clear()
	_coarse.clear()
	for i in _px.size():
		var key := Vector2i(floori(_px[i] / CELL), floori(_pz[i] / CELL))
		var cell: PackedInt32Array = _grid.get(key, PackedInt32Array())
		cell.append(i)
		_grid[key] = cell          # packed arrays are values: store the grown copy back
		if i % 25 == 0:
			_coarse.append(i)


## Where the route runs over road it has already ridden (an out-and-back, a
## loop's shared start and finish), two GPS lines lie a metre or so apart; each
## would carve its own groove and the wheels would hop between them. Pull every
## later pass onto the first one (fully within SNAP_IN, easing off by SNAP_OUT).
## Returns [earlier sample position per sample (-1: none), pull weight].
func _snap_repeats() -> Array:
	var n := _px.size()
	var at := PackedFloat32Array()
	var wt := PackedFloat32Array()
	at.resize(n)
	wt.resize(n)
	at.fill(-1.0)
	for i in range(SNAP_GAP, n):
		var p := Vector2(_px[i], _pz[i])
		var best := SNAP_OUT * SNAP_OUT
		var bq := Vector2.ZERO
		var bj := -1.0
		var cx := floori(p.x / CELL)
		var cz := floori(p.y / CELL)
		for gx in range(cx - 1, cx + 2):
			for gz in range(cz - 1, cz + 2):
				var cell: Variant = _grid.get(Vector2i(gx, gz))
				if cell == null:
					continue
				for j in cell as PackedInt32Array:
					if j + 1 >= i - SNAP_GAP:
						continue
					var a := Vector2(_px[j], _pz[j])
					var ab := Vector2(_px[j + 1], _pz[j + 1]) - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var q := a + ab * t
					var d2 := p.distance_squared_to(q)
					if d2 < best:
						best = d2
						bq = q
						bj = j + t
		if bj < 0.0:
			continue
		var w := 1.0 - smoothstep(SNAP_IN, SNAP_OUT, sqrt(best))
		_px[i] = lerpf(p.x, bq.x, w)
		_pz[i] = lerpf(p.y, bq.y, w)
		at[i] = bj
		wt[i] = w
	return [at, wt]


## Moving average over ±k samples (shorter at the ends), by running sums.
static func _box(v: PackedFloat32Array, k: int) -> PackedFloat32Array:
	var n := v.size()
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	sums[0] = 0.0
	for i in n:
		sums[i + 1] = sums[i] + v[i]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var lo := maxi(i - k, 0)
		var hi := mini(i + k, n - 1)
		out[i] = (sums[hi + 1] - sums[lo]) / float(hi - lo + 1)
	return out


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
	var s := maxf(_route_s(z).x, 0.0)
	if _h.is_empty():
		return route.ele_at(s) + datum
	var f := minf(s, route.length) / STEP_R
	var i := mini(int(f), _h.size() - 2)
	return lerpf(_h[i], _h[i + 1], clampf(f - i, 0.0, 1.0))


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


## Grade (%) the way the rider is going: from the same heights the ground shows,
## so the trainer climbs what the screen climbs (and flips on the way back).
func grade_at(z: float) -> float:
	if _h.is_empty():
		var rs := _route_s(z)
		return route.grade_at(maxf(rs.x, 0.0)) * rs.y
	return clampf((h_at(z + 10.0) - h_at(z - 10.0)) / 20.0 * 100.0, -Route.MAX_GRADE, Route.MAX_GRADE)


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
## Measured to the path's segments, not its sample points, so a second pass of
## the same road a few centimetres off never beats the line you are on.
func nearest(x: float, z: float, reach: float) -> Vector3:
	var p := Vector2(x, z)
	var best := reach
	var out := Vector3.ZERO
	var r := int(ceil((reach + STEP_R) / CELL))
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	var last := _px.size() - 1
	for gx in range(cx - r, cx + r + 1):
		for gz in range(cz - r, cz + r + 1):
			var cell: Variant = _grid.get(Vector2i(gx, gz))
			if cell == null:
				continue
			for j in cell as PackedInt32Array:
				if j >= last:
					continue
				var dx := _px[j] - x
				var dz := _pz[j] - z
				if dx * dx + dz * dz > (best + STEP_R) * (best + STEP_R):
					continue                   # its segment cannot be nearer
				var hit := _on_segment(j, p)
				if absf(hit.y) < best:
					best = absf(hit.y)
					out = hit
	return out


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
		var hit := _on_segment(j, p)
		if absf(hit.y) < best:
			best = absf(hit.y)
			out = hit
	return out


## p projected onto segment j..j+1: Vector3(trail z, signed lateral, 1).
func _on_segment(j: int, p: Vector2) -> Vector3:
	var a := Vector2(_px[j], _pz[j])
	var ab := Vector2(_px[j + 1], _pz[j + 1]) - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var d := p.distance_to(a + ab * t)
	var side := signf(ab.x * (p.y - a.y) - ab.y * (p.x - a.x))
	return Vector3((j + t) * STEP_R + start, d * (side if side != 0.0 else 1.0), 1.0)


## Sample i lies on road an earlier pass already covers (draw that road once).
func is_repeat(i: int) -> bool:
	return i < _repeat.size() and _repeat[i] > 0.99


func sample_count() -> int:
	return _px.size()


func sample_xz(i: int) -> Vector2:
	return Vector2(_px[i], _pz[i])


## Trail z of path sample i.
func sample_z(i: int) -> float:
	return i * STEP_R + start
