class_name RideRecorder
extends Node
## Records one sample per second of the ride and journals each sample to disk
## as it happens, so a crash loses at most a second. The journal is a JSON
## Lines file: first line {"meta": …}, then one {"s": …} per sample, and
## finally {"end": …} when the ride finishes cleanly.

signal sample_added(sample: Dictionary)

const RIDES_DIR := "user://rides"

var ride_id := ""
var meta: Dictionary = {}
var samples: Array[Dictionary] = []

var _file: FileAccess
var _last_second := -1
var _power := 0
var _cadence := 0
var _heart_rate := 0
var _speed_kph := 0.0
var _target := 0
var _segment := -1
var _finished := false


static func rides_dir_abs() -> String:
	return ProjectSettings.globalize_path(RIDES_DIR)


func begin(workout_name: String, ftp: int, now_unix: int = int(Time.get_unix_time_from_system())) -> void:
	DirAccess.make_dir_recursive_absolute(rides_dir_abs())
	ride_id = Time.get_datetime_string_from_unix_time(now_unix, false).replace(":", "-")
	meta = {"workout": workout_name, "ftp": ftp, "started_at": now_unix, "version": 1}
	samples.clear()
	_last_second = -1
	_finished = false
	_file = FileAccess.open(journal_path(), FileAccess.WRITE)
	if _file:
		_file.store_line(JSON.stringify({"meta": meta}))
		_file.flush()


func journal_path() -> String:
	return RIDES_DIR.path_join(ride_id + ".jsonl")


func fit_path() -> String:
	return RIDES_DIR.path_join(ride_id + ".fit")


func attach_runner(runner: WorkoutRunner) -> void:
	runner.ticked.connect(_on_tick)
	runner.target_changed.connect(func(w: int) -> void: _target = w)
	runner.segment_changed.connect(func(i: int, _s: WorkoutSegment) -> void: _segment = i)


func attach_trainer(t: Trainer) -> void:
	t.power_changed.connect(on_power)
	t.cadence_changed.connect(on_cadence)
	t.speed_changed.connect(on_speed)


func attach_heart_rate(h: HeartRateSensor) -> void:
	h.heart_rate_changed.connect(on_heart_rate)


func on_power(w: int) -> void:
	_power = w


func on_cadence(c: int) -> void:
	_cadence = c


func on_heart_rate(b: int) -> void:
	_heart_rate = b


func on_speed(kph: float) -> void:
	_speed_kph = kph


func _on_tick(snap: Dictionary) -> void:
	if snap.state != WorkoutRunner.State.RUNNING:
		return
	var sec := int(floor(snap.elapsed))
	if sec != _last_second:
		_last_second = sec
		record_sample(snap.elapsed, int(Time.get_unix_time_from_system()))


## Append one sample. Public so tests can drive it without a runner.
func record_sample(elapsed: float, now_unix: int) -> Dictionary:
	var s := {
		"t": now_unix, "e": int(floor(elapsed)),
		"p": _power, "c": _cadence, "h": _heart_rate,
		"v": snappedf(_speed_kph, 0.1), "tg": _target, "sg": _segment,
	}
	samples.append(s)
	if _file:
		_file.store_line(JSON.stringify({"s": s}))
		_file.flush()
	sample_added.emit(s)
	return s


func finish(completed: bool, now_unix: int = int(Time.get_unix_time_from_system())) -> void:
	if _finished:
		return
	_finished = true
	meta["ended_at"] = now_unix
	meta["completed"] = completed
	if _file:
		_file.store_line(JSON.stringify({"end": {"ended_at": now_unix, "completed": completed}}))
		_file.close()
		_file = null


## Journals that never got an end line: rides cut short by a crash or quit.
static func unfinished_journals() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(RIDES_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".jsonl"):
			continue
		var j := load_journal(RIDES_DIR.path_join(f))
		if not j.is_empty() and not j.has("end") and j.samples.size() > 0:
			out.append(RIDES_DIR.path_join(f))
	return out


## Read a journal back: {meta, samples, end?}. Tolerates a truncated last line.
static func load_journal(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var out := {"meta": {}, "samples": []}
	var samples: Array[Dictionary] = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not (parsed is Dictionary):
			continue
		if parsed.has("meta"):
			out["meta"] = parsed.meta
		elif parsed.has("s"):
			samples.append(parsed.s)
		elif parsed.has("end"):
			out["end"] = parsed.end
	out["samples"] = samples
	return out
