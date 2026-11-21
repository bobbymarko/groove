class_name RouteProfile
extends Control
## A route's height profile: the climb as a filled silhouette over a band
## coloured by its scenery (woods dark green, fields pale, desert tan, snow
## white, a blue tick where water is near). With `progress` >= 0 it also marks
## where the rider is (the ride HUD's strip in a free ride).

var route: Route
var progress := -1.0              ## metres along the route; < 0 hides the marker
var band_height := 6.0
var fill := Color(0.55, 0.62, 0.75, 0.55)
var line := Color(0.85, 0.9, 1.0, 0.9)
var done_fill := Color(1.0, 0.72, 0.3, 0.7)

const BIOME_COLORS := {
	"summer": Color(0.32, 0.6, 0.26), "spring": Color(0.5, 0.75, 0.35), "autumn": Color(0.85, 0.5, 0.18),
	"winter": Color(0.9, 0.94, 1.0), "desert": Color(0.82, 0.62, 0.4), "birchwood": Color(0.7, 0.8, 0.45),
	"apocalypse": Color(0.45, 0.42, 0.38),
}


func set_route(r: Route) -> void:
	route = r
	queue_redraw()


func set_progress(metres: float) -> void:
	progress = metres
	queue_redraw()


## A biome segment's colour: darker for woods, paler for open country.
static func biome_color(b: Dictionary) -> Color:
	var c: Color = BIOME_COLORS.get(str(b.get("id", "")), Color(0.5, 0.5, 0.5))
	var trees := float(b.get("trees", 1.0))
	if trees > 1.0:
		return c.darkened(0.25)
	if trees < 0.3:
		return c.lerp(Color(0.9, 0.88, 0.7), 0.35)
	return c


func _draw() -> void:
	if route == null or route.length <= 0.0 or size.x < 4.0:
		return
	var w := size.x
	var h := size.y - band_height - 2.0
	var lo := INF
	var hi := -INF
	var n := int(clampf(w / 2.0, 16.0, 600.0))
	var eles := PackedFloat64Array()
	for i in n + 1:
		var e := route.ele_at(route.length * i / n)
		eles.append(e)
		lo = minf(lo, e)
		hi = maxf(hi, e)
	var span := maxf(hi - lo, 30.0)     # flat routes stay low instead of filling the box
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(Vector2(w * i / n, h - (eles[i] - lo) / span * (h - 4.0)))
	var poly := pts.duplicate()
	poly.append(Vector2(w, h))
	poly.append(Vector2(0.0, h))
	draw_colored_polygon(poly, fill)
	if progress >= 0.0:
		var px := w * clampf(progress / route.length, 0.0, 1.0)
		var done := PackedVector2Array()
		for p in pts:
			if p.x <= px:
				done.append(p)
		if done.size() >= 2:
			var top := done.duplicate()
			top.append(Vector2(done[-1].x, h))
			top.append(Vector2(0.0, h))
			draw_colored_polygon(top, done_fill)
	draw_polyline(pts, line, 1.5, true)
	# The scenery band under the profile.
	var y := size.y - band_height
	if route.biomes.is_empty():
		draw_rect(Rect2(0.0, y, w, band_height), Color(1, 1, 1, 0.12))
	for b in route.biomes:
		var x0 := w * float(b.from) / route.length
		var x1 := w * float(b.to) / route.length
		draw_rect(Rect2(x0, y, maxf(x1 - x0, 1.0), band_height), biome_color(b))
		if b.get("water", false):
			draw_rect(Rect2(x0, y - 2.0, maxf(x1 - x0, 1.0), 2.0), Color(0.35, 0.65, 1.0))
	if progress >= 0.0:
		var px := w * clampf(progress / route.length, 0.0, 1.0)
		draw_line(Vector2(px, 0.0), Vector2(px, size.y), Color(1, 1, 1, 0.95), 2.0)
