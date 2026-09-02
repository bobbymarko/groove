extends Control
## Ride screen, milestone 1: text HUD over nothing. Wires the WorkoutRunner to
## the active trainer and shows what is happening. The 3D scene slots in
## underneath this in milestone 4.

const MESSAGE_SECONDS := 8.0

var _runner: WorkoutRunner
var _trainer: Trainer
var _hr: HeartRateSensor

var _power_samples: Array[int] = []
var _actual_power := 0
var _cadence := 0
var _bpm := 0
var _message_until := 0.0
var _total_kj := 0.0
var _last_sample_time := -1.0

# UI
var _title: Label
var _clock: Label
var _segment: Label
var _countdown: Label
var _next: Label
var _target: Label
var _power: Label
var _cadence_l: Label
var _hr_l: Label
var _bias_l: Label
var _erg_l: Label
var _message: Label
var _state_l: Label
var _graph: WorkoutGraph
var _start_btn: Button
var _conn_l: Label


func _ready() -> void:
	_build_ui()
	_runner = WorkoutRunner.new()
	_runner.name = "WorkoutRunner"
	add_child(_runner)
	_runner.ticked.connect(_on_tick)
	_runner.segment_changed.connect(_on_segment)
	_runner.target_changed.connect(_on_target)
	_runner.text_event.connect(_on_text)
	_runner.state_changed.connect(_on_state)
	_runner.erg_changed.connect(_on_erg)
	_runner.bias_changed.connect(func(b: int): _bias_l.text = "Bias %d%%" % b)
	_runner.finished.connect(_on_finished)

	_trainer = Devices.trainer
	_hr = Devices.heart_rate
	if _trainer:
		_trainer.power_changed.connect(func(w: int): _actual_power = w; _power.text = "%d" % w)
		_trainer.cadence_changed.connect(func(c: int): _cadence = c; _cadence_l.text = "%d rpm" % c)
		_trainer.connected.connect(_refresh_connection)
		_trainer.disconnected.connect(_refresh_connection)
		_trainer.status_changed.connect(func(_s: String) -> void: _refresh_connection())
	if _hr:
		_hr.connected.connect(_refresh_connection)
		_hr.disconnected.connect(_refresh_connection)
	_refresh_connection()
	if _hr:
		_hr.heart_rate_changed.connect(func(b: int): _bpm = b; _hr_l.text = "%d bpm" % b)

	_runner.load_workout(App.workout, App.ftp)
	_title.text = App.workout.name
	_graph.set_workout(App.workout)
	_on_tick(_runner.snapshot())


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_SPACE: _runner.toggle_pause()
		KEY_RIGHT: _runner.skip_segment()
		KEY_UP: _runner.adjust_bias(1)
		KEY_DOWN: _runner.adjust_bias(-1)
		KEY_E: _runner.set_erg(not _runner.erg_enabled)
		KEY_ESCAPE: _runner.end_early()
		KEY_F: _runner.time_scale = 1.0 if _runner.time_scale > 1.0 else 20.0  # dev: fast-forward


func _refresh_connection() -> void:
	var problems: Array[String] = []
	if _trainer == null:
		problems.append("No trainer")
	elif not _trainer.is_device_connected():
		problems.append("%s disconnected, reconnecting…" % _trainer.display_name())
	if _hr != null and not _hr.is_device_connected():
		problems.append("%s disconnected, reconnecting…" % _hr.display_name())
	_conn_l.text = "  ·  ".join(problems)
	_conn_l.visible = not problems.is_empty()


# --- runner events -----------------------------------------------------------

func _on_tick(snap: Dictionary) -> void:
	_clock.text = "%s  /  %s" % [_fmt(snap.elapsed), _fmt(snap.total)]
	_countdown.text = _fmt(snap.segment_remaining)
	_graph.set_progress(snap.elapsed, snap.bias)
	if _message_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _message_until:
		_message.text = ""
		_message_until = 0.0
	# One-second bookkeeping for the summary.
	if snap.state == WorkoutRunner.State.RUNNING and floorf(snap.elapsed) != _last_sample_time:
		_last_sample_time = floorf(snap.elapsed)
		_power_samples.append(_actual_power)
		_total_kj += _actual_power / 1000.0


func _on_segment(_i: int, s: WorkoutSegment) -> void:
	_segment.text = s.label() + ("  ·  %d rpm" % s.cadence if s.cadence > 0 else "")
	var n := _runner.next_segment()
	_next.text = ("Next: %s, %s" % [n.label(), _fmt(n.duration)]) if n else "Last segment"


func _on_target(w: int) -> void:
	_target.text = "Target %d W" % w if w > 0 else "No target"
	if _trainer and _runner.erg_enabled and w > 0:
		_trainer.set_target_power(w)
	elif _trainer and w == 0:
		_trainer.set_resistance(0.3)


func _on_text(msg: String) -> void:
	_message.text = msg
	_message_until = Time.get_ticks_msec() / 1000.0 + MESSAGE_SECONDS


func _on_state(s: WorkoutRunner.State) -> void:
	_state_l.text = WorkoutRunner.State.keys()[s].capitalize()
	_start_btn.text = {
		WorkoutRunner.State.READY: "Start",
		WorkoutRunner.State.RUNNING: "Pause",
		WorkoutRunner.State.PAUSED: "Resume",
	}.get(s, "Done")


func _on_erg(enabled: bool) -> void:
	_erg_l.text = "ERG on" if enabled else "ERG off"
	if _trainer:
		if enabled:
			_trainer.set_target_power(_runner.current_target)
		else:
			_trainer.set_resistance(0.35)


func _on_finished(completed: bool) -> void:
	if _trainer:
		_trainer.set_target_power(0)
	var avg := 0
	if _power_samples.size() > 0:
		var sum := 0
		for p in _power_samples:
			sum += p
		avg = int(float(sum) / _power_samples.size())
	_message.text = "%s  ·  avg %d W  ·  %d kJ" % [
		"Workout complete" if completed else "Ended early", avg, int(_total_kj)]
	_message_until = 0.0
	_start_btn.disabled = true


# --- UI ---------------------------------------------------------------------

func _fmt(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	_title = _label(top, "", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_l = _label(top, "Ready", 20)
	_clock = _label(top, "0:00 / 0:00", 20)

	_conn_l = _label(v, "", 18)
	_conn_l.modulate = Color(1.0, 0.55, 0.45)
	_conn_l.visible = false
	_segment = _label(v, "", 26)
	_next = _label(v, "", 16)
	_next.modulate = Color(1, 1, 1, 0.6)

	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 48)
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	var pcol := VBoxContainer.new()
	pcol.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(pcol)
	_power = _label(pcol, "—", 120)
	_power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target = _label(pcol, "Target — W", 32)
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scol := VBoxContainer.new()
	scol.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(scol)
	_countdown = _label(scol, "0:00", 64)
	_cadence_l = _label(scol, "— rpm", 32)
	_hr_l = _label(scol, "— bpm", 32)

	_message = _label(v, "", 22)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 60
	_message.modulate = Color(1.0, 0.9, 0.6)

	_graph = WorkoutGraph.new()
	_graph.custom_minimum_size.y = 90
	v.add_child(_graph)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_start_btn = _button(bar, "Start", func(): _runner.toggle_pause())
	_button(bar, "Skip ›", func(): _runner.skip_segment())
	_button(bar, "Bias −", func(): _runner.adjust_bias(-1))
	_bias_l = _label(bar, "Bias 100%", 16)
	_button(bar, "Bias +", func(): _runner.adjust_bias(1))
	_erg_l = _label(bar, "ERG on", 16)
	_button(bar, "Toggle ERG", func(): _runner.set_erg(not _runner.erg_enabled))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_button(bar, "End", func(): _runner.end_early())
	_button(bar, "Home", func(): App.go_to("res://ui/screens/home_screen.tscn"))


func _label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
