class_name BiomeMap
extends RefCounted
## Which biome the realistic look shows at each point along the trail (R41).
## An ordinary ride has one segment; a route ride has the looked-up scenery,
## shifted to trail distance. Neighbouring biomes blend over BLEND metres:
## plants are dithered between them, the ground shader mixes its two looks,
## hills, river and creeks fade in and out.

const BLEND := 150.0

var segments: Array[Dictionary] = []   ## {from, to, id, trees, water, mix} in trail z, in order


static func single(id: String) -> BiomeMap:
	var m := BiomeMap.new()
	var water := str(RealFlora.BIOMES.get(id, {}).get("water", "")) != ""
	m.segments.append({"from": -INF, "to": INF, "id": id, "trees": 1.0, "water": water, "mix": ""})
	return m


## A route's scenery, its metre 0 at trail z = start. The first segment reaches
## back to the trail's start and the last runs on past the route's end.
static func for_route(route: Route, start: float) -> BiomeMap:
	if route.biomes.is_empty():
		return single(route.main_biome())
	var m := BiomeMap.new()
	for b in route.biomes:
		m.segments.append({"from": float(b.from) + start, "to": float(b.to) + start, "id": str(b.id),
			"trees": float(b.get("trees", 1.0)), "water": bool(b.get("water", false)), "mix": str(b.get("mix", ""))})
	m.segments[0].from = -INF
	m.segments[-1].to = INF
	return m


func ids() -> Array[String]:
	var out: Array[String] = []
	for s in segments:
		if not out.has(s.id):
			out.append(s.id)
	return out


func any_water() -> bool:
	for s in segments:
		if s.water:
			return true
	return false


func _index(z: float) -> int:
	var lo := 0
	var hi := segments.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if z < float(segments[mid].to):
			hi = mid
		else:
			lo = mid + 1
	return lo


func segment_at(z: float) -> Dictionary:
	return segments[_index(z)]


## {a, b, t}: the segment at z and the neighbour it is blending with; t is
## b's share, rising to 0.5 at the boundary (past it, a and b swap).
func at(z: float) -> Dictionary:
	var i := _index(z)
	var a: Dictionary = segments[i]
	var half := BLEND * 0.5
	if i + 1 < segments.size() and z > float(a.to) - half:
		return {"a": a, "b": segments[i + 1], "t": smoothstep(-half, half, z - float(a.to))}
	if i > 0 and z < float(a.from) + half:
		return {"a": a, "b": segments[i - 1], "t": 1.0 - smoothstep(-half, half, z - float(a.from))}
	return {"a": a, "b": a, "t": 0.0}


## The segment a plant at (x, z) belongs to: across a blend, a stable random
## share goes to each side, so woods thin out into fields rather than ending.
func owner(x: float, z: float) -> Dictionary:
	var w := at(z)
	if w.t <= 0.0:
		return w.a
	var h := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
	return w.b if h < float(w.t) else w.a


## A blended number from the biomes' own tables (hills, relief…).
func param(z: float, key: String, fallback: float) -> float:
	var w := at(z)
	var va := float(RealFlora.BIOMES.get(w.a.id, {}).get(key, fallback))
	if w.t <= 0.0:
		return va
	var vb := float(RealFlora.BIOMES.get(w.b.id, {}).get(key, fallback))
	return lerpf(va, vb, float(w.t))


## 0..1: how much river and creek this stretch has (fading across a blend).
func water_at(z: float) -> float:
	var w := at(z)
	var wa := 1.0 if w.a.water else 0.0
	var wb := 1.0 if w.b.water else 0.0
	return lerpf(wa, wb, float(w.t))


## 0..1: how desert-like z is (its ridged ranges).
func share_of(z: float, id: String) -> float:
	var w := at(z)
	var sa := 1.0 if w.a.id == id else 0.0
	var sb := 1.0 if w.b.id == id else 0.0
	return lerpf(sa, sb, float(w.t))
