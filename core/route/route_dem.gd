class_name RouteDem
extends RefCounted
## Real ground heights around a route, from cached elevation tiles (AWS
## Terrain Tiles, "terrarium" PNGs: height = R*256 + G + B/256 - 32768 m).
## Zoom 14 (~7 m a pixel) near the route, zoom 10 (~110 m) out to the horizon.
## Read-only once loaded, so terrain workers may sample it freely.

const NEAR_ZOOM := 14
const FAR_ZOOM := 10

var geo: Geo
var _tiles: Dictionary = {}     ## Vector3i(zoom, x, y) -> PackedByteArray (256 * 256 RGB), decoded per sample


static func decode(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(256 * 256)
	var data := img.get_data()
	var stride := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
	for i in 256 * 256:
		var k := i * stride
		out[i] = data[k] * 256.0 + data[k + 1] + data[k + 2] / 256.0 - 32768.0
	return out


## All cached tiles for the route at gpx_path (none yet: every height is 0).
static func load_for(gpx_path: String, g: Geo) -> RouteDem:
	var dem := RouteDem.new()
	dem.geo = g
	var dir := RouteElevation.dem_dir(gpx_path)
	var d := DirAccess.open(dir)
	if d == null:
		return dem
	for f in d.get_files():
		if not f.ends_with(".png"):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(f)))
		if img == null or img.get_width() != 256:
			continue
		if img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGB8)
		var parts := f.get_basename().split("_")
		dem._tiles[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = img.get_data()
	return dem


func has_data() -> bool:
	return not _tiles.is_empty()


func tile_count() -> int:
	return _tiles.size()


## Ground height at local (x, z) metres: zoom 14 where cached, else zoom 10, else 0.
func height(x: float, z: float) -> float:
	var ll := geo.to_latlon(Vector2(x, z))
	var h: Variant = _sample(ll, NEAR_ZOOM)
	if h == null:
		h = _sample(ll, FAR_ZOOM)
	return 0.0 if h == null else float(h)


func _sample(ll: Vector2, zoom: int) -> Variant:
	var t := Geo.tile_xy(ll, zoom) * 256.0 - Vector2(0.5, 0.5)    # pixel centres
	var px := floorf(t.x)
	var py := floorf(t.y)
	var fx := t.x - px
	var fy := t.y - py
	var h00: Variant = _px(zoom, int(px), int(py))
	if h00 == null:
		return null
	var h10: Variant = _px(zoom, int(px) + 1, int(py))
	var h01: Variant = _px(zoom, int(px), int(py) + 1)
	var h11: Variant = _px(zoom, int(px) + 1, int(py) + 1)
	if h10 == null: h10 = h00
	if h01 == null: h01 = h00
	if h11 == null: h11 = h10
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


func _px(zoom: int, gx: int, gy: int) -> Variant:
	var tile: Variant = _tiles.get(Vector3i(zoom, gx >> 8, gy >> 8))
	if tile == null:
		return null
	var b := tile as PackedByteArray
	var k := ((gy & 255) * 256 + (gx & 255)) * 3
	return b[k] * 256.0 + b[k + 1] + b[k + 2] / 256.0 - 32768.0
