extends TestCase

var p: FakePeripheral
var t: FtmsTrainer
var powers: Array[int] = []
var cadences: Array[int] = []
var events: Array[String] = []


func setup() -> void:
	p = FakePeripheral.new()
	p.name = "KICKR CORE TEST"
	p.services_to_report = FakePeripheral.ftms_services()
	t = FtmsTrainer.new()
	t.power_changed.connect(func(w: int): powers.append(w))
	t.cadence_changed.connect(func(c: int): cadences.append(c))
	t.connected.connect(func(): events.append("connected"))
	t.disconnected.connect(func(): events.append("disconnected"))
	powers.clear(); cadences.clear(); events.clear()


func teardown() -> void:
	t.free()


func _bring_up() -> void:
	t.attach(p)
	p.simulate_connect()
	p.simulate_services()


func test_attach_connects_and_discovers() -> void:
	t.attach(p)
	assert_eq(p.connect_calls, 1)
	p.simulate_connect()
	assert_eq(p.discover_calls, 1)
	assert_true(not t.is_device_connected())


func test_setup_subscribes_and_handshakes_in_order() -> void:
	_bring_up()
	assert_true(Gatt.FTMS_CONTROL_POINT in p.subscribes)
	assert_true(Gatt.FTMS_INDOOR_BIKE_DATA in p.subscribes)
	assert_true(Gatt.FTMS_POWER_RANGE in p.reads)
	assert_true(t.is_device_connected())
	assert_eq(events, ["connected"])
	# Only Request Control has been written; Start waits for the ack.
	assert_eq(p.writes.size(), 1)
	assert_eq(p.writes[0][0], Gatt.FtmsOp.REQUEST_CONTROL)
	p.ack_last_write()
	assert_true(t.has_control())
	assert_eq(p.writes.size(), 2)
	assert_eq(p.writes[1][0], Gatt.FtmsOp.START_RESUME)
	p.ack_last_write()
	assert_eq(p.writes.size(), 2)  # nothing else queued


func test_target_before_setup_is_applied_after_handshake() -> void:
	t.set_target_power(180)
	_bring_up()
	p.ack_last_write()   # request control
	p.ack_last_write()   # start
	assert_eq(p.writes.size(), 3)
	assert_eq(Array(p.writes[2]), [0x05, 0xB4, 0x00])


func test_one_write_in_flight_and_newest_target_wins() -> void:
	_bring_up()
	p.ack_last_write()
	p.ack_last_write()
	t.set_target_power(150)
	t.set_target_power(160)
	t.set_target_power(170)
	assert_eq(p.writes.size(), 3)          # 150 in flight, 160 dropped, 170 queued
	p.ack_last_write()
	assert_eq(p.writes.size(), 4)
	assert_eq(p.writes[3].decode_s16(1), 170)
	p.ack_last_write()
	assert_eq(p.writes.size(), 4)


func test_write_timeout_unblocks_queue() -> void:
	_bring_up()
	t.set_target_power(200)
	assert_eq(p.writes.size(), 1)          # request control in flight, never acked
	t.tick(FtmsTrainer.WRITE_TIMEOUT + 0.1)
	assert_eq(p.writes.size(), 2)          # start went out despite the missing ack


func test_telemetry_parsing() -> void:
	_bring_up()
	p.simulate_notify(Gatt.FTMS_INDOOR_BIKE_DATA, PackedByteArray([0x44, 0x00, 0xE8, 0x03, 0xB4, 0x00, 0xF0, 0x00]))
	assert_eq(powers, [240])
	assert_eq(cadences, [90])


func test_power_range_read() -> void:
	_bring_up()
	p.read_completed.emit(Gatt.FTMS_POWER_RANGE, PackedByteArray([0x00, 0x00, 0xD0, 0x07, 0x01, 0x00]))
	assert_eq(t.supported_power_range(), Vector2i(0, 2000))


func test_dropout_reconnects_and_reapplies_target() -> void:
	_bring_up()
	p.ack_last_write()
	p.ack_last_write()
	t.set_target_power(210)
	p.ack_last_write()
	p.simulate_disconnect()
	assert_eq(events, ["connected", "disconnected"])
	assert_true(not t.is_device_connected())
	assert_eq(p.connect_calls, 1)
	t.tick(FtmsTrainer.RECONNECT_DELAY + 0.1)
	assert_eq(p.connect_calls, 2)
	p.simulate_connect()
	p.simulate_services()
	assert_eq(events, ["connected", "disconnected", "connected"])
	var n := p.writes.size()
	p.ack_last_write()   # request control
	p.ack_last_write()   # start
	assert_eq(p.writes.size(), n + 2)
	assert_eq(p.writes[-1].decode_s16(1), 210)   # target re-applied


func test_failed_reconnect_retries() -> void:
	_bring_up()
	p.simulate_disconnect()
	p.fail_next_connect = true
	t.tick(FtmsTrainer.RECONNECT_DELAY + 0.1)
	assert_eq(p.connect_calls, 2)
	t.tick(FtmsTrainer.RECONNECT_DELAY + 0.1)
	assert_eq(p.connect_calls, 2)             # backoff: second wait is doubled
	t.tick(FtmsTrainer.RECONNECT_DELAY + 0.1)
	assert_eq(p.connect_calls, 3)


func test_disconnect_device_stops_reconnecting() -> void:
	_bring_up()
	t.disconnect_device()
	assert_eq(p.disconnect_calls, 1)
	t.tick(FtmsTrainer.RECONNECT_DELAY + 1.0)
	assert_eq(p.connect_calls, 1)


func test_erg_off_sends_sim_grade() -> void:
	_bring_up()
	p.ack_last_write()
	p.ack_last_write()
	t.set_resistance(0.5)
	assert_eq(p.writes[-1][0], Gatt.FtmsOp.SET_SIM_PARAMS)
	assert_eq(p.writes[-1].decode_s16(3), 400)   # 0.5 => 4.00 %


func test_control_refused_is_reported() -> void:
	var msgs: Array[String] = []
	t.status_changed.connect(func(s: String): msgs.append(s))
	_bring_up()
	p.ack_last_write(Gatt.FtmsResult.CONTROL_NOT_PERMITTED)
	assert_true(not t.has_control())
	assert_true(msgs[-1].contains("refused control"))


func test_device_without_ftms_is_not_ready() -> void:
	p.services_to_report = FakePeripheral.hr_services()
	_bring_up()
	assert_true(not t.is_device_connected())
	assert_eq(events, [])


func test_data_silence_is_treated_as_disconnect() -> void:
	_bring_up()
	p.ack_last_write()
	p.ack_last_write()
	t.set_target_power(220)
	p.ack_last_write()
	# Data keeps the watchdog quiet.
	for i in 3:
		t.tick(4.0)
		p.simulate_notify(Gatt.FTMS_INDOOR_BIKE_DATA, PackedByteArray([0x44, 0x00, 0, 0, 0, 0, 0xDC, 0x00]))
	assert_true(t.is_device_connected())
	assert_eq(events, ["connected"])
	# Silence triggers a probe read first...
	p.reads.clear()
	t.tick(FtmsTrainer.DATA_TIMEOUT + 0.1)
	assert_eq(p.reads, [Gatt.FTMS_POWER_RANGE])
	assert_true(t.is_device_connected())
	# ...and an unanswered probe means the link is gone.
	t.tick(FtmsTrainer.PROBE_TIMEOUT + 0.1)
	assert_true(not t.is_device_connected())
	assert_eq(events, ["connected", "disconnected"])
	# ...and the normal reconnect path re-applies the target.
	t.tick(FtmsTrainer.RECONNECT_DELAY + 0.1)
	assert_eq(p.connect_calls, 2)
	p.simulate_connect()
	p.simulate_services()
	p.ack_last_write()
	p.ack_last_write()
	assert_eq(p.writes[-1].decode_s16(1), 220)


func test_answered_probe_keeps_link_alive() -> void:
	_bring_up()
	t.tick(FtmsTrainer.DATA_TIMEOUT + 0.1)
	assert_eq(p.reads.count(Gatt.FTMS_POWER_RANGE), 2)  # one at setup, one probe
	p.read_completed.emit(Gatt.FTMS_POWER_RANGE, PackedByteArray([0, 0, 0xD0, 0x07, 1, 0]))
	t.tick(FtmsTrainer.PROBE_TIMEOUT + 0.1)
	assert_true(t.is_device_connected())
	assert_eq(events, ["connected"])
