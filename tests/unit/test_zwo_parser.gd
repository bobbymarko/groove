extends TestCase

const FIXTURE := "res://workouts/cadence_today.zwo"

var w: Workout


func setup() -> void:
	w = ZwoParser.parse_file(FIXTURE)


func test_parses_metadata() -> void:
	assert_true(w != null, ZwoParser.last_error)
	assert_eq(w.name, "Cadence: Corner Exit")
	assert_eq(w.author, "Cadence")
	assert_true(w.description.begins_with("First top-end session"))


func test_segment_structure() -> void:
	# Warmup + 6×(on, off) + steady + cooldown
	assert_eq(w.segments.size(), 1 + 12 + 1 + 1)
	assert_eq(w.segments[0].kind, WorkoutSegment.Kind.WARMUP)
	assert_eq(w.segments[1].kind, WorkoutSegment.Kind.INTERVAL_ON)
	assert_eq(w.segments[2].kind, WorkoutSegment.Kind.INTERVAL_OFF)
	assert_eq(w.segments[13].kind, WorkoutSegment.Kind.STEADY)
	assert_eq(w.segments[14].kind, WorkoutSegment.Kind.COOLDOWN)
	assert_near(w.total_duration(), 600 + 6 * 180 + 360 + 180)


func test_warmup_ramp() -> void:
	var s := w.segments[0]
	assert_near(s.duration, 600.0)
	assert_near(s.power_low, 0.45)
	assert_near(s.power_high, 0.70)
	assert_true(s.is_ramp())
	assert_near(s.power_at(0.0), 0.45)
	assert_near(s.power_at(300.0), 0.575)
	assert_near(s.power_at(600.0), 0.70)


func test_intervals() -> void:
	var on := w.segments[1]
	var off := w.segments[2]
	assert_near(on.duration, 60.0)
	assert_near(on.power_low, 1.06)
	assert_eq(on.cadence, 95)
	assert_eq(on.rep, 1)
	assert_eq(on.rep_count, 6)
	assert_near(off.duration, 120.0)
	assert_near(off.power_low, 0.50)
	assert_eq(off.cadence, 0)
	assert_eq(w.segments[11].rep, 6)
	assert_eq(w.segments[11].kind, WorkoutSegment.Kind.INTERVAL_ON)


func test_cooldown_ramps_down() -> void:
	var s := w.segments[14]
	assert_near(s.power_low, 0.55)
	assert_near(s.power_high, 0.40)


func test_text_events_absolute_times() -> void:
	# 4 warmup + 6 interval + 2 steady + 1 cooldown
	assert_eq(w.text_events.size(), 13)
	assert_near(w.text_events[0].time, 10.0)
	assert_true(w.text_events[0].message.begins_with("Wednesday"))
	# Interval block starts at 600; its events are offset from the block start.
	assert_near(w.text_events[4].time, 600.0)
	assert_true(w.text_events[4].message.begins_with("Rep 1"))
	assert_near(w.text_events[5].time, 780.0)
	# Steady block starts at 600 + 1080 = 1680
	assert_near(w.text_events[10].time, 1690.0)
	# Cooldown starts at 2040
	assert_near(w.text_events[12].time, 2050.0)


func test_target_lookup() -> void:
	assert_near(w.target_fraction_at(0.0), 0.45)
	assert_near(w.target_fraction_at(600.0), 1.06)
	assert_near(w.target_fraction_at(659.9), 1.06)
	assert_near(w.target_fraction_at(660.0), 0.50)
	assert_eq(w.segment_index_at(w.total_duration()), -1)
	assert_eq(w.segment_index_at(-1.0), -1)


func test_free_ride_and_unknown_blocks() -> void:
	var xml := """<workout_file><name>X</name><sportType>bike</sportType><workout>
		<FreeRide Duration="300" FlatRoad="1"/>
		<SteadyState Duration="60" Power="0.8"><textevent timeoffset="5" message="a &amp; b"/></SteadyState>
		<Mystery Duration="999"/>
		<Ramp Duration="120" PowerLow="0.5" PowerHigh="0.9"/>
	</workout></workout_file>"""
	var x := ZwoParser.parse(xml)
	assert_true(x != null, ZwoParser.last_error)
	assert_eq(x.segments.size(), 3)
	assert_eq(x.segments[0].kind, WorkoutSegment.Kind.FREE_RIDE)
	assert_true(not x.segments[0].has_target())
	assert_near(x.target_fraction_at(10.0), 0.0)
	assert_eq(x.text_events[0].message, "a & b")
	assert_near(x.text_events[0].time, 305.0)
	assert_eq(x.segments[2].kind, WorkoutSegment.Kind.RAMP)


func test_rejects_garbage() -> void:
	assert_true(ZwoParser.parse("not xml at all") == null)
	assert_true(ZwoParser.parse("<workout_file><workout/></workout_file>") == null)
	assert_true(ZwoParser.parse_file("res://nope.zwo") == null)
	assert_true(ZwoParser.last_error != "")


func test_rejects_running_workouts() -> void:
	var xml := "<workout_file><sportType>run</sportType><workout><SteadyState Duration='60' Power='0.8'/></workout></workout_file>"
	assert_true(ZwoParser.parse(xml) == null)
