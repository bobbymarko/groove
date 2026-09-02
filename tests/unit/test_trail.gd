extends TestCase


func test_default_profile_is_continuous_and_gentle() -> void:
	var t := Trail.new()
	var prev := t.h_at(0.0)
	for z in range(1, 400):
		var h := t.h_at(float(z))
		assert_true(absf(h - prev) < 0.12, "step at %d: %f" % [z, h - prev])   # < 12 % grade
		prev = h
	assert_true(absf(t.grade_at(200.0)) < 8.0)


func test_grade_provider_drives_height() -> void:
	var t := Trail.new()
	t.grade_provider = func(_z: float) -> float: return 8.0
	var h0 := t.h_at(50.0)
	var h1 := t.h_at(150.0)
	# 8 % over 100 m = 8 m, minus the smoothing ramp-in at the start.
	assert_true(h1 - h0 > 7.0 and h1 - h0 < 8.1, "rise %f" % (h1 - h0))
	assert_near(t.grade_at(120.0), 8.0, 0.2)


func test_grade_for_target_mapping() -> void:
	assert_true(Trail.grade_for_target(0.5) < 0.0)          # recovery descends
	assert_near(Trail.grade_for_target(0.75), 0.0)           # endurance is flat
	assert_true(Trail.grade_for_target(1.06) > 4.0)          # threshold climbs
	assert_eq(Trail.grade_for_target(2.0), 10.0)             # clamped
	assert_eq(Trail.grade_for_target(0.0), -6.0)


func test_height_cache_is_consistent() -> void:
	var t := Trail.new()
	var a := t.h_at(333.3)
	var b := t.h_at(333.3)
	assert_near(a, b)
	assert_near(t.position_at(10.0).z, 10.0)
	assert_near(t.heading_at(10.0).length(), 1.0)
