class_name Route
extends RefCounted
## A real-world route from a GPX file: where it goes (lat/lon), how far, its
## height profile (smoothed, since GPS elevation is noisy) and, once looked up,
## what the land is like along it (RouteLandCover fills `biomes`).

const EARTH_R := 6371000.0
const STEP := 10.0              ## the smoothed height profile has one sample per STEP metres
const SMOOTH_HALF := 3          ## moving average over ±3 samples (~60 m), applied twice
const MAX_GRADE := 20.0

var name := ""
var source := ""                     ## the library file it was loaded from
var lats := PackedFloat64Array()
var lons := PackedFloat64Array()
var eles := PackedFloat64Array()     ## raw, per point (0 when the file has none)
var dist := PackedFloat64Array()     ## cumulative metres at each point
var has_elevation := false
var length := 0.0
var climb := 0.0                     ## metres of ascent on the smoothed profile
## Scenery along the route, in order: {from, to, id, trees, water}. `id` is a
## RealFlora biome id, `trees` a density multiplier, `water` a river or lake nearby.
var biomes: Array[Dictionary] = []
var estimated := false               ## biomes guessed from climate alone (the map lookup failed)
var _profile := PackedFloat64Array()


## Build from points; call once after filling lats/lons/eles.
func finish() -> void:
	dist.resize(lats.size())
	var total := 0.0
	for i in lats.size():
		if i > 0:
			total += haversine(lats[i - 1], lons[i - 1], lats[i], lons[i])
		dist[i] = total
	length = total
	_build_profile()


static func haversine(la1: float, lo1: float, la2: float, lo2: float) -> float:
	var p1 := deg_to_rad(la1)
	var p2 := deg_to_rad(la2)
	var dp := p2 - p1
	var dl := deg_to_rad(lo2 - lo1)
	var a := sin(dp * 0.5) ** 2 + cos(p1) * cos(p2) * sin(dl * 0.5) ** 2
	return 2.0 * EARTH_R * asin(minf(sqrt(a), 1.0))


func _build_profile() -> void:
	var n := int(ceil(length / STEP)) + 1
	_profile.resize(n)
	var j := 0
	for k in n:
		var d := minf(k * STEP, length)
		while j < dist.size() - 2 and dist[j + 1] < d:
			j += 1
		_profile[k] = _lerp_points(eles, j, d) if has_elevation else 0.0
	for pass_i in 2:
		var src := _profile.duplicate()
		for k in n:
			var s := 0.0
			var c := 0
			for o in range(-SMOOTH_HALF, SMOOTH_HALF + 1):
				var q := k + o
				if q >= 0 and q < n:
					s += src[q]
					c += 1
			_profile[k] = s / c
	climb = 0.0
	for k in range(1, n):
		climb += maxf(_profile[k] - _profile[k - 1], 0.0)


func _lerp_points(values: PackedFloat64Array, j: int, d: float) -> float:
	if values.size() == 1:
		return values[0]
	var seg := dist[j + 1] - dist[j]
	var f := 0.0 if seg <= 0.0 else clampf((d - dist[j]) / seg, 0.0, 1.0)
	return lerpf(values[j], values[j + 1], f)


## Index of the point segment containing distance d.
func _seg(d: float) -> int:
	var lo := 0
	var hi := dist.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if dist[mid] <= d:
			lo = mid
		else:
			hi = mid
	return lo


## Smoothed elevation (metres) at distance d along the route.
func ele_at(d: float) -> float:
	if _profile.is_empty():
		return 0.0
	var f := clampf(d, 0.0, length) / STEP
	var k := mini(int(f), _profile.size() - 1)
	var k1 := mini(k + 1, _profile.size() - 1)
	return lerpf(_profile[k], _profile[k1], f - k)


## Grade in percent at distance d, from the smoothed profile, clamped to ±20 %.
func grade_at(d: float) -> float:
	if length < STEP * 2.0:
		return 0.0
	var a := clampf(d - STEP, 0.0, length)
	var b := clampf(d + STEP, 0.0, length)
	if b - a < 1.0:
		return 0.0
	return clampf((ele_at(b) - ele_at(a)) / (b - a) * 100.0, -MAX_GRADE, MAX_GRADE)


## Vector2(lat, lon) at distance d.
func latlon_at(d: float) -> Vector2:
	if lats.is_empty():
		return Vector2.ZERO
	if lats.size() == 1:
		return Vector2(lats[0], lons[0])
	var j := _seg(clampf(d, 0.0, length))
	var dd := clampf(d, 0.0, length)
	return Vector2(_lerp_points(lats, j, dd), _lerp_points(lons, j, dd))


## The scenery segment at distance d (the last one past the end); {} before any lookup.
func biome_at(d: float) -> Dictionary:
	for b in biomes:
		if d < float(b.to):
			return b
	return biomes[-1] if not biomes.is_empty() else {}


## The biome covering most of the route ("summer" before any lookup).
func main_biome() -> String:
	var by := {}
	for b in biomes:
		by[b.id] = float(by.get(b.id, 0.0)) + float(b.to) - float(b.from)
	var best := "summer"
	var most := -1.0
	for id in by:
		if by[id] > most:
			most = by[id]
			best = id
	return best


## A free ride is one open segment; the ride ends at the route's distance
## (RideScreen), long before this runs out.
func free_ride_workout() -> Workout:
	var w := Workout.new()
	w.name = name
	var seg := WorkoutSegment.new()
	seg.kind = WorkoutSegment.Kind.FREE_RIDE
	seg.duration = 12.0 * 3600.0
	w.segments.append(seg)
	w.rebuild_index()
	return w
