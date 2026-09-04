extends Control
## Ride screen, milestone 1: text HUD over nothing. Wires the WorkoutRunner to
## the active trainer and shows what is happening. The 3D scene slots in
## underneath this in milestone 4.

const MESSAGE_SECONDS := 8.0

var _runner: WorkoutRunner
var _recorder: RideRecorder
var _scene: RideScene
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
var _grade_l: Label
var _fps_l: Label
var _bias_l: Label
var _erg_l: Button                 # toggles ERG; reads "ERG on" / "ERG off"
var _message: Label
var _state_l: Label
var _graph: WorkoutGraph
var _start_btn: Button
var _conn_l: Label
var _tuning: TuningPanel
# New HUD pieces
var _finish_l: Label
var _overall_bar: ProgressBar
var _overall_bar2: ProgressBar
var _seg_bar: ProgressBar
var _speed_l: Label
var _dist_l: Label
var _elev_l: Label
var _kj_l: Label
var _reps_l: Label
var _block_name_l: Label
var _block_dur_l: Label
var _rows: Array[PanelContainer] = []
var _groups: Array[Dictionary] = []      # {first, last, ...} segment index ranges
var _start_distance := -1.0
var _elev_gain := 0.0
var _last_h := NAN
var _controls: HBoxContainer
var _coach: CoachDialog
var _hud_root: MarginContainer
var _fade: ColorRect                 # covers the world at start, fades away
var _intro_panels: Array[Control] = []   # top panels that slide in after the world
var _effort_shot_done := false
var _hardest_index := -1
var _controls_idle := 0.0
const CONTROLS_HIDE_AFTER := 3.0


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
	_runner.bias_changed.connect(func(b: int): _bias_l.text = "%d%%" % b)
	_runner.finished.connect(_on_finished)

	_bind_trainer(Devices.trainer)
	_bind_heart_rate(Devices.heart_rate)
	Devices.trainer_changed.connect(_bind_trainer)
	Devices.heart_rate_sensor_changed.connect(_bind_heart_rate)
	_refresh_connection()

	_recorder = RideRecorder.new()
	_recorder.name = "RideRecorder"
	add_child(_recorder)
	_recorder.attach_runner(_runner)
	_runner.state_changed.connect(func(st: WorkoutRunner.State) -> void:
		if st == WorkoutRunner.State.RUNNING and _recorder.ride_id == "" and not App.dry_run:
			_recorder.begin(App.workout.name, App.ftp))
	_runner.load_workout(App.workout, App.ftp)
	# The segment with the highest target gets a screenshot at its midpoint.
	var best := -1.0
	for i in App.workout.segments.size():
		var seg := App.workout.segments[i]
		if seg.has_target() and seg.peak() > best:
			best = seg.peak()
			_hardest_index = i
	_title.text = App.workout.name
	_graph.set_workout(App.workout)
	_intro()
	_on_tick(_runner.snapshot())


## Start of a ride: the world fades in from black, then the HUD arrives, the
## top panels sliding down as they appear. Skipped for tooling renders.
func _intro() -> void:
	if App.dry_run:
		_fade.visible = false
		return
	_hud_root.modulate.a = 0.0
	for p in _intro_panels:
		p.position.y -= 28.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _fade.visible = false)
	tw.tween_property(_hud_root, "modulate:a", 1.0, 0.45).set_ease(Tween.EASE_OUT)
	var slide := create_tween().set_parallel(true)
	for i in _intro_panels.size():
		slide.tween_property(_intro_panels[i], "position:y", _intro_panels[i].position.y + 28.0, 0.5) \
			.set_delay(1.4 + 0.12 * i).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_controls_idle = 0.0


func _process(delta: float) -> void:
	_controls_idle += delta
	var show := _controls_idle < CONTROLS_HIDE_AFTER or _runner.state != WorkoutRunner.State.RUNNING or _tuning.visible
	_controls.modulate.a = move_toward(_controls.modulate.a, 1.0 if show else 0.0, delta * 4.0)
	_controls.mouse_filter = Control.MOUSE_FILTER_STOP if _controls.modulate.a > 0.05 else Control.MOUSE_FILTER_IGNORE


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_SPACE: _runner.toggle_pause()
		KEY_S: _runner.skip_segment()
		KEY_RIGHT: _scene.camera.orbit = wrapf(_scene.camera.orbit + deg_to_rad(15.0), -PI, PI)
		KEY_LEFT: _scene.camera.orbit = wrapf(_scene.camera.orbit - deg_to_rad(15.0), -PI, PI)
		KEY_0: _scene.camera.orbit = 0.0
		KEY_P: _runner.toggle_pause()
		KEY_UP, KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _runner.adjust_bias(5 if event.shift_pressed else 1)
		KEY_DOWN, KEY_MINUS, KEY_KP_SUBTRACT: _runner.adjust_bias(-5 if event.shift_pressed else -1)
		KEY_E: _runner.set_erg(not _runner.erg_enabled)
		KEY_ESCAPE: _runner.end_early()
		KEY_H:
			# Home only when not mid-effort, so a stray key cannot abandon a ride.
			if _runner.state != WorkoutRunner.State.RUNNING:
				App.go_to("res://ui/screens/home_screen.tscn")
		KEY_F:
			_runner.time_scale = 1.0 if _runner.time_scale > 1.0 else 20.0  # dev: fast-forward
			_scene.time_scale = _runner.time_scale
		KEY_T: _tuning.visible = not _tuning.visible


func _bind_trainer(t: Trainer) -> void:
	_trainer = t
	if t == null:
		_refresh_connection()
		return
	t.power_changed.connect(_on_power)
	t.cadence_changed.connect(_on_cadence)
	if _recorder:
		_recorder.attach_trainer(t)
	t.connected.connect(_on_trainer_connected)
	t.disconnected.connect(_refresh_connection)
	t.status_changed.connect(func(_s: String) -> void: _refresh_connection())
	_on_trainer_connected()


func _bind_heart_rate(h: HeartRateSensor) -> void:
	_hr = h
	if h == null:
		_refresh_connection()
		return
	h.heart_rate_changed.connect(_on_bpm)
	if _recorder:
		_recorder.attach_heart_rate(h)
	h.connected.connect(_refresh_connection)
	h.disconnected.connect(_refresh_connection)
	_refresh_connection()


func _on_power(w: int) -> void:
	_actual_power = w
	_power.text = "%d" % w


func _on_cadence(c: int) -> void:
	_cadence = c
	_cadence_l.text = "%d" % c


func _on_bpm(b: int) -> void:
	_bpm = b
	_hr_l.text = "%d" % b


## A trainer that (re)connects mid-ride gets the current target straight away.
func _on_trainer_connected() -> void:
	if _trainer != null and _trainer.is_device_connected() and _runner != null and _runner.current_index >= 0:
		if _runner.erg_enabled and _runner.current_target > 0:
			_trainer.set_target_power(_runner.current_target)
		elif not _runner.erg_enabled:
			_trainer.set_resistance(0.35)
	_refresh_connection()


func _refresh_connection() -> void:
	var problems: Array[String] = []
	if _trainer == null:
		problems.append("No trainer")
	elif not is_instance_valid(_trainer):
		problems.append("Trainer changed")
	elif not _trainer.is_device_connected():
		problems.append("%s disconnected, reconnecting…" % _trainer.display_name())
	if _hr != null and not _hr.is_device_connected():
		problems.append("%s disconnected, reconnecting…" % _hr.display_name())
	_conn_l.text = "  ·  ".join(problems)
	_conn_l.visible = not problems.is_empty()


# --- runner events -----------------------------------------------------------

func _on_tick(snap: Dictionary) -> void:
	_scene.riding = snap.state == WorkoutRunner.State.RUNNING
	_scene.power = float(_actual_power)
	_scene.cadence = float(_cadence)
	_fps_l.text = "%d fps  %.1f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
	var g := _scene.current_grade()
	_grade_l.text = "%s%d%%" % ["▲" if g > 0.5 else ("▼" if g < -0.5 else ""), int(round(absf(g)))]
	_clock.text = _fmt(snap.elapsed)
	_countdown.text = _fmt(snap.segment_remaining)
	_finish_l.text = _fmt(snap.remaining)
	var frac: float = float(snap.elapsed) / maxf(float(snap.total), 1.0)
	_overall_bar.value = frac
	_overall_bar2.value = frac
	var seg := _runner.current_segment()
	_seg_bar.value = (snap.segment_elapsed / maxf(seg.duration, 1.0)) if seg else 0.0
	_graph.set_progress(snap.elapsed, snap.bias)
	if not _effort_shot_done and snap.segment_index == _hardest_index and seg and snap.segment_elapsed >= seg.duration * 0.5:
		_effort_shot_done = true
		_capture_screenshot("effort")
	# Trip numbers from the scene: speed, distance ridden, climbing.
	_speed_l.text = App.speed_text(_scene.physics.speed)
	if _start_distance < 0.0:
		_start_distance = _scene.distance
	_dist_l.text = App.distance_text(_scene.distance - _start_distance)
	var h := _scene.trail.h_at(_scene.distance)
	if not is_nan(_last_h) and snap.state == WorkoutRunner.State.RUNNING and h > _last_h:
		_elev_gain += h - _last_h
	_last_h = h
	_elev_l.text = "%d" % int(_elev_gain)
	_kj_l.text = "%d" % int(_total_kj)
	# One-second bookkeeping for the summary.
	if snap.state == WorkoutRunner.State.RUNNING and floorf(snap.elapsed) != _last_sample_time:
		_last_sample_time = floorf(snap.elapsed)
		_power_samples.append(_actual_power)
		_total_kj += _actual_power / 1000.0
		_graph.add_heart_rate(snap.elapsed, _bpm)


func _on_segment(i: int, s: WorkoutSegment) -> void:
	_block_name_l.text = _block_title(s)
	_block_dur_l.text = "FOR %s" % HudStyle.duration(s.duration)
	_segment.text = s.label() + ("  ·  %d rpm" % s.cadence if s.cadence > 0 else "")
	for gi in _groups.size():
		var g := _groups[gi]
		var active: bool = i >= int(g.first) and i <= int(g.last)
		_style_row(_rows[gi], active)
	_update_reps(i)


func _block_title(s: WorkoutSegment) -> String:
	match s.kind:
		WorkoutSegment.Kind.WARMUP: return "WARM UP"
		WorkoutSegment.Kind.COOLDOWN: return "COOL DOWN"
		WorkoutSegment.Kind.STEADY: return "STEADY"
		WorkoutSegment.Kind.RAMP: return "RAMP"
		WorkoutSegment.Kind.INTERVAL_ON: return "REP %d OF %d" % [s.rep, s.rep_count]
		WorkoutSegment.Kind.INTERVAL_OFF: return "RECOVER"
		WorkoutSegment.Kind.FREE_RIDE: return "FREE RIDE"
		WorkoutSegment.Kind.MAX_EFFORT: return "MAX EFFORT"
	return "RIDE"


func _update_reps(current_index: int) -> void:
	var total := 0
	var done := 0
	for i in App.workout.segments.size():
		var seg := App.workout.segments[i]
		if seg.kind == WorkoutSegment.Kind.INTERVAL_ON:
			total += 1
			if i < current_index:
				done += 1
	_reps_l.text = "★ %d/%d" % [done, total] if total > 0 else ""


func _on_target(w: int) -> void:
	_target.text = ("%dw" % w) if w > 0 else "free"
	if _trainer and _runner.erg_enabled and w > 0:
		_trainer.set_target_power(w)
	elif _trainer and w == 0:
		_trainer.set_resistance(0.3)


func _on_text(msg: String) -> void:
	_coach.say(msg)


func _on_state(s: WorkoutRunner.State) -> void:
	_state_l.text = "" if s == WorkoutRunner.State.RUNNING else WorkoutRunner.State.keys()[s].capitalize()
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
	if _recorder.ride_id != "":
		_recorder.finish(completed)
		await _capture_screenshot("finish")
		_finalize_ride()
	var avg := 0
	if _power_samples.size() > 0:
		var sum := 0
		for p in _power_samples:
			sum += p
		avg = int(float(sum) / _power_samples.size())
	_coach.say("%s  ·  avg %d W  ·  %d kJ" % [
		"Workout complete" if completed else "Ended early", avg, int(_total_kj)], 0.0)
	_start_btn.disabled = true
	_block_name_l.text = "DONE"
	_block_dur_l.text = ""


## Save a clean scene screenshot (HUD hidden for one frame) beside the ride files.
func _capture_screenshot(tag: String) -> void:
	if _recorder == null or _recorder.ride_id == "":
		return
	var was_hud := _hud_root.visible
	var was_coach := _coach.visible
	_hud_root.visible = false
	_coach.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_hud_root.visible = was_hud
	_coach.visible = was_coach
	var path := RideRecorder.RIDES_DIR.path_join("%s-%s.png" % [_recorder.ride_id, tag])
	img.save_png(ProjectSettings.globalize_path(path))


## Target as a fraction of FTP at a point `metres_ahead` up the trail, for the
## terrain generator: hard efforts become climbs, recoveries descents.
func _target_fraction_ahead(metres_ahead: float) -> Variant:
	if _runner == null or _runner.workout == null:
		return null
	# Predict arrival with a smoothed speed, and lead the profile so the grade
	# has already ramped when the interval begins (the ramp takes ~6 m).
	const LEAD_SECONDS := 4.0
	var speed := maxf(_scene.avg_speed, 3.0)
	var t := _runner.elapsed + metres_ahead / speed + LEAD_SECONDS
	if t >= _runner.workout.total_duration():
		return 0.6
	return _runner.workout.target_fraction_at(t)


## Encode the FIT file, queue the upload, and show the summary.
func _finalize_ride() -> void:
	var metrics := RideMetrics.compute(_recorder.samples, App.ftp)
	if _recorder.samples.size() > 0:
		var bytes := FitEncoder.encode(_recorder.meta, _recorder.samples, metrics, true)
		var f := FileAccess.open(_recorder.fit_path(), FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
	# Sharing is confirmed on the summary screen, never automatic.
	App.last_ride_journal = _recorder.journal_path()
	App.prompt_upload = true
	_coach.say(_coach.label.text + "   → Summary", 0.0)
	get_tree().create_timer(1.5).timeout.connect(func() -> void: App.go_to("res://ui/screens/summary_screen.tscn"))


# --- UI ---------------------------------------------------------------------

func _fmt(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


func _build_ui() -> void:
	_scene = RideScene.new()
	_scene.name = "RideScene"
	_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scene)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.04, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_scene.target_fraction_ahead = _target_fraction_ahead
	_tuning = TuningPanel.new()
	_tuning.scene = _scene
	_tuning.visible = false
	_tuning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_tuning.position = Vector2(size.x - 560, 80)
	_tuning.custom_minimum_size = Vector2(540, 0)
	_tuning.modulate = Color(1, 1, 1, 0.92)
	add_child(_tuning)
	_tuning.z_index = 10

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	_hud_root = margin
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	# ---- top area: workout panel anchored left, telemetry panel centred on the page ----
	var top := Control.new()
	top.custom_minimum_size.y = 300
	v.add_child(top)
	var left := _build_workout_panel(top)
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var tele := _build_telemetry_panel(top)
	_intro_panels = [left, tele]
	tele.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tele.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tele.grow_vertical = Control.GROW_DIRECTION_END
	tele.resized.connect(func() -> void: tele.position.x = (top.size.x - tele.size.x) * 0.5)
	top.resized.connect(func() -> void: tele.position.x = (top.size.x - tele.size.x) * 0.5)

	_conn_l = HudStyle.label(v, "", 18, 700, Color(1.0, 0.55, 0.45))
	_conn_l.visible = false
	# Hidden legacy labels that the runner handlers still write to.
	_segment = Label.new(); _segment.visible = false; v.add_child(_segment)
	_next = Label.new(); _next.visible = false; v.add_child(_next)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the workout panel's footer hangs into this area
	v.add_child(spacer)

	# Coach notes: centred dialog with portrait (see CoachDialog). Added last so it draws on top.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_coach = CoachDialog.new()
	_coach.name = "CoachDialog"
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_coach)
	_message = _coach.label

	# ---- controls just above the plan graph: hidden while riding, shown when the mouse moves ----
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_controls = bar
	_controls.modulate.a = 0.0
	_start_btn = HudStyle.button(bar, "Start", 16, func(): _runner.toggle_pause())
	HudStyle.button(bar, "Skip", 16, func(): _runner.skip_segment())
	_erg_l = HudStyle.button(bar, "ERG on", 16, func(): _runner.set_erg(not _runner.erg_enabled))
	_state_l = HudStyle.label(bar, "", 14, 600, HudStyle.TEXT_DIM)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	# FPS readout lives in the top-right corner of the screen, outside the HUD layout.
	_fps_l = HudStyle.label(self, "— fps", 14, 500, Color(0.75, 1.0, 0.75, 0.85))
	_fps_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_l.offset_right = -14.0
	_fps_l.offset_top = 8.0
	_fps_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_l.visible = App.show_fps
	HudStyle.button(bar, "End", 16, func(): _runner.end_early())
	HudStyle.button(bar, "Home", 16, func(): App.go_to("res://ui/screens/home_screen.tscn"))

	_graph = WorkoutGraph.new()
	_graph.custom_minimum_size.y = 70
	v.add_child(_graph)


## Top-left: workout name, overall progress, finish time, block list, bias, reps.
func _build_workout_panel(parent: Control) -> PanelContainer:
	var panel := HudStyle.panel(parent, HudStyle.PANEL, 10, 14)
	panel.custom_minimum_size.x = 300
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_title = HudStyle.label(v, App.workout.name, 20, 700)
	_title.custom_minimum_size.x = 270
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_overall_bar = HudStyle.bar(v, 12, 6)
	var fin := HBoxContainer.new()
	fin.alignment = BoxContainer.ALIGNMENT_END
	fin.add_theme_constant_override("separation", 8)
	v.add_child(fin)
	var fin_l := HudStyle.label(fin, "Finish in", 20, 700, HudStyle.TEXT_DIM)
	_finish_l = HudStyle.label(fin, _fmt(App.workout.total_duration()), 26, 900)
	HudStyle.share_baseline(fin, _finish_l, fin_l)

	_groups = WorkoutSummary.rows(App.workout, App.ftp)
	_rows.clear()
	for g in _groups:
		_rows.append(HudStyle.block_row(v, g))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	v.add_child(foot)
	HudStyle.button(foot, "−", 20, func(): _runner.adjust_bias(-1))
	_bias_l = HudStyle.label(foot, "100%", 20, 700)
	HudStyle.button(foot, "+", 20, func(): _runner.adjust_bias(1))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_reps_l = HudStyle.label(foot, "", 20, 700, Color(1.0, 0.85, 0.3))
	_update_reps(-1)
	return panel


func _style_row(row: PanelContainer, active: bool) -> void:
	HudStyle.style_block_row(row, HudStyle.ACCENT if active else row.get_meta("bg", HudStyle.PANEL_ROW))


## Top-centre: trip numbers, progress, current block, power, live metrics.
func _build_telemetry_panel(parent: Control) -> PanelContainer:
	var panel := HudStyle.panel(parent, HudStyle.PANEL, 10, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var trip := HBoxContainer.new()
	trip.add_theme_constant_override("separation", 30)
	v.add_child(trip)
	_speed_l = _metric(trip, "0", App.speed_unit())
	_dist_l = _metric(trip, "0.0", App.distance_unit())
	_elev_l = _metric(trip, "0", "M")
	_clock = _metric(trip, "0:00", "ET")
	_overall_bar2 = HudStyle.bar(v, 8, 4)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	v.add_child(body)
	# Current block box
	var block := HudStyle.panel(body, Color(0.55, 0.57, 0.63, 0.55), 8, 12)
	block.custom_minimum_size = Vector2(190, 0)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", 0)
	block.add_child(bv)
	_block_name_l = HudStyle.label(bv, "READY", 20, 700)
	_block_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target = HudStyle.label(bv, "—", 44, 900)
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_dur_l = HudStyle.label(bv, "", 18, 700)
	_block_dur_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Segment progress and power
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(mid)
	var seg_stack := Control.new()
	seg_stack.custom_minimum_size.y = 30
	mid.add_child(seg_stack)
	_seg_bar = HudStyle.bar(seg_stack, 30, 8, Color(0.2, 0.22, 0.3, 0.95))
	_seg_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown = HudStyle.label(seg_stack, "0:00", 22, 700)
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", 6)
	mid.add_child(prow)
	_power = HudStyle.label(prow, "—", 96, 900)
	var wl := HudStyle.label(prow, "w", 36, 700)
	HudStyle.share_baseline(prow, _power, wl)
	# Right column of live metrics
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	body.add_child(col)
	_cadence_l = _side_metric(col, "—", "rpm")
	_hr_l = _side_metric(col, "—", "bpm")
	_grade_l = _side_metric(col, "0%", "grade")
	_kj_l = _side_metric(col, "0", "kJ")
	return panel


func _metric(parent: Control, value: String, unit: String) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 40, 900)
	var u := HudStyle.label(h, unit, 17, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)
	return val


func _side_metric(parent: Control, value: String, unit: String) -> Label:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 26, 700)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = 70
	var u := HudStyle.label(h, unit, 16, 700, HudStyle.TEXT_DIM)
	u.custom_minimum_size.x = 56
	HudStyle.share_baseline(h, val, u)
	return val


func _label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.14, 0.9))
	l.add_theme_constant_override("outline_size", maxi(int(font_size / 8), 2))
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
