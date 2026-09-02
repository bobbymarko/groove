extends TestCase

const FIXTURE := "res://workouts/cadence_today.zwo"
const FTP := 250

var r: WorkoutRunner
var targets: Array[int] = []
var segments: Array[int] = []
var messages: Array[String] = []
var finished_with: Array[bool] = []


func setup() -> void:
	r = WorkoutRunner.new()
	r.target_changed.connect(func(w: int): targets.append(w))
	r.segment_changed.connect(func(i: int, _s: WorkoutSegment): segments.append(i))
	r.text_event.connect(func(m: String): messages.append(m))
	r.finished.connect(func(c: bool): finished_with.append(c))
	r.load_workout(ZwoParser.parse_file(FIXTURE), FTP)
	targets.clear(); segments.clear(); messages.clear(); finished_with.clear()


func teardown() -> void:
	r.free()


func test_initial_state() -> void:
	assert_eq(r.state, WorkoutRunner.State.READY)
	assert_eq(r.bias, 100)
	assert_true(r.erg_enabled)


func test_start_emits_first_segment_and_target() -> void:
	r.start()
	assert_eq(r.state, WorkoutRunner.State.RUNNING)
	assert_eq(segments, [0])
	assert_eq(targets, [int(round(0.45 * FTP))])  # 112 or 113


func test_ramp_target_changes_over_time() -> void:
	r.start()
	r.advance(300.0)
	assert_eq(r.current_target, int(round(0.575 * FTP)))
	assert_true(targets.size() >= 2)


func test_segment_boundaries_and_text_events() -> void:
	r.start()
	for i in 61:
		r.advance(10.0)  # to 610 s
	assert_eq(r.current_index, 1)
	assert_eq(r.current_target, int(round(1.06 * FTP)))
	assert_eq(messages.size(), 5)  # 4 warmup messages + "Rep 1"
	assert_true(messages[4].begins_with("Rep 1"))


func test_pause_freezes_time() -> void:
	r.start()
	r.advance(5.0)
	r.pause()
	r.advance(100.0)
	assert_near(r.elapsed, 5.0)
	assert_eq(r.state, WorkoutRunner.State.PAUSED)
	r.resume()
	r.advance(1.0)
	assert_near(r.elapsed, 6.0)


func test_skip_moves_to_next_segment_and_drops_its_messages() -> void:
	r.start()
	r.advance(20.0)          # past the 10 s warmup message
	assert_eq(messages.size(), 1)
	r.skip_segment()
	assert_eq(r.current_index, 1)
	assert_near(r.elapsed, 600.0)
	# Skipped warmup messages at 300/480/560 are dropped; "Rep 1" at 600 fires.
	assert_eq(messages.size(), 2)
	assert_true(messages[1].begins_with("Rep 1"))


func test_skip_while_paused_stays_paused() -> void:
	r.start()
	r.pause()
	r.skip_segment()
	assert_eq(r.state, WorkoutRunner.State.PAUSED)
	assert_eq(r.current_index, 1)


func test_bias_scales_target_and_clamps() -> void:
	r.start()
	r.skip_segment()  # into rep 1, 1.06 × FTP
	var base := int(round(1.06 * FTP))
	assert_eq(r.current_target, base)
	r.adjust_bias(10)
	assert_eq(r.current_target, int(round(1.06 * FTP * 1.10)))
	r.adjust_bias(1000)
	assert_eq(r.bias, WorkoutRunner.BIAS_MAX)
	r.adjust_bias(-1000)
	assert_eq(r.bias, WorkoutRunner.BIAS_MIN)


func test_erg_toggle() -> void:
	var seen: Array[bool] = []
	r.erg_changed.connect(func(e: bool): seen.append(e))
	r.set_erg(false)
	r.set_erg(false)
	r.set_erg(true)
	assert_eq(seen, [false, true])


func test_runs_to_completion() -> void:
	r.start()
	var total := r.workout.total_duration()
	var t := 0.0
	while t < total + 5.0:
		r.advance(1.0)
		t += 1.0
	assert_eq(r.state, WorkoutRunner.State.FINISHED)
	assert_eq(finished_with, [true])
	assert_eq(messages.size(), 13)
	assert_eq(segments.size(), 15)
	assert_near(r.elapsed, total)


func test_end_early() -> void:
	r.start()
	r.advance(30.0)
	r.end_early()
	assert_eq(r.state, WorkoutRunner.State.FINISHED)
	assert_eq(finished_with, [false])
	r.advance(10.0)
	assert_near(r.elapsed, 30.0)


func test_snapshot_fields() -> void:
	r.start()
	r.advance(100.0)
	var s := r.snapshot()
	assert_near(s.elapsed, 100.0)
	assert_near(s.remaining, r.workout.total_duration() - 100.0)
	assert_eq(s.segment_index, 0)
	assert_near(s.segment_remaining, 500.0)
	assert_eq(s.target_watts, r.current_target)
