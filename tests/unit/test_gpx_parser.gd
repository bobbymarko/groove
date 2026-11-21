extends TestCase
## GPX import and the Route model (R41).

const FIXTURE := "res://tests/fixtures/sample.gpx"
var r: Route


func setup() -> void:
	r = GpxParser.parse_file(FIXTURE)


func test_reads_points_across_segments_and_name() -> void:
	assert_true(r != null, GpxParser.last_error)
	assert_eq(r.lats.size(), 21)
	assert_eq(r.name, "Sample Climb")
	assert_true(r.has_elevation)


func test_length_is_haversine() -> void:
	# 0.02° of latitude ≈ 2224 m.
	assert_near(r.length, 2223.9, 2.0)


func test_profile_climbs_then_flattens() -> void:
	assert_near(r.climb, 50.0, 3.0)
	assert_near(r.grade_at(500.0), 4.5, 0.4)      # 5 m per 111 m
	assert_near(r.grade_at(1800.0), 0.0, 0.2)
	assert_near(r.ele_at(0.0), 100.0, 4.0)        # smoothing barely moves the ends
	assert_near(r.ele_at(2000.0), 150.0, 0.5)


func test_latlon_interpolates() -> void:
	var p := r.latlon_at(r.length * 0.5)
	assert_near(p.x, 45.01, 0.0002)
	assert_near(p.y, 7.0, 0.00001)
	assert_near(r.latlon_at(-5.0).x, 45.0, 1e-6)
	assert_near(r.latlon_at(r.length + 50.0).x, 45.02, 1e-6)


func test_no_elevation_is_flat() -> void:
	var gpx := '<gpx><rte><rtept lat="10.0" lon="20.0"/><rtept lat="10.002" lon="20.0"/><rtept lat="10.004" lon="20.0"/></rte></gpx>'
	var flat := GpxParser.parse_bytes(gpx.to_utf8_buffer())
	assert_true(flat != null, GpxParser.last_error)
	assert_false(flat.has_elevation)
	assert_eq(flat.grade_at(200.0), 0.0)
	assert_eq(flat.lats.size(), 3)


func test_rejects_files_without_points() -> void:
	assert_true(GpxParser.parse_bytes("<gpx><trk></trk></gpx>".to_utf8_buffer()) == null)
	assert_true(GpxParser.last_error != "")
	assert_true(GpxParser.parse_bytes("not xml at all".to_utf8_buffer()) == null)


func test_biome_lookup_and_main_biome() -> void:
	r.biomes = [{"from": 0.0, "to": 600.0, "id": "summer", "trees": 1.0, "water": false},
		{"from": 600.0, "to": 2300.0, "id": "winter", "trees": 0.2, "water": true}]
	assert_eq(r.biome_at(100.0).id, "summer")
	assert_eq(r.biome_at(700.0).id, "winter")
	assert_eq(r.biome_at(9999.0).id, "winter")
	assert_eq(r.main_biome(), "winter")


func test_sidecar_round_trip() -> void:
	r.biomes = [{"from": 0.0, "to": 2300.0, "id": "autumn", "trees": 1.4, "water": true}]
	r.estimated = true
	var data: Dictionary = JSON.parse_string(JSON.stringify({"biomes": r.biomes, "estimated": true}))
	var r2 := GpxParser.parse_file(FIXTURE)
	RouteLibrary.apply_sidecar(r2, data)
	assert_eq(r2.biomes.size(), 1)
	assert_eq(r2.biomes[0].id, "autumn")
	assert_near(float(r2.biomes[0].trees), 1.4)
	assert_true(r2.estimated)
