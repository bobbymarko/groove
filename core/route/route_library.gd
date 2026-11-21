class_name RouteLibrary
extends RefCounted
## The user's imported routes: each GPX is copied into user://routes beside a
## sidecar (<name>.route.json) holding its looked-up land cover, so the lookup
## happens once. Deleting moves both into routes/deleted, never destroying them.

const DIR := "user://routes"
const DELETED_DIR := "user://routes/deleted"
const FILTER := "*.gpx ; GPX routes"

static var last_error := ""


static func supported(path: String) -> bool:
	return path.get_extension().to_lower() == "gpx"


## Copy a GPX into the library after checking it parses. Returns the library
## path, or "" with last_error set.
static func import(path: String) -> String:
	var r := GpxParser.parse_file(path)
	if r == null:
		last_error = GpxParser.last_error
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var dest := DIR.path_join(path.get_file())
	if FileAccess.file_exists(dest):
		dest = DIR.path_join("%s-%d.gpx" % [path.get_file().get_basename(), int(Time.get_unix_time_from_system())])
	if DirAccess.copy_absolute(path, ProjectSettings.globalize_path(dest)) != OK:
		last_error = "could not copy the file into the library"
		return ""
	return dest


static func list() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if supported(f):
			out.append(DIR.path_join(f))
	out.sort()
	return out


static func sidecar_path(gpx_path: String) -> String:
	return gpx_path.get_basename() + ".route.json"


## The route with its saved scenery (no scenery yet if never looked up).
static func load_route(gpx_path: String) -> Route:
	var r := GpxParser.parse_file(gpx_path)
	if r == null:
		last_error = GpxParser.last_error
		return null
	var side := sidecar_path(gpx_path)
	if FileAccess.file_exists(side):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(side))
		if data is Dictionary:
			apply_sidecar(r, data)
	return r


static func has_scenery(gpx_path: String) -> bool:
	return FileAccess.file_exists(sidecar_path(gpx_path))


## Turn saved land cover into scenery for the given month (today's by default).
static func apply_sidecar(r: Route, data: Dictionary, month: int = 0) -> void:
	if month <= 0:
		month = int(Time.get_date_dict_from_system().month)
	r.biomes = RouteLandCover.biomes_from_cover(r, data.get("cover", []), month)
	r.estimated = bool(data.get("estimated", false))


static func save_cover(gpx_path: String, cover: Array, estimated: bool) -> void:
	var data := {"version": 1, "looked_up": Time.get_datetime_string_from_system(true), "estimated": estimated, "cover": cover}
	var f := FileAccess.open(sidecar_path(gpx_path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


static func delete(gpx_path: String) -> bool:
	if not gpx_path.begins_with(DIR + "/") or gpx_path.begins_with(DELETED_DIR):
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DELETED_DIR))
	var stamp := int(Time.get_unix_time_from_system())
	for p in [gpx_path, sidecar_path(gpx_path), RouteLandCover.partial_path(gpx_path)]:
		if FileAccess.file_exists(p):
			var dest := DELETED_DIR.path_join("%d-%s" % [stamp, p.get_file()])
			DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(dest))
	return true
