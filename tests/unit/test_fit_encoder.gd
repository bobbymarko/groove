extends TestCase


func _ride(n: int) -> Array:
	var out := []
	for i in n:
		out.append({"t": 1756800000 + i, "e": i, "p": 150 + (i % 7), "c": 88, "h": 130 + (i % 5), "v": 28.8, "tg": 150, "sg": 0})
	return out


func test_crc16_self_check_property() -> void:
	# For the FIT CRC, appending a buffer's CRC (little endian) makes the whole check to 0.
	var h := PackedByteArray([0x0E, 0x10, 0x5E, 0x08, 0x74, 0x00, 0x00, 0x00, 0x2E, 0x46, 0x49, 0x54])
	var crc := FitEncoder.crc16(h)
	assert_true(crc != 0)
	h.append(crc & 0xFF)
	h.append((crc >> 8) & 0xFF)
	assert_eq(FitEncoder.crc16(h), 0)
	assert_eq(FitEncoder.crc16(PackedByteArray()), 0)


func test_structure_and_crc() -> void:
	var samples := _ride(120)
	var meta := {"started_at": 1756800000, "ftp": 250, "workout": "Test"}
	var metrics := RideMetrics.compute(samples, 250)
	var bytes := FitEncoder.encode(meta, samples, metrics, true)
	var d := FitReader.read(bytes)
	assert_eq(d.header.size, 14)
	assert_eq(d.header.magic, ".FIT")
	assert_eq(d.header.data_size, bytes.size() - 14 - 2)
	assert_true(d.crc_ok, "file CRC")
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_FILE_ID).size(), 1)
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_RECORD).size(), 120)
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_EVENT).size(), 2)
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_LAP).size(), 1)
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_SESSION).size(), 1)
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_ACTIVITY).size(), 1)


func test_field_values() -> void:
	var samples := _ride(60)
	var meta := {"started_at": 1756800000, "ftp": 250}
	var metrics := RideMetrics.compute(samples, 250)
	var d := FitReader.read(FitEncoder.encode(meta, samples, metrics, true))
	var file_id: Dictionary = FitReader.of_type(d, FitEncoder.MSG_FILE_ID)[0]
	assert_eq(file_id[0], 4)                                   # type = activity
	assert_eq(file_id[1], 255)                                 # manufacturer = development
	assert_eq(file_id[4], 1756800000 - 631065600)              # time_created in FIT epoch
	var rec: Dictionary = FitReader.of_type(d, FitEncoder.MSG_RECORD)[3]
	assert_eq(rec[253], 1756800003 - 631065600)
	assert_eq(rec[7], 153)                                     # power
	assert_eq(rec[4], 88)                                      # cadence
	assert_eq(rec[3], 133)                                     # heart rate
	assert_eq(rec[6], 8000)                                    # 28.8 km/h = 8.000 m/s
	var session: Dictionary = FitReader.of_type(d, FitEncoder.MSG_SESSION)[0]
	assert_eq(session[5], 2)                                   # cycling
	assert_eq(session[6], 58)                                  # virtual_activity
	assert_eq(session[8], 60000)                               # timer time ms
	assert_eq(session[20], metrics.avg_power)
	assert_eq(session[101], 250)                               # threshold power
	assert_eq(session[26], 1)                                  # one lap
	var activity: Dictionary = FitReader.of_type(d, FitEncoder.MSG_ACTIVITY)[0]
	assert_eq(activity[1], 1)                                  # one session


func test_missing_heart_rate_is_invalid_marker() -> void:
	var samples := [{"t": 1756800000, "p": 100, "c": 80, "h": 0, "v": 20.0}]
	var d := FitReader.read(FitEncoder.encode({"started_at": 1756800000, "ftp": 200}, samples, RideMetrics.compute(samples, 200)))
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_RECORD)[0][3], 0xFF)
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_SESSION)[0][16], 0xFF)


func test_indoor_flag() -> void:
	var samples := _ride(5)
	var d := FitReader.read(FitEncoder.encode({"started_at": 1756800000, "ftp": 200}, samples, RideMetrics.compute(samples, 200), false))
	assert_eq(FitReader.of_type(d, FitEncoder.MSG_SESSION)[0][6], 6)
