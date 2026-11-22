extends TestCase
## The realistic look's quality tiers and the render-scale governor's rule (R15, R43).


func test_gpu_names_pick_the_default_tier() -> void:
	assert_eq(RealQuality.default_for_gpu("Apple M4 Pro"), "high")
	assert_eq(RealQuality.default_for_gpu("Apple M2 Max"), "high")
	assert_eq(RealQuality.default_for_gpu("Apple M1 Ultra"), "high")
	assert_eq(RealQuality.default_for_gpu("Apple M1"), "medium")
	assert_eq(RealQuality.default_for_gpu("Apple M3"), "medium")
	assert_eq(RealQuality.default_for_gpu("NVIDIA GeForce RTX 4090"), "medium")
	assert_eq(RealQuality.default_for_gpu(""), "medium")


func test_tiers_get_cheaper_downwards() -> void:
	var lo: Dictionary = RealQuality.TABLE.low
	var med: Dictionary = RealQuality.TABLE.medium
	var hi: Dictionary = RealQuality.TABLE.high
	assert_true(float(lo.scale_max) < float(med.scale_max) and float(med.scale_max) < float(hi.scale_max))
	assert_true(int(lo.shadow_splits) < int(hi.shadow_splits) and float(lo.shadow_dist) < float(med.shadow_dist) and float(med.shadow_dist) < float(hi.shadow_dist))
	assert_true(float(lo.forest_density) < float(med.forest_density) and float(med.forest_density) < float(hi.forest_density))
	assert_eq(RealQuality.normalize("bogus"), "high")


func test_grass_rings_thin_with_the_tier() -> void:
	var base := RealGrass.RINGS
	RealQuality.set_tier("high")
	assert_eq(RealQuality.grass_rings(base).size(), 3)
	assert_eq(float(RealQuality.grass_rings(base)[2].out), 56.0)
	RealQuality.set_tier("low")
	assert_eq(RealQuality.grass_rings(base).size(), 2)
	RealQuality.set_tier("medium")
	assert_true(float(RealQuality.grass_rings(base)[2].out) < 56.0)
	RealQuality.set_tier("high")


func _st(scale: float, since := 10.0, calm := 0.0, fast := 0.0, wait := 20.0, probing := false, probe_t := 0.0) -> Dictionary:
	return {"scale": scale, "since_change": since, "calm": calm, "fast": fast, "wait": wait, "probing": probing, "probe_t": probe_t}


func test_steps_down_over_budget() -> void:
	assert_near(float(RealQuality.govern(_st(0.67), 19.0, 0.016, 0.67).scale), 0.62, 0.001)
	assert_near(float(RealQuality.govern(_st(0.67), 17.5, 0.016, 0.67).scale), 0.67, 0.001)   # inside the 6 % margin
	assert_near(float(RealQuality.govern(_st(0.4), 40.0, 0.016, 0.67).scale), 0.4, 0.001)      # the floor


func test_waits_between_changes() -> void:
	assert_near(float(RealQuality.govern(_st(0.67, 1.0), 30.0, 0.016, 0.67).scale), 0.67, 0.001)
	assert_near(float(RealQuality.govern(_st(0.5, 1.0, 0.0, 9.0), 9.0, 0.016, 0.67).scale), 0.5, 0.001)


func test_steps_up_when_headroom_is_visible() -> void:
	assert_near(float(RealQuality.govern(_st(0.5, 10.0, 0.0, 4.0), 9.0, 0.016, 0.67).scale), 0.55, 0.001)
	assert_near(float(RealQuality.govern(_st(0.5, 10.0, 0.0, 1.0), 9.0, 0.016, 0.67).scale), 0.5, 0.001)   # not long enough


func test_probe_after_calm_and_back_off_when_it_fails() -> void:
	var s := RealQuality.govern(_st(0.5, 10.0, 20.0), 16.7, 0.016, 0.67)
	assert_near(float(s.scale), 0.55, 0.001)
	assert_true(s.probing)
	# Over budget after the probe: undone, and the wait doubles.
	s.since_change = 4.0
	s = RealQuality.govern(s, 19.0, 0.016, 0.67)
	assert_near(float(s.scale), 0.5, 0.001)
	assert_false(s.probing)
	assert_near(float(s.wait), 40.0, 0.001)
	# The wait is capped.
	var capped := _st(0.55, 10.0, 0.0, 0.0, 250.0, true, 1.0)
	assert_near(float(RealQuality.govern(capped, 19.0, 0.016, 0.67).wait), 300.0, 0.001)


func test_probe_that_holds_resets_the_wait() -> void:
	var s := _st(0.55, 8.0, 0.0, 0.0, 80.0, true, 5.99)
	s = RealQuality.govern(s, 16.7, 0.02, 0.67)
	assert_false(s.probing)
	assert_near(float(s.wait), 20.0, 0.001)
	assert_near(float(s.scale), 0.55, 0.001)


func test_tier_change_clamps_at_once() -> void:
	assert_near(float(RealQuality.govern(_st(0.67, 0.0), 14.0, 0.016, 0.5).scale), 0.5, 0.001)
	assert_near(float(RealQuality.govern(_st(0.3, 0.0), 14.0, 0.016, 0.5).scale), 0.4, 0.001)
	assert_near(float(RealQuality.govern(_st(0.62, 10.0, 0.0, 20.0), 5.0, 0.016, 0.59).scale), 0.59, 0.001)


## One simulated ride: a GPU with frame cost a + b * scale^2 on a display with the
## given refresh interval; the displayed frame time is max(cost, refresh) and is
## smoothed over 2 s like RealLook does. Returns {scale, changes: [[time, scale]...]}.
func _simulate(a: float, b: float, refresh_ms: float, ceiling: float, seconds: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var st := RealQuality.new_state(minf(0.5, ceiling))
	var avg := 0.0
	var log: Array = []
	var t := 0.0
	while t < seconds:
		var cost := maxf(a + b * st.scale * st.scale, refresh_ms)
		avg = cost if avg <= 0.0 else lerpf(avg, cost, 1.0 - exp(-dt / 2.0))
		var before: float = st.scale
		st = RealQuality.govern(st, avg, dt, ceiling)
		if not is_equal_approx(before, float(st.scale)):
			log.append([t, float(st.scale)])
		t += dt
	return {"scale": st.scale, "changes": log}


func test_60hz_display_with_a_heavy_scene_settles_and_only_probes() -> void:
	# 22 ms at 0.67, 16.1 ms at 0.55, 18.4 ms at 0.6: 0.55 is the best that holds.
	var r := _simulate(4.0, 40.0, 16.67, 0.67, 900.0)
	var log: Array = r.changes
	assert_true(float(r.scale) <= 0.56, "ends at %.2f" % float(r.scale))
	var late := 0
	var above := 0
	for c: Array in log:
		if float(c[0]) > 120.0:
			late += 1
		if float(c[1]) > 0.56:
			above += 1
	# After settling, changes come only as probe pairs (up, then back down) at backed-off intervals.
	assert_true(late <= 8, "%d changes after 120 s" % late)
	assert_true(above <= 6, "%d probes above the settled scale" % above)
	var gaps: Array[float] = []
	var last_up := -1.0
	for c: Array in log:
		if float(c[1]) > 0.56 and float(c[0]) > 120.0:
			if last_up >= 0.0:
				gaps.append(float(c[0]) - last_up)
			last_up = float(c[0])
	for i in range(1, gaps.size()):
		assert_true(gaps[i] > gaps[i - 1], "probe gaps grow: %s" % str(gaps))


func test_120hz_display_with_headroom_climbs_to_the_ceiling_and_stays() -> void:
	var r := _simulate(3.0, 15.0, 8.33, 0.67, 300.0)
	assert_near(float(r.scale), 0.67, 0.001)
	for c: Array in r.changes:
		assert_true(float(c[0]) < 60.0, "no change after the climb (change at %.0f s)" % float(c[0]))
