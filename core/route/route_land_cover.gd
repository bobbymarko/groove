class_name RouteLandCover
extends Node
## Looks up what the land is like along a route, once, from OpenStreetMap
## (Overpass API): woods, fields, scrub, bare rock, glaciers, lakes and rivers.
## The route is split into ~5 km stretches, one query each (clipped to the
## stretch's box), then sampled every 100 m: the land under the route and 40 m
## either side, and any lake or river within 250 m. The result is land cover
## only ("cover" segments); the season and climate turn it into scenery at ride
## time (biomes_from_cover), so a route looks right in any month.
## Map data © OpenStreetMap contributors (ODbL).

signal progress(fraction: float)
signal done(ok: bool, message: String)

## Public Overpass servers, tried in turn: they are free, shared and often
## queueing, so a lookup is patient (backoff up to MAX_ATTEMPTS per stretch).
const ENDPOINTS := ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter",
	"https://overpass.kumi.systems/api/interpreter"]
const MAX_ATTEMPTS := 6
const STRETCH := 10000.0
const SAMPLE := 100.0
const MARGIN := 400.0          ## metres added around each stretch's box
const PROBE := 40.0            ## metres either side of the route
const WATER_NEAR := 250.0
const MIN_RUN := 400.0
const MIN_LAKE := 30000.0      ## m²: smaller ponds (stormwater, farm ponds) do not count as water to ride beside         ## shorter land-cover runs merge into a neighbour

const NATURAL := "wood|scrub|heath|grassland|bare_rock|scree|sand|glacier|water|wetland|beach"
## Residential areas are left out: suburbs have hundreds, they only ever mean
## "open" here, and they made the queries heavy and slow.
const LANDUSE := "forest|meadow|farmland|grass|orchard|vineyard"

var busy := false
var status := ""
var _http: HTTPRequest
var _route: Route
var _path := ""
var _stretches: Array = []     # [{from, to, bbox: Rect2 (x lon, y lat)}]
var _next := 0
var _samples: Array[Dictionary] = []   # land cover so far, every SAMPLE metres
var _attempts := 0
var _endpoint := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 300.0      # busy public servers can queue a request for minutes
	_http.request_completed.connect(_on_completed)
	add_child(_http)


## Start a lookup for the route stored at gpx_path. Emits done(ok, message);
## on failure the route still gets a climate-only estimate.
func look_up(route: Route, gpx_path: String) -> void:
	if busy:
		return
	busy = true
	_route = route
	_path = gpx_path
	# Resume where an earlier lookup of this route got to (app closed, servers gave up).
	_samples.clear()
	var start := 0.0
	var part := partial_path(gpx_path)
	if FileAccess.file_exists(part):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(part))
		if saved is Dictionary and saved.has("samples"):
			for x in saved.samples:
				_samples.append({"d": float(x.d), "kind": str(x.kind), "water": bool(x.water)})
			start = float(saved.get("done_to", 0.0))
			print("[route lookup] resuming %s from %.1f km" % [gpx_path.get_file(), start / 1000.0])
	_stretches = stretches_for(route, start)
	_next = 0
	_attempts = 0
	_request_next()


func _request_next() -> void:
	if _next >= _stretches.size():
		_finish(true, "")
		return
	status = "Looking up the scenery… %d%%" % int(100.0 * _next / _stretches.size())
	print("[route lookup] stretch %d/%d of %s" % [_next + 1, _stretches.size(), _path.get_file()])
	progress.emit(float(_next) / _stretches.size())
	var body := "data=" + query_for(_stretches[_next].bbox).uri_encode()
	var headers := ["Content-Type: application/x-www-form-urlencoded",
		"User-Agent: Groove/%s (indoor cycling app)" % ProjectSettings.get_setting("application/config/version", "dev")]
	if _http.request(ENDPOINTS[_endpoint], headers, HTTPClient.METHOD_POST, body) != OK:
		_retry("could not reach OpenStreetMap")


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_retry("timed out" if result == HTTPRequest.RESULT_TIMEOUT else "no connection (%d)" % result)
		return
	if code < 200 or code >= 300:
		_retry("server answered %d" % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	var problem := answer_problem(data)
	if problem != "":
		_retry(problem)
		return
	var cur: Dictionary = _stretches[_next]
	_samples.append_array(classify(_route, data.elements, float(cur.from), float(cur.to)))
	var f := FileAccess.open(partial_path(_path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"done_to": float(cur.to), "samples": _samples}))
		f.close()
	_next += 1
	_attempts = 0
	await get_tree().create_timer(1.0).timeout      # be gentle with a free public service
	_request_next()


## Busy or failed: wait longer each time and try the next server.
func _retry(why: String) -> void:
	_attempts += 1
	if _attempts >= MAX_ATTEMPTS:
		_finish(false, "OpenStreetMap is not answering (%s)" % why)
		return
	_endpoint = (_endpoint + 1) % ENDPOINTS.size()
	# A stretch that keeps failing is probably too heavy for a busy server
	# (lots of mapped parkland): split it in half and try the halves.
	var cur: Dictionary = _stretches[_next]
	if _attempts >= 2 and float(cur.to) - float(cur.from) > 2000.0:
		var mid := (float(cur.from) + float(cur.to)) * 0.5
		_stretches[_next] = stretch(_route, float(cur.from), mid)
		_stretches.insert(_next + 1, stretch(_route, mid, float(cur.to)))
		_attempts = 0
		print("[route lookup] splitting a slow stretch in two")
	var wait := minf(8.0 * pow(2.0, maxi(_attempts, 1) - 1), 90.0)
	status = "OpenStreetMap is busy, trying again in %d s…" % int(wait)
	print("[route lookup] %s; retry %d in %d s" % [why, _attempts, int(wait)])
	progress.emit(float(_next) / _stretches.size())
	await get_tree().create_timer(wait).timeout
	_request_next()


## Why an answer cannot be used ("" if it can). Overpass reports a query that
## ran out of time as 200 OK with a remark and no elements.
static func answer_problem(data: Variant) -> String:
	if not (data is Dictionary and data.has("elements")):
		return "unexpected answer"
	var remark := str(data.get("remark", ""))
	if remark.contains("error") or remark.contains("timed out") or remark.contains("out of memory"):
		return "the server ran out of time"
	return ""


func _finish(ok: bool, message: String) -> void:
	var cover: Array[Dictionary] = []
	if ok:
		cover = cover_from_samples(_samples, _route.length)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(partial_path(_path)))
	else:
		cover = [{"from": 0.0, "to": _route.length, "kind": "unknown", "water": false}]
	RouteLibrary.save_cover(_path, cover, not ok)
	busy = false
	status = "" if ok else "Scenery estimated: " + message
	print("[route lookup] done %s: %s" % [_path.get_file(), "ok" if ok else message])
	progress.emit(1.0)
	done.emit(ok, message)


# --- pure functions (tested without network) ------------------------------------

## Where a lookup in progress keeps the stretches it has done.
static func partial_path(gpx_path: String) -> String:
	return gpx_path.get_basename() + ".partial.json"


## The route in ~10 km stretches, each with its lat/lon box plus MARGIN.
static func stretches_for(route: Route, start := 0.0) -> Array:
	var out := []
	var from := start
	while from < route.length - 1.0:
		var to := minf(from + STRETCH, route.length)
		out.append(stretch(route, from, to))
		from = to
	return out


## One stretch of route: its lat/lon box (x lon, y lat) plus MARGIN.
static func stretch(route: Route, from: float, to: float) -> Dictionary:
	var box := Rect2(Vector2(route.latlon_at(from).y, route.latlon_at(from).x), Vector2.ZERO)
	var d := from
	while d <= to:
		var p := route.latlon_at(d)
		box = box.expand(Vector2(p.y, p.x))
		d += 50.0
	var p_end := route.latlon_at(to)
	box = box.expand(Vector2(p_end.y, p_end.x))
	var mid_lat := box.get_center().y
	var dlat := MARGIN / 111320.0
	var dlon := MARGIN / (111320.0 * maxf(cos(deg_to_rad(mid_lat)), 0.05))
	box = box.grow_individual(dlon, dlat, dlon, dlat)
	return {"from": from, "to": to, "bbox": box}


static func query_for(box: Rect2) -> String:
	var b := "(%.6f,%.6f,%.6f,%.6f)" % [box.position.y, box.position.x, box.end.y, box.end.x]
	return ("[out:json][timeout:180];(" +
		"wr[\"natural\"~\"^(%s)$\"]%s;" % [NATURAL, b] +
		"wr[\"landuse\"~\"^(%s)$\"]%s;" % [LANDUSE, b] +
		"way[\"waterway\"=\"river\"]%s;);out geom%s;" % [b, b])


## Land cover every SAMPLE metres between from and to: [{d, kind, water}].
static func classify(route: Route, elements: Array, from: float, to: float) -> Array[Dictionary]:
	var origin := route.latlon_at((from + to) * 0.5)
	var shapes := _shapes(elements, origin)
	var out: Array[Dictionary] = []
	var d := from + SAMPLE * 0.5
	while d < to:
		var p := _local(route.latlon_at(d), origin)
		var ahead := _local(route.latlon_at(minf(d + 10.0, route.length)), origin)
		var behind := _local(route.latlon_at(maxf(d - 10.0, 0.0)), origin)
		var dir := (ahead - behind).normalized()
		var side := Vector2(-dir.y, dir.x)
		var votes := {}
		for probe in [p, p + side * PROBE, p - side * PROBE]:
			var k := _kind_at(shapes, probe)
			votes[k] = int(votes.get(k, 0)) + 1
		var kind := "unknown"
		var best := 0
		for k in votes:
			if votes[k] > best or (votes[k] == best and _rank(k) > _rank(kind)):
				best = votes[k]
				kind = k
		if kind == "unknown":
			# The road itself is rarely mapped: take the land around it.
			var around := {}
			for a in 8:
				var k := _kind_at(shapes, p + Vector2.from_angle(a * TAU / 8.0) * 150.0)
				if k != "unknown":
					around[k] = int(around.get(k, 0)) + 1
			var most := 1                 # at least two of the eight points agree
			for k in around:
				if around[k] > most:
					most = around[k]
					kind = k
		out.append({"d": d, "kind": kind, "water": _water_near(shapes, p)})
		d += SAMPLE
	return out


## Merge samples into runs of one land cover; runs under MIN_RUN join the
## longer neighbour, so the scenery does not flicker. [{from, to, kind, water}]
static func cover_from_samples(samples: Array[Dictionary], length: float) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for s in samples:
		var a := maxf(float(s.d) - SAMPLE * 0.5, 0.0)
		var b := minf(float(s.d) + SAMPLE * 0.5, length)
		if not runs.is_empty() and runs[-1].kind == s.kind:
			runs[-1].to = b
			runs[-1].wet += (b - a) * (1.0 if s.water else 0.0)
		else:
			runs.append({"from": a, "to": b, "kind": s.kind, "wet": (b - a) * (1.0 if s.water else 0.0)})
	var merged := true
	while merged and runs.size() > 1:
		merged = false
		for i in runs.size():
			var r: Dictionary = runs[i]
			if r.to - r.from >= MIN_RUN:
				continue
			var j := i - 1 if i > 0 else i + 1
			if i > 0 and i < runs.size() - 1:
				var left: Dictionary = runs[i - 1]
				var right: Dictionary = runs[i + 1]
				j = i - 1 if left.to - left.from >= right.to - right.from else i + 1
			var into: Dictionary = runs[j]
			into.from = minf(into.from, r.from)
			into.to = maxf(into.to, r.to)
			into.wet += r.wet
			runs.remove_at(i)
			merged = true
			break
		# Neighbours that now share a kind become one run.
		var k := 1
		while k < runs.size():
			if runs[k].kind == runs[k - 1].kind:
				runs[k - 1].to = runs[k].to
				runs[k - 1].wet += runs[k].wet
				runs.remove_at(k)
			else:
				k += 1
	var out: Array[Dictionary] = []
	for r in runs:
		out.append({"from": r.from, "to": r.to, "kind": r.kind, "water": r.wet > 0.3 * (r.to - r.from)})
	if not out.is_empty():
		out[0].from = 0.0
		out[-1].to = length
	return out


## Scenery for a season: land cover + latitude + elevation + month → RealFlora
## biome ids with a tree-density multiplier. [{from, to, id, trees, water, mix}]
static func biomes_from_cover(route: Route, cover: Array, month: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cover:
		var mid := (float(c.from) + float(c.to)) * 0.5
		var ll := route.latlon_at(mid)
		var pick := climate_biome(str(c.kind), ll.x, route.ele_at(mid), month)
		var seg := {"from": float(c.from), "to": float(c.to), "id": pick.id, "trees": pick.trees,
			"water": bool(c.get("water", false)), "mix": pick.mix}
		if not out.is_empty() and out[-1].id == seg.id and is_equal_approx(out[-1].trees, seg.trees) and out[-1].water == seg.water and out[-1].mix == seg.mix:
			out[-1].to = seg.to
		else:
			out.append(seg)
	return out


## Season by month and hemisphere ("summer" all year in the tropics).
static func season(lat: float, month: int) -> String:
	if absf(lat) < 23.0:
		return "summer"
	var m := month if lat >= 0.0 else ((month + 5) % 12) + 1
	if m == 12 or m <= 2:
		return "winter"
	if m <= 5:
		return "spring"
	if m <= 8:
		return "summer"
	return "autumn"


## One place's scenery: {id, trees, mix}. mix biases the tree kinds ("conifer",
## "broad" or "" for the biome's own mix).
static func climate_biome(kind: String, lat: float, ele: float, month: int) -> Dictionary:
	var alat := absf(lat)
	var sea := season(lat, month)
	var trees: float = {"forest_conifer": 1.6, "forest_broad": 1.6, "forest_mixed": 1.6, "open": 0.15,
		"scrub": 0.4, "barren": 0.05, "snow": 0.1, "unknown": 0.6}.get(kind, 0.6)
	var mix := "conifer" if kind == "forest_conifer" else ("broad" if kind == "forest_broad" else "")
	# Snow: glaciers, ground above the year-round snow line, or winter far enough north (or high).
	var snow_line := 5200.0 - maxf(alat - 20.0, 0.0) * 95.0
	var winter_snow := sea == "winter" and ele > 1500.0 - (alat - 35.0) * 60.0
	if kind == "snow" or ele > snow_line or winter_snow:
		return {"id": "winter", "trees": minf(trees, 1.2), "mix": "conifer"}
	if (kind == "scrub" or kind == "barren") and alat >= 15.0 and alat <= 40.0:
		return {"id": "desert", "trees": 1.0 if kind == "scrub" else 0.5, "mix": ""}
	var id: String = {"winter": "autumn", "spring": "spring", "summer": "summer", "autumn": "autumn"}[sea]
	if kind == "forest_broad" and alat > 55.0 and sea != "autumn":
		id = "birchwood"
	return {"id": id, "trees": trees, "mix": mix}


# --- geometry ---------------------------------------------------------------------

## Metres east/north of origin (equirectangular; fine over a 5 km stretch).
static func _local(ll: Vector2, origin: Vector2) -> Vector2:
	return Vector2((ll.y - origin.y) * 111320.0 * cos(deg_to_rad(origin.x)), (ll.x - origin.x) * 110540.0)


## Elements as edge lists in local metres: [{kind, area: bool, river: bool, edges: PackedVector2Array (pairs)}].
static func _shapes(elements: Array, origin: Vector2) -> Array:
	var out := []
	for e in elements:
		if not (e is Dictionary) or not e.has("tags"):
			continue
		var kind := _kind_for_tags(e.tags)
		var river := str(e.tags.get("waterway", "")) == "river"
		if kind == "" and not river:
			continue
		var edges := PackedVector2Array()
		if e.get("type") == "way" and e.has("geometry"):
			_add_edges(edges, e.geometry, origin, not river)
		elif e.get("type") == "relation" and e.has("members"):
			for m in e.members:
				if m is Dictionary and m.has("geometry"):
					_add_edges(edges, m.geometry, origin, false)
		if edges.is_empty():
			continue
		var bounds := Rect2(edges[0], Vector2.ZERO)
		for v in edges:
			bounds = bounds.expand(v)
		out.append({"kind": kind, "area": not river, "river": river, "edges": edges, "bounds": bounds,
			"water": kind == "water" and (e.get("type") == "relation" or _area(edges) >= MIN_LAKE)})
	return out


## Consecutive points as edges; clipped geometry (nulls for nodes outside the
## box) is bridged across the gap; a way's ring is closed if clipping opened it.
static func _add_edges(edges: PackedVector2Array, geometry: Array, origin: Vector2, close: bool) -> void:
	var pts := PackedVector2Array()
	for g in geometry:
		if g is Dictionary and g.has("lat"):
			pts.append(_local(Vector2(float(g.lat), float(g.lon)), origin))
	for i in range(1, pts.size()):
		edges.append(pts[i - 1])
		edges.append(pts[i])
	if close and pts.size() > 2 and pts[0].distance_to(pts[-1]) > 0.5:
		edges.append(pts[-1])
		edges.append(pts[0])


static func _kind_for_tags(tags: Dictionary) -> String:
	var n := str(tags.get("natural", ""))
	var l := str(tags.get("landuse", ""))
	if n == "glacier":
		return "snow"
	if n == "wetland":
		return "open"          # marsh: open ground, not a lake to ride beside
	if n == "water":
		return "water"
	if n == "wood" or l == "forest":
		var leaf := str(tags.get("leaf_type", ""))
		return "forest_conifer" if leaf == "needleleaved" else ("forest_broad" if leaf == "broadleaved" else "forest_mixed")
	if n == "scrub" or n == "heath":
		return "scrub"
	if n in ["bare_rock", "scree", "sand", "beach"]:
		return "barren"
	if n == "grassland" or l in ["meadow", "farmland", "grass", "orchard", "vineyard", "residential", "farmyard", "allotments"]:
		return "open"
	return ""


## Which land cover wins when shapes overlap (a wood inside farmland is a wood).
static func _rank(kind: String) -> int:
	return {"snow": 7, "forest_conifer": 6, "forest_broad": 6, "forest_mixed": 6, "water": 5, "scrub": 4, "barren": 3, "open": 2, "unknown": 0}.get(kind, 1)


static func _kind_at(shapes: Array, p: Vector2) -> String:
	var best := "unknown"
	for s in shapes:
		if not s.area or not (s.bounds as Rect2).grow(1.0).has_point(p):
			continue
		if _inside(s.edges, p) and _rank(s.kind) > _rank(best):
			best = s.kind
	return "open" if best == "water" else best      # the trail itself is never in the lake: a causeway


## Even-odd rule over all edges (a multipolygon's rings, holes included).
static func _inside(edges: PackedVector2Array, p: Vector2) -> bool:
	var inside := false
	for i in range(0, edges.size(), 2):
		var a := edges[i]
		var b := edges[i + 1]
		if (a.y > p.y) != (b.y > p.y):
			var x := a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if x > p.x:
				inside = not inside
	return inside


## Area of a closed outline given as edge pairs (shoelace), m².
static func _area(edges: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(0, edges.size(), 2):
		a += edges[i].x * edges[i + 1].y - edges[i + 1].x * edges[i].y
	return absf(a) * 0.5


static func _water_near(shapes: Array, p: Vector2) -> bool:
	for s in shapes:
		if not (s.water or s.river):
			continue
		if not (s.bounds as Rect2).grow(WATER_NEAR).has_point(p):
			continue
		if s.water and _inside(s.edges, p):
			return true
		for i in range(0, s.edges.size(), 2):
			if Geometry2D.get_closest_point_to_segment(p, s.edges[i], s.edges[i + 1]).distance_to(p) < WATER_NEAR:
				return true
	return false
