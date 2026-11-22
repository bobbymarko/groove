extends TestCase
## The cover grid (R42 stage 2): OpenStreetMap shapes painted into 20 m squares
## around a route, water levels from the ground, and the trail bridging rivers.

var route: Route


func setup() -> void:
	route = GpxParser.parse_file("res://tests/fixtures/sample.gpx")   # 2.2 km due north at 7° E


func _square(x0: float, z0: float, s: float) -> PackedVector2Array:
	var a := Vector2(x0, z0)
	var b := Vector2(x0 + s, z0)
	var c := Vector2(x0 + s, z0 + s)
	var d := Vector2(x0, z0 + s)
	return PackedVector2Array([a, b, b, c, c, d, d, a])


func test_areas_fill_their_squares_and_holes_stay_out() -> void:
	var g := CoverGrid.new()
	var everywhere := Rect2(-5000, -5000, 10000, 10000)
	var wood := _square(-200.0, -200.0, 400.0)
	wood.append_array(_square(-50.0, -50.0, 100.0))          # a clearing (inner ring)
	g.fill_polygon(wood, CoverGrid.FOREST_BROAD, everywhere)
	assert_eq(g.kind_at(-150.0, -150.0), CoverGrid.FOREST_BROAD)
	assert_eq(g.kind_at(0.0, 0.0), CoverGrid.NONE)            # in the clearing
	assert_eq(g.kind_at(250.0, 0.0), CoverGrid.NONE)
	# A lake inside the wood wins; fields under the wood lose.
	g.fill_polygon(_square(100.0, 100.0, 60.0), CoverGrid.LAKE, everywhere)
	g.fill_polygon(_square(-300.0, -300.0, 600.0), CoverGrid.OPEN, everywhere)
	assert_eq(g.kind_at(130.0, 130.0), CoverGrid.LAKE)
	assert_eq(g.kind_at(-150.0, -150.0), CoverGrid.FOREST_BROAD)
	assert_eq(g.kind_at(250.0, 250.0), CoverGrid.OPEN)
	# Painting stops at the clip box.
	var h := CoverGrid.new()
	h.fill_polygon(_square(0.0, 0.0, 400.0), CoverGrid.OPEN, Rect2(0, 0, 200, 400))
	assert_eq(h.kind_at(100.0, 100.0), CoverGrid.OPEN)
	assert_eq(h.kind_at(300.0, 100.0), CoverGrid.NONE)


func test_a_river_line_is_a_band_of_water() -> void:
	var g := CoverGrid.new()
	g.draw_line(PackedVector2Array([Vector2(-500, 0), Vector2(500, 0)]), 40.0, CoverGrid.RIVER, Rect2(-1000, -1000, 2000, 2000))
	assert_eq(g.kind_at(0.0, 5.0), CoverGrid.RIVER)
	assert_eq(g.kind_at(0.0, -15.0), CoverGrid.RIVER)
	assert_eq(g.kind_at(0.0, 45.0), CoverGrid.NONE)
	assert_near(g.water_at(0.0, 10.0), 1.0, 0.01)
	assert_true(g.water_at(0.0, 25.0) < 0.5)
	assert_true(g.water_at(0.0, 25.0) > 0.0)                  # the shore blends


func test_saves_and_loads_including_west_and_north_of_the_centre() -> void:
	var g := CoverGrid.new()
	g.fill_polygon(_square(-3000.0, -3000.0, 200.0), CoverGrid.SCRUB, Rect2(-5000, -5000, 10000, 10000))
	g.fill_polygon(_square(2000.0, 2000.0, 200.0), CoverGrid.LAKE, Rect2(-5000, -5000, 10000, 10000))
	var path := "user://test_cover_grid.cover"
	assert_true(g.save(path))
	var back := CoverGrid.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(back.block_count(), g.block_count())
	assert_eq(back.kind_at(-2900.0, -2900.0), CoverGrid.SCRUB)
	assert_eq(back.kind_at(2100.0, 2100.0), CoverGrid.LAKE)
	assert_true(CoverGrid.load_from("user://no_such.cover").is_empty())


func test_a_lake_lies_flat_at_its_lowest_ground_and_a_river_follows_its_valley() -> void:
	var g := CoverGrid.new()
	var all := Rect2(-5000, -5000, 10000, 10000)
	g.fill_polygon(_square(0.0, 0.0, 200.0), CoverGrid.LAKE, all)
	g.draw_line(PackedVector2Array([Vector2(1000, -1000), Vector2(1000, 1000)]), 20.0, CoverGrid.RIVER, all)
	g.compute_levels(func(x: float, z: float) -> float: return 100.0 + x * 0.01 + z * 0.02)   # tilted ground
	assert_near(g.level_at(30.0, 30.0), 100.0 + 0.1 + 0.2, 0.01)     # the lowest cell centre
	assert_near(g.level_at(170.0, 170.0), g.level_at(30.0, 30.0), 0.001)
	var up := g.level_at(1005.0, 500.0)
	var down := g.level_at(1005.0, -500.0)
	assert_true(up > down + 15.0)                              # 1 km of 2 % valley
	assert_true(is_nan(g.level_at(500.0, 500.0)))


func test_a_lookup_answer_paints_the_wood_and_the_lake_by_the_route() -> void:
	var elements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/overpass_sample.json")).elements
	var geo := Geo.for_route(route)
	var g := CoverGrid.new()
	var st := RouteLandCover.stretches_for(route)
	RouteLandCover.rasterize(g, elements, geo, RouteLandCover.local_box(geo, st[0].bbox))
	var start := geo.to_local(route.latlon_at(100.0))
	assert_eq(g.kind_at(start.x, start.y), CoverGrid.FOREST_CONIFER)
	var field := geo.to_local(route.latlon_at(1500.0))
	assert_eq(g.kind_at(field.x, field.y), CoverGrid.OPEN)
	var lake := geo.to_local(Vector2(45.014, 7.0045))
	assert_eq(g.kind_at(lake.x, lake.y), CoverGrid.LAKE)


func test_the_trail_bridges_a_river_clear_of_the_water() -> void:
	var geo := Geo.for_route(route)
	var g := CoverGrid.new()
	var mid := geo.to_local(route.latlon_at(1100.0))
	g.draw_line(PackedVector2Array([mid + Vector2(-800, 0), mid + Vector2(800, 0)]), 30.0, CoverGrid.RIVER, Rect2(mid - Vector2(2000, 2000), Vector2(4000, 4000)))
	var dem := RouteDem.new()
	dem.geo = geo
	var t0 := Geo.tile_xy(Vector2(44.99, 6.99), RouteDem.NEAR_ZOOM)
	var t1 := Geo.tile_xy(Vector2(45.03, 7.01), RouteDem.NEAR_ZOOM)
	var flat := PackedByteArray()                 # 200 m everywhere
	flat.resize(256 * 256 * 3)
	for i in 256 * 256:
		flat[i * 3] = 128
		flat[i * 3 + 1] = 200
	for ty in range(int(t1.y), int(t0.y) + 1):
		for tx in range(int(t0.x), int(t1.x) + 1):
			dem._tiles[Vector3i(RouteDem.NEAR_ZOOM, tx, ty)] = flat
	g.compute_levels(dem.height)
	var t := RouteTrail.new(route, geo, dem, g)
	assert_eq(t.bridges.size(), 1, str(t.bridges))
	var b: Dictionary = t.bridges[0]
	assert_true(float(b.from) < 1085.0 and float(b.to) > 1115.0, str(b))
	var deck := t.h_at(t.start + 1100.0)
	assert_true(deck >= float(b.level) + 1.0, "deck %.2f over water %.2f" % [deck, float(b.level)])
	assert_true(t.bridge_depth(t.start + 1100.0) > 10.0)
	assert_eq(t.bridge_depth(t.start + 600.0), 0.0)
	var terrain := MapTerrain.new(t, dem, g)
	var p := t.position_at(t.start + 1100.0)
	assert_near(terrain.surface(p.x, p.z), deck, 0.01)            # riding on the deck
	assert_true(terrain.height(p.x, p.z) < float(b.level) - 0.5)  # the river bed below it
	terrain.free()
