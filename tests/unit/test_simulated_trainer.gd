extends TestCase

var t: SimulatedTrainer
var powers: Array[int] = []
var cadences: Array[int] = []


func setup() -> void:
	t = SimulatedTrainer.new()
	t._ready()  # not in a tree; wire the timer manually
	t.noise_fraction = 0.0
	t.power_changed.connect(func(w: int): powers.append(w))
	t.cadence_changed.connect(func(c: int): cadences.append(c))
	powers.clear(); cadences.clear()


func teardown() -> void:
	t.free()


func test_connect_state() -> void:
	assert_true(not t.is_device_connected())
	t.connect_device()
	assert_true(t.is_device_connected())
	t.disconnect_device()
	assert_true(not t.is_device_connected())


func test_erg_converges_to_target() -> void:
	t.set_target_power(200)
	for i in 30:
		t.step(1.0)
	assert_true(absi(powers[-1] - 200) <= 3, "power %d" % powers[-1])
	assert_true(cadences[-1] > 70, "cadence %d" % cadences[-1])


func test_erg_follows_target_change_within_seconds() -> void:
	t.set_target_power(150)
	for i in 30:
		t.step(1.0)
	t.set_target_power(250)
	for i in 8:
		t.step(1.0)
	assert_true(powers[-1] > 230, "power %d after 8 s" % powers[-1])


func test_not_pedaling_reads_zero() -> void:
	t.pedaling = false
	t.set_target_power(200)
	for i in 30:
		t.step(1.0)
	assert_eq(powers[-1], 0)
	assert_eq(cadences[-1], 0)


func test_resistance_mode_depends_on_cadence() -> void:
	t.set_target_power(100)
	for i in 20:
		t.step(1.0)
	t.set_resistance(0.5)
	for i in 30:
		t.step(1.0)
	assert_true(powers[-1] > 150 and powers[-1] < 300, "power %d" % powers[-1])
