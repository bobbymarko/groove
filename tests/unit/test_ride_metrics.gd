extends TestCase


func _flat(power: int, n: int, hr := 0, cad := 0, kph := 0.0) -> Array:
	var out := []
	for i in n:
		out.append({"t": 1000 + i, "p": power, "h": hr, "c": cad, "v": kph})
	return out


func test_empty() -> void:
	var m := RideMetrics.compute([], 250)
	assert_eq(m.duration_s, 0)
	assert_eq(m.avg_power, 0)


func test_flat_ride_np_equals_avg() -> void:
	var m := RideMetrics.compute(_flat(200, 600, 140, 90, 30.0), 250)
	assert_eq(m.duration_s, 600)
	assert_eq(m.avg_power, 200)
	assert_eq(m.normalized_power, 200)
	assert_near(m.intensity_factor, 0.8)
	assert_near(m.tss, 600 * 200 * 0.8 / (250 * 3600.0) * 100.0, 0.01)   # 10.67
	assert_near(m.kj, 120.0)
	assert_eq(m.avg_heart_rate, 140)
	assert_eq(m.avg_cadence, 90)
	assert_near(m.distance_m, 600 * 30.0 / 3.6, 0.5)


func test_intervals_raise_np_above_avg() -> void:
	var s := _flat(300, 60) + _flat(100, 120) + _flat(300, 60) + _flat(100, 120)
	var m := RideMetrics.compute(s, 250)
	assert_eq(m.avg_power, int(round((300 * 120 + 100 * 240) / 360.0)))   # 167
	assert_true(m.normalized_power > m.avg_power, "NP %d avg %d" % [m.normalized_power, m.avg_power])
	assert_eq(m.max_power, 300)


func test_hour_at_ftp_is_100_tss() -> void:
	var m := RideMetrics.compute(_flat(250, 3600), 250)
	assert_near(m.tss, 100.0, 0.01)
	assert_near(m.intensity_factor, 1.0)


func test_short_ride_np_falls_back_to_avg() -> void:
	assert_near(RideMetrics.normalized_power(_flat(180, 10)), 180.0)
