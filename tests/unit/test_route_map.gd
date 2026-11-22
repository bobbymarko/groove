extends TestCase
## True-map route rides (R42): the local frame, elevation tiles and the trail
## along the route's real shape.

var route: Route


func setup() -> void:
	route = GpxParser.parse_file("res://tests/fixtures/sample.gpx")   # 2.2 km due north at 7° E


func test_frame_round_trip_and_north_is_minus_z() -> void:
	var g := Geo.for_route(route)
	var p := g.to_local(Vector2(45.015, 7.001))
	var back := g.to_latlon(p)
	assert_near(back.x, 45.015, 1e-5)              # Vector2 is 32-bit: ~0.4 m
	assert_near(back.y, 7.001, 1e-5)
	assert_true(g.to_local(Vector2(45.02, 7.0)).y < g.to_local(Vector2(45.0, 7.0)).y)
	assert_near(g.to_local(Vector2(45.0, 7.001)).x - g.to_local(Vector2(45.0, 7.0)).x, 78.7, 0.5)   # 0.001° of longitude at 45°


func test_tile_maths_round_trip() -> void:
	var t := Geo.tile_xy(Vector2(44.836, -93.154), 14)
	assert_eq(int(t.x), 3952)
	var ll := Geo.tile_latlon(t, 14)
	assert_near(ll.x, 44.836, 1e-5)
	assert_near(ll.y, -93.154, 1e-5)


func test_dem_decodes_terrarium_heights() -> void:
	var g := Geo.for_route(route)
	var dem := RouteDem.new()
	dem.geo = g
	var t := Geo.tile_xy(Vector2(45.01, 7.0), RouteDem.NEAR_ZOOM)
	var bytes := PackedByteArray()
	bytes.resize(256 * 256 * 3)
	for i in 256 * 256:                       # 300.5 m: (128*256 + 300) + 128/256 - 32768
		bytes[i * 3] = 129
		bytes[i * 3 + 1] = 44
		bytes[i * 3 + 2] = 128
	dem._tiles[Vector3i(RouteDem.NEAR_ZOOM, int(t.x), int(t.y))] = bytes
	var p := g.to_local(Vector2(45.01, 7.0))
	assert_near(dem.height(p.x, p.y), 300.5, 0.01)


func test_route_trail_follows_the_route() -> void:
	var g := Geo.for_route(route)
	var t := RouteTrail.new(route, g)
	var a := t.position_at(t.start)
	var b := t.position_at(t.start + 1000.0)
	var want := g.to_local(route.latlon_at(1000.0))
	assert_near(b.x, want.x, 0.5)
	assert_near(b.z, want.y, 0.5)
	assert_true(b.z < a.z)                    # riding north
	assert_near(t.heading_at(t.start + 500.0).z, -1.0, 0.01)
	assert_near(t.h_at(t.start + 2000.0), 150.0, 0.5)
	var n := t.nearest(b.x + 6.0, b.z, 20.0)
	assert_near(n.x, t.start + 1000.0, 0.5)
	assert_near(absf(n.y), 6.0, 0.05)
	assert_eq(t.nearest(b.x + 60.0, b.z, 20.0).z, 0.0)


func test_a_point_to_point_route_turns_back_after_its_end() -> void:
	var t := RouteTrail.new(route, Geo.for_route(route))
	assert_false(t.is_loop)
	var L := route.length
	var before := t.position_at(t.start + L - 100.0)
	var after := t.position_at(t.start + L + 100.0)
	assert_near(before.distance_to(after), 0.0, 0.5)
	assert_true(t.heading_at(t.start + L + 100.0).z > 0.9)          # heading south again
	assert_true(t.grade_at(t.start + 300.0) > 2.0)
	assert_true(t.grade_at(t.start + 2.0 * L - 300.0) < -2.0)       # the climb is a descent on the way back
