extends TestCase


func test_norm() -> void:
	assert_eq(Gatt.norm("2AD2"), Gatt.FTMS_INDOOR_BIKE_DATA)
	assert_eq(Gatt.norm("00002AD2-0000-1000-8000-00805F9B34FB"), Gatt.FTMS_INDOOR_BIKE_DATA)


func test_set_target_power_encoding() -> void:
	var b := Gatt.ftms_set_target_power(200)
	assert_eq(Array(b), [0x05, 0xC8, 0x00])
	b = Gatt.ftms_set_target_power(300)
	assert_eq(Array(b), [0x05, 0x2C, 0x01])


func test_sim_grade_encoding() -> void:
	var b := Gatt.ftms_set_sim_grade(4.0)   # 4.00 % => 400 => 0x0190
	assert_eq(b.size(), 7)
	assert_eq(b[0], 0x11)
	assert_eq(b.decode_s16(1), 0)
	assert_eq(b.decode_s16(3), 400)


func test_indoor_bike_data_speed_cadence_power() -> void:
	# flags: speed present (bit0 clear), cadence (bit2), power (bit6) => 0x0044
	var d := PackedByteArray([0x44, 0x00,  0xE8, 0x03,  0xB4, 0x00,  0xF0, 0x00])
	var r := Gatt.parse_indoor_bike_data(d)
	assert_near(r.speed_kph, 10.0)        # 1000 * 0.01
	assert_near(r.cadence_rpm, 90.0)      # 180 * 0.5
	assert_eq(r.power_w, 240)
	assert_true(not r.has("heart_rate"))


func test_indoor_bike_data_more_data_and_heart_rate() -> void:
	# bit0 set (no speed), power (bit6), heart rate (bit9) => 0x0241
	var d := PackedByteArray([0x41, 0x02,  0x64, 0x00,  0x8A])
	var r := Gatt.parse_indoor_bike_data(d)
	assert_true(not r.has("speed_kph"))
	assert_eq(r.power_w, 100)
	assert_eq(r.heart_rate, 138)


func test_indoor_bike_data_truncated_is_safe() -> void:
	assert_eq(Gatt.parse_indoor_bike_data(PackedByteArray([0x44])).size(), 0)
	var r := Gatt.parse_indoor_bike_data(PackedByteArray([0x44, 0x00, 0x10]))
	assert_true(not r.has("speed_kph"))


func test_control_response() -> void:
	var r := Gatt.parse_control_response(PackedByteArray([0x80, 0x05, 0x01]))
	assert_eq(r.op, 0x05)
	assert_true(r.ok)
	r = Gatt.parse_control_response(PackedByteArray([0x80, 0x00, 0x05]))
	assert_true(not r.ok)
	assert_eq(Gatt.result_name(r.result), "control not permitted")
	assert_true(Gatt.parse_control_response(PackedByteArray([0x01, 0x02])).is_empty())


func test_power_range() -> void:
	var r := Gatt.parse_power_range(PackedByteArray([0x00, 0x00, 0xD0, 0x07, 0x01, 0x00]))
	assert_eq(r.min, 0)
	assert_eq(r.max, 2000)
	assert_eq(r.step, 1)


func test_heart_rate_formats() -> void:
	assert_eq(Gatt.parse_heart_rate(PackedByteArray([0x00, 0x7A])), 122)
	assert_eq(Gatt.parse_heart_rate(PackedByteArray([0x16, 0x7A])), 122)          # flags with contact bits
	assert_eq(Gatt.parse_heart_rate(PackedByteArray([0x01, 0x2C, 0x01])), 300)    # uint16 form
	assert_eq(Gatt.parse_heart_rate(PackedByteArray([0x01])), -1)
