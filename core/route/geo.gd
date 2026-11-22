class_name Geo
extends RefCounted
## A flat metre frame centred on a route (x east, z south: north is -z, as
## Godot looks down -z), and Web Mercator tile maths for elevation tiles.
## Over a route's few tens of kilometres the flat frame is accurate to well
## under a metre per kilometre.

const M_PER_DEG_LAT := 110540.0
const M_PER_DEG_LON := 111320.0

var lat0 := 0.0
var lon0 := 0.0
var _kx := 1.0      ## metres per degree of longitude at lat0


func _init(origin_lat := 0.0, origin_lon := 0.0) -> void:
	lat0 = origin_lat
	lon0 = origin_lon
	_kx = M_PER_DEG_LON * cos(deg_to_rad(lat0))


## The frame for a route: centred on its bounding box.
static func for_route(r: Route) -> Geo:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in r.lats.size():
		lo = Vector2(minf(lo.x, r.lats[i]), minf(lo.y, r.lons[i]))
		hi = Vector2(maxf(hi.x, r.lats[i]), maxf(hi.y, r.lons[i]))
	return Geo.new((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5)


## Vector2(lat, lon) -> Vector2(x, z) metres.
func to_local(ll: Vector2) -> Vector2:
	return Vector2((ll.y - lon0) * _kx, -(ll.x - lat0) * M_PER_DEG_LAT)


## Vector2(x, z) metres -> Vector2(lat, lon).
func to_latlon(p: Vector2) -> Vector2:
	return Vector2(lat0 - p.y / M_PER_DEG_LAT, lon0 + p.x / _kx)


## Fractional tile coordinates (x, y) of a point at a zoom level.
static func tile_xy(ll: Vector2, zoom: int) -> Vector2:
	var n := float(1 << zoom)
	var lat_r := deg_to_rad(clampf(ll.x, -85.0, 85.0))
	return Vector2((ll.y + 180.0) / 360.0 * n, (1.0 - asinh(tan(lat_r)) / PI) * 0.5 * n)


## Vector2(lat, lon) of fractional tile coordinates.
static func tile_latlon(t: Vector2, zoom: int) -> Vector2:
	var n := float(1 << zoom)
	return Vector2(rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * t.y / n)))), t.x / n * 360.0 - 180.0)
