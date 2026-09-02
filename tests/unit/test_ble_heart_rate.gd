extends TestCase

var p: FakePeripheral
var hr: BleHeartRate
var bpms: Array[int] = []


func setup() -> void:
	p = FakePeripheral.new()
	p.services_to_report = FakePeripheral.hr_services()
	hr = BleHeartRate.new()
	hr.heart_rate_changed.connect(func(b: int): bpms.append(b))
	bpms.clear()


func teardown() -> void:
	hr.free()


func test_subscribes_and_reports() -> void:
	hr.attach(p)
	p.simulate_connect()
	p.simulate_services()
	assert_true(hr.is_device_connected())
	assert_eq(p.subscribes, [Gatt.HEART_RATE_MEASUREMENT])
	p.simulate_notify(Gatt.HEART_RATE_MEASUREMENT, PackedByteArray([0x00, 0x8C]))
	assert_eq(bpms, [140])


func test_reconnects_after_dropout() -> void:
	hr.attach(p)
	p.simulate_connect()
	p.simulate_services()
	p.simulate_disconnect()
	assert_true(not hr.is_device_connected())
	hr.tick(BleHeartRate.RECONNECT_DELAY + 0.1)
	assert_eq(p.connect_calls, 2)
