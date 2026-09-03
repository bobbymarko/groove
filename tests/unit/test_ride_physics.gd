extends TestCase


func test_steady_speed_orders() -> void:
	var flat_200 := RidePhysics.steady_speed(200.0, 0.0)
	var flat_300 := RidePhysics.steady_speed(300.0, 0.0)
	var climb_200 := RidePhysics.steady_speed(200.0, 14.0)
	assert_true(flat_300 > flat_200)
	# Visual grade must not change speed (GRADE_EFFECT 0) so hills stay in step with intervals.
	assert_near(climb_200, flat_200, 0.01)
	assert_true(flat_200 > 6.0 and flat_200 < 11.0, "flat 200 W = %f m/s" % flat_200)   # ~25–35 km/h


func test_step_converges_and_coasts() -> void:
	var p := RidePhysics.new()
	for i in 600:
		p.step(250.0, 0.0, 0.1)
	assert_near(p.speed, RidePhysics.steady_speed(250.0, 0.0), 0.2)
	var v := p.speed
	p.step(0.0, 0.0, 1.0)
	assert_true(p.speed < v)
	for i in 300:
		p.step(0.0, 8.0, 1.0)
	assert_eq(p.speed, RidePhysics.MIN_SPEED)


func test_not_riding_can_stop() -> void:
	var p := RidePhysics.new()
	for i in 200:
		p.step(0.0, 0.0, 1.0, false)
	assert_near(p.speed, 0.0, 0.01)
