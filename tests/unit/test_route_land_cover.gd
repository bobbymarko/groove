extends TestCase
## Land cover along a route from an OpenStreetMap answer, and the climate
## that turns it into scenery (R41). No network: a saved Overpass answer.

var route: Route
var elements: Array


func setup() -> void:
	route = GpxParser.parse_file("res://tests/fixtures/sample.gpx")
	elements = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/overpass_sample.json")).elements


func test_stretches_cover_the_route_with_a_margin() -> void:
	var st := RouteLandCover.stretches_for(route)
	assert_eq(st.size(), 1)
	var box: Rect2 = st[0].bbox
	assert_true(box.position.y < 45.0 - 0.003 and box.end.y > 45.02 + 0.003, str(box))
	assert_true(box.has_point(Vector2(7.0, 45.01)))
	var q := RouteLandCover.query_for(box)
	assert_true(q.contains("[out:json]") and q.contains("leaf") == false and q.contains("waterway"))
	assert_true(q.contains("%.6f" % box.position.y))


func test_forest_then_fields_by_a_lake() -> void:
	var samples := RouteLandCover.classify(route, elements, 0.0, route.length)
	assert_eq(samples[0].kind, "forest_conifer")
	assert_eq(samples[12].kind, "open")
	var cover := RouteLandCover.cover_from_samples(samples, route.length)
	assert_eq(cover.size(), 2, str(cover))      # the 200 m scrub patch joined the field
	assert_eq(cover[0].kind, "forest_conifer")
	assert_near(float(cover[1].from), 900.0, 1.0)
	assert_false(cover[0].water)
	assert_true(cover[1].water)                 # the lake lies within 250 m of the route
	assert_near(float(cover[1].to), route.length)


func test_climate_turns_cover_into_scenery() -> void:
	assert_eq(RouteLandCover.climate_biome("forest_conifer", 45.0, 120.0, 7).id, "summer")
	assert_eq(RouteLandCover.climate_biome("forest_conifer", 45.0, 120.0, 7).mix, "conifer")
	assert_eq(RouteLandCover.climate_biome("scrub", 32.2, 750.0, 3).id, "desert")      # Tucson
	assert_eq(RouteLandCover.climate_biome("open", 46.5, 3300.0, 7).id, "winter")      # above the snow line
	assert_eq(RouteLandCover.climate_biome("open", 60.0, 80.0, 1).id, "winter")        # a Nordic January
	assert_eq(RouteLandCover.climate_biome("open", 45.0, 200.0, 1).id, "autumn")       # a mild lowland January
	assert_eq(RouteLandCover.climate_biome("forest_broad", 62.0, 100.0, 6).id, "birchwood")
	assert_true(RouteLandCover.climate_biome("open", 45.0, 100.0, 7).trees < 0.3)
	assert_eq(RouteLandCover.season(-40.0, 7), "winter")                               # southern hemisphere
	assert_eq(RouteLandCover.season(5.0, 1), "summer")                                 # tropics


func test_biomes_merge_neighbours_that_look_the_same() -> void:
	var cover := [{"from": 0.0, "to": 900.0, "kind": "open", "water": false},
		{"from": 900.0, "to": 1500.0, "kind": "unknown", "water": false},
		{"from": 1500.0, "to": 2224.0, "kind": "open", "water": false}]
	var b := RouteLandCover.biomes_from_cover(route, cover, 7)
	assert_eq(b.size(), 3)                      # unknown has more trees than open: kept apart
	var same := [{"from": 0.0, "to": 900.0, "kind": "open", "water": false}, {"from": 900.0, "to": 2224.0, "kind": "open", "water": false}]
	assert_eq(RouteLandCover.biomes_from_cover(route, same, 7).size(), 1)


func test_a_timed_out_answer_is_not_empty_land() -> void:
	assert_eq(RouteLandCover.answer_problem({"elements": []}), "")
	assert_true(RouteLandCover.answer_problem({"elements": [], "remark": "runtime error: Query timed out in \"query\" at line 1 after 61 seconds."}) != "")
	assert_true(RouteLandCover.answer_problem("<html>502</html>") != "")
