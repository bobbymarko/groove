extends TestCase
## FIT workout files: steps, repeats, power targets in % and watts.

const F_INDEX := 254
const F_NAME := 0
const F_DUR_TYPE := 1
const F_DUR_VALUE := 2
const F_TGT_TYPE := 3
const F_TGT_VALUE := 4
const F_LOW := 5
const F_HIGH := 6
const F_INTENSITY := 7


## Build a FIT file with one workout message and the given steps.
func _fit(name: String, steps: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	# workout definition (local 0): wkt_name string[24]
	b.put_u8(0x40); b.put_u8(0); b.put_u8(0); b.put_u16(26); b.put_u8(1)
	b.put_u8(8); b.put_u8(24); b.put_u8(0x07)
	b.put_u8(0x00)
	var nm := name.to_utf8_buffer(); nm.resize(24); b.put_data(nm)
	# step definition (local 1)
	var fields := [[F_INDEX, 2, 0x84], [F_DUR_TYPE, 1, 0x00], [F_DUR_VALUE, 4, 0x86], [F_TGT_TYPE, 1, 0x00],
		[F_TGT_VALUE, 4, 0x86], [F_LOW, 4, 0x86], [F_HIGH, 4, 0x86], [F_INTENSITY, 1, 0x00], [F_NAME, 16, 0x07]]
	b.put_u8(0x41); b.put_u8(0); b.put_u8(0); b.put_u16(27); b.put_u8(fields.size())
	for f in fields:
		b.put_u8(f[0]); b.put_u8(f[1]); b.put_u8(f[2])
	for i in steps.size():
		var st: Dictionary = steps[i]
		b.put_u8(0x01)
		b.put_u16(i)
		b.put_u8(st.get("dur_type", 0)); b.put_u32(st.get("dur", 0))
		b.put_u8(st.get("tgt_type", 4)); b.put_u32(st.get("tgt", 0))
		b.put_u32(st.get("low", 0)); b.put_u32(st.get("high", 0))
		b.put_u8(st.get("intensity", 0))
		var sn: PackedByteArray = str(st.get("name", "")).to_utf8_buffer(); sn.resize(16); b.put_data(sn)
	var data := b.data_array
	var h := StreamPeerBuffer.new()
	h.put_u8(14); h.put_u8(0x20); h.put_u16(2132); h.put_u32(data.size()); h.put_data(".FIT".to_utf8_buffer()); h.put_u16(0)
	var out := h.data_array
	out.append_array(data)
	var crc := FitEncoder.crc16(out)
	out.append(crc & 0xFF); out.append(crc >> 8)
	return out


func test_steps_and_repeat() -> void:
	var bytes := _fit("Boss Battle", [
		{"dur": 600000, "low": 50, "high": 60, "intensity": 2, "name": "Warm up"},
		{"dur": 60000, "low": 1000 + 250, "high": 1000 + 260, "intensity": 0},   # 250-260 W
		{"dur": 120000, "low": 45, "high": 55, "intensity": 1},
		{"dur_type": 6, "dur": 1, "tgt_type": 0, "tgt": 3},                                     # repeat steps 1-2 three times
		{"dur": 300000, "low": 40, "high": 50, "intensity": 3},
	])
	var w := FitWorkoutParser.parse(bytes, 250)
	assert_true(w != null, FitWorkoutParser.last_error)
	assert_eq(w.name, "Boss Battle")
	assert_eq(w.segments.size(), 8, "warmup + 3x(on+off) + cooldown")
	assert_eq(w.segments[0].kind, WorkoutSegment.Kind.WARMUP)
	assert_near(w.segments[0].power_low, 0.55)
	assert_eq(w.segments[1].kind, WorkoutSegment.Kind.INTERVAL_ON)
	assert_near(w.segments[1].power_low, 1.02)
	assert_eq(w.segments[1].rep, 1)
	assert_eq(w.segments[1].rep_count, 3)
	assert_eq(w.segments[2].kind, WorkoutSegment.Kind.INTERVAL_OFF)
	assert_eq(w.segments[5].rep, 3)
	assert_eq(w.segments[7].kind, WorkoutSegment.Kind.COOLDOWN)
	assert_near(w.total_duration(), 600.0 + 3 * 180.0 + 300.0)
	assert_eq(w.text_events.size(), 1)
	assert_eq(w.text_events[0].message, "Warm up")


func test_zone_and_open_targets() -> void:
	var bytes := _fit("Zones", [
		{"dur": 60000, "tgt": 4},                       # zone 4
		{"dur": 60000, "tgt_type": 1, "low": 120, "high": 140},   # heart-rate target: free ride
	])
	var w := FitWorkoutParser.parse(bytes, 250)
	assert_true(w != null, FitWorkoutParser.last_error)
	assert_near(w.segments[0].power_low, 0.98)
	assert_eq(w.segments[1].kind, WorkoutSegment.Kind.FREE_RIDE)


func test_not_fit() -> void:
	assert_true(FitWorkoutParser.parse("nope".to_utf8_buffer(), 250) == null)
