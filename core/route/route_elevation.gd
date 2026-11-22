class_name RouteElevation
extends Node
## Downloads the real ground around a route once, at import (R42): zoom-14
## elevation tiles within NEAR_REACH of the route, zoom-10 tiles out to
## FAR_REACH for the horizon. Public AWS Terrain Tiles (no key); cached under
## the route's folder, resumable, and marked done when complete.

signal progress(fraction: float)
signal done(ok: bool, message: String)

const URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const NEAR_REACH := 1200.0
const FAR_REACH := 8000.0

var busy := false
var status := ""
var _http: HTTPRequest
var _path := ""
var _todo: Array[Vector3i] = []      # (zoom, x, y)
var _total := 0
var _fails := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.request_completed.connect(_on_completed)
	add_child(_http)


static func dem_dir(gpx_path: String) -> String:
	return gpx_path.get_basename() + ".terrain"


static func has_dem(gpx_path: String) -> bool:
	return FileAccess.file_exists(dem_dir(gpx_path).path_join("done.txt"))


## Every tile the route needs: Vector3i(zoom, x, y).
static func tiles_for(route: Route) -> Array[Vector3i]:
	var seen := {}
	var out: Array[Vector3i] = []
	var d := 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	while true:
		var ll := route.latlon_at(d)
		lo = Vector2(minf(lo.x, ll.x), minf(lo.y, ll.y))
		hi = Vector2(maxf(hi.x, ll.x), maxf(hi.y, ll.y))
		var dlat := NEAR_REACH / Geo.M_PER_DEG_LAT
		var dlon := NEAR_REACH / (Geo.M_PER_DEG_LON * cos(deg_to_rad(ll.x)))
		_add_range(out, seen, RouteDem.NEAR_ZOOM, Vector2(ll.x - dlat, ll.y - dlon), Vector2(ll.x + dlat, ll.y + dlon))
		if d >= route.length:
			break
		d = minf(d + 300.0, route.length)
	var flat := FAR_REACH / Geo.M_PER_DEG_LAT
	var flon := FAR_REACH / (Geo.M_PER_DEG_LON * cos(deg_to_rad((lo.x + hi.x) * 0.5)))
	_add_range(out, seen, RouteDem.FAR_ZOOM, lo - Vector2(flat, flon), hi + Vector2(flat, flon))
	return out


static func _add_range(out: Array[Vector3i], seen: Dictionary, zoom: int, sw: Vector2, ne: Vector2) -> void:
	var a := Geo.tile_xy(Vector2(ne.x, sw.y), zoom)     # north-west corner: smallest x and y
	var b := Geo.tile_xy(Vector2(sw.x, ne.y), zoom)
	for tx in range(int(a.x), int(b.x) + 1):
		for ty in range(int(a.y), int(b.y) + 1):
			var key := Vector3i(zoom, tx, ty)
			if not seen.has(key):
				seen[key] = true
				out.append(key)


func fetch(route: Route, gpx_path: String) -> void:
	if busy:
		return
	busy = true
	_path = gpx_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dem_dir(gpx_path)))
	_todo.clear()
	for t in tiles_for(route):
		if not FileAccess.file_exists(_file(t)):
			_todo.append(t)         # resume: tiles already saved are kept
	_total = _todo.size()
	_fails = 0
	print("[route terrain] %d tiles to fetch for %s" % [_total, gpx_path.get_file()])
	_next()


func _file(t: Vector3i) -> String:
	return dem_dir(_path).path_join("%d_%d_%d.png" % [t.x, t.y, t.z])


func _next() -> void:
	if _todo.is_empty():
		var f := FileAccess.open(dem_dir(_path).path_join("done.txt"), FileAccess.WRITE)
		if f:
			f.store_string(Time.get_datetime_string_from_system(true))
		_finish(true, "")
		return
	var t := _todo[0]
	status = "Fetching the real ground… %d%%" % int(100.0 * (_total - _todo.size()) / maxf(_total, 1.0))
	progress.emit(float(_total - _todo.size()) / maxf(_total, 1.0))
	if _http.request(URL % [t.x, t.y, t.z], ["User-Agent: Groove/%s (indoor cycling app)" % ProjectSettings.get_setting("application/config/version", "dev")]) != OK:
		_retry()


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 404:
		_todo.pop_front()           # open sea / no data: that tile is simply missing
		_next()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_retry()
		return
	var f := FileAccess.open(_file(_todo[0]), FileAccess.WRITE)
	if f:
		f.store_buffer(body)
		f.close()
	_todo.pop_front()
	_fails = 0
	_next()


func _retry() -> void:
	_fails += 1
	if _fails > 5:
		_finish(false, "the elevation server is not answering")
		return
	await get_tree().create_timer(2.0 * _fails).timeout
	_next()


func _finish(ok: bool, message: String) -> void:
	busy = false
	status = "" if ok else "Real ground not fetched: " + message
	print("[route terrain] done %s: %s" % [_path.get_file(), "ok" if ok else message])
	progress.emit(1.0)
	done.emit(ok, message)
