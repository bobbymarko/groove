class_name WorkoutRunner
extends Node
## Runs a Workout as a timeline. Computes the target power each frame from the
## segment, the rider's FTP, and the intensity bias, and emits events the HUD,
## trainer, and recorder subscribe to. Knows nothing about devices or UI.

enum State { IDLE, READY, RUNNING, PAUSED, FINISHED }

signal state_changed(state: State)
signal ticked(snapshot: Dictionary)
signal target_changed(watts: int)
signal segment_changed(index: int, segment: WorkoutSegment)
signal text_event(message: String)
signal erg_changed(enabled: bool)
signal bias_changed(percent: int)
signal finished(completed: bool)

const BIAS_MIN := 50
const BIAS_MAX := 150

var workout: Workout
var ftp: int = 200
var state := State.IDLE
var elapsed := 0.0
var bias := 100
var erg_enabled := true
var current_index := -1
var current_target := -1
var time_scale := 1.0  ## >1 fast-forwards; used by tests and demos

var _next_event := 0


func load_workout(w: Workout, ftp_watts: int) -> void:
	workout = w
	ftp = maxi(ftp_watts, 1)
	elapsed = 0.0
	bias = 100
	erg_enabled = true
	current_index = -1
	current_target = -1
	_next_event = 0
	_set_state(State.READY)


func start() -> void:
	if state != State.READY:
		return
	_set_state(State.RUNNING)
	advance(0.0)


func pause() -> void:
	if state == State.RUNNING:
		_set_state(State.PAUSED)


func resume() -> void:
	if state == State.PAUSED:
		_set_state(State.RUNNING)


func toggle_pause() -> void:
	if state == State.RUNNING:
		pause()
	elif state == State.PAUSED:
		resume()
	elif state == State.READY:
		start()


## Jump to the start of the next segment. Text events in the skipped span are dropped.
func skip_segment() -> void:
	if not _is_active() or current_index < 0:
		return
	var target_time := workout.segment_end(current_index)
	_seek(target_time)


func adjust_bias(delta_percent: int) -> void:
	var b := clampi(bias + delta_percent, BIAS_MIN, BIAS_MAX)
	if b == bias:
		return
	bias = b
	bias_changed.emit(bias)
	_refresh_target()


func set_erg(enabled: bool) -> void:
	if erg_enabled == enabled:
		return
	erg_enabled = enabled
	erg_changed.emit(enabled)


func end_early() -> void:
	if state == State.FINISHED or state == State.IDLE:
		return
	_set_state(State.FINISHED)
	finished.emit(false)


func _process(delta: float) -> void:
	if state == State.RUNNING:
		advance(delta * time_scale)


## Move the timeline forward by dt seconds. Public so tests can drive it.
func advance(dt: float) -> void:
	if state != State.RUNNING:
		return
	elapsed += dt
	var total := workout.total_duration()
	if elapsed >= total:
		elapsed = total
		_fire_events_through(total)
		ticked.emit(snapshot())
		_set_state(State.FINISHED)
		finished.emit(true)
		return
	var idx := workout.segment_index_at(elapsed)
	if idx != current_index:
		current_index = idx
		segment_changed.emit(idx, workout.segments[idx])
	_fire_events_through(elapsed)
	_refresh_target()
	ticked.emit(snapshot())


func snapshot() -> Dictionary:
	var total := workout.total_duration() if workout else 0.0
	var seg_start := workout.segment_start(current_index) if current_index >= 0 else 0.0
	var seg_dur := workout.segments[current_index].duration if current_index >= 0 else 0.0
	return {
		"state": state,
		"elapsed": elapsed,
		"remaining": maxf(total - elapsed, 0.0),
		"total": total,
		"segment_index": current_index,
		"segment_elapsed": elapsed - seg_start,
		"segment_remaining": maxf(seg_start + seg_dur - elapsed, 0.0),
		"target_watts": maxi(current_target, 0),
		"bias": bias,
		"erg": erg_enabled,
	}


func current_segment() -> WorkoutSegment:
	return workout.segments[current_index] if workout and current_index >= 0 else null


func next_segment() -> WorkoutSegment:
	if workout and current_index >= 0 and current_index + 1 < workout.segments.size():
		return workout.segments[current_index + 1]
	return null


func target_watts_at(t: float) -> int:
	return int(round(workout.target_fraction_at(t) * ftp * bias / 100.0))


func _is_active() -> bool:
	return state == State.RUNNING or state == State.PAUSED


func _seek(t: float) -> void:
	elapsed = t
	# Drop text events that fall before the new position.
	while _next_event < workout.text_events.size() and workout.text_events[_next_event].time < t:
		_next_event += 1
	var was_paused := state == State.PAUSED
	if was_paused:
		state = State.RUNNING
	advance(0.0)
	if was_paused and state == State.RUNNING:
		state = State.PAUSED


func _fire_events_through(t: float) -> void:
	while _next_event < workout.text_events.size() and workout.text_events[_next_event].time <= t:
		text_event.emit(workout.text_events[_next_event].message)
		_next_event += 1


func _refresh_target() -> void:
	if current_index < 0:
		return
	var t := target_watts_at(elapsed)
	if t != current_target:
		current_target = t
		target_changed.emit(t)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
