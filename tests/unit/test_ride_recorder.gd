extends TestCase

var rec: RideRecorder


func setup() -> void:
	rec = RideRecorder.new()


func teardown() -> void:
	if rec.ride_id != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rec.journal_path()))
	rec.free()


func test_journal_roundtrip() -> void:
	rec.begin("Test workout", 250, 1756800000)
	rec.on_power(200)
	rec.on_cadence(90)
	rec.on_heart_rate(140)
	rec.on_speed(30.0)
	for i in 5:
		rec.record_sample(float(i), 1756800000 + i)
	rec.finish(true, 1756800005)
	var j := RideRecorder.load_journal(rec.journal_path())
	assert_eq(j.meta.workout, "Test workout")
	assert_eq(int(j.meta.ftp), 250)
	assert_eq(j.samples.size(), 5)
	assert_eq(int(j.samples[2].p), 200)
	assert_eq(int(j.samples[2].t), 1756800002)
	assert_true(j.has("end"))
	assert_true(bool(j.end.completed))


func test_unfinished_journal_is_detected_and_readable() -> void:
	rec.begin("Crash test", 200, 1756800000)
	rec.on_power(150)
	for i in 3:
		rec.record_sample(float(i), 1756800000 + i)
	# No finish(): simulate a crash. Data must already be on disk.
	var j := RideRecorder.load_journal(rec.journal_path())
	assert_eq(j.samples.size(), 3)
	assert_true(not j.has("end"))
	assert_true(rec.journal_path() in RideRecorder.unfinished_journals())
	rec.finish(false)


func test_tick_samples_once_per_second_only_while_running() -> void:
	rec.begin("Tick", 200)
	var running := {"state": WorkoutRunner.State.RUNNING, "elapsed": 0.0}
	for e in [0.0, 0.3, 0.9, 1.0, 1.5, 2.2]:
		running.elapsed = e
		rec._on_tick(running)
	assert_eq(rec.samples.size(), 3)   # seconds 0, 1, 2
	rec._on_tick({"state": WorkoutRunner.State.PAUSED, "elapsed": 3.0})
	assert_eq(rec.samples.size(), 3)
	rec.finish(false)
