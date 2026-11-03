class_name CampRide
extends Node3D
## A Camp training session: Groove's workout runner, trainer control and ride
## recording, played as a side-scroller over the workout's power profile.
## You forage as you ride; the trader pays for the basket at the end.
##
## User args: sim (default) or real; workout=<path>. For tooling:
## autostart, and speed=N to run the workout clock N times faster (sim only).

const DEFAULT_WORKOUT := "res://workouts/vo2_5x4.zwo"
const BASKET_OFFSET := Vector3(-0.3, 1.25, 0.0)   ## where finds fly to, rider space

var _runner: WorkoutRunner
var _recorder: RideRecorder
var _trainer: Trainer
var _hr_sensor: HeartRateSensor
var _trail: PowerTrail
var _world: TrailWorld
var _rider: MonsterRider
var _cam: Camera3D
var _hud: CampRideHud
var _forage := Forage.new()
var _finds: Array[Dictionary] = []
var _next_spawn := 0
var _live: Array[Dictionary] = []       # spawned, unresolved finds
var _critter: Dictionary = {}           # the running critter, if any
var _power := 0.0
var _cadence := 0
var _bpm := 0
var _last_second := -1
var _last_x := 0.0
var _sim := true
var _sim_offset := 0.0
var _skipped_segment := -1
var _workout_path := DEFAULT_WORKOUT


func _ready() -> void:
	var picked := false
	for a in OS.get_cmdline_user_args():
		if a == "real":
			_sim = false
		elif a.begins_with("workout="):
			_workout_path = a.trim_prefix("workout=")
			picked = true
	var w := App.workout
	if w == null or picked:
		w = WorkoutLoader.load_file(_workout_path, App.ftp)
	App.workout = w
	if _sim:
		App.dry_run = true        # practice rides never land in the ride library
		Devices.use_simulated_devices()
	_forage.ftp = App.ftp
	CampWorld.dusk(self)
	_trail = PowerTrail.new(w)
	_finds = _trail.finds()
	_world = TrailWorld.new()
	add_child(_world)
	_world.setup(_trail)
	_rider = MonsterRider.new()
	_rider.recipe = CampSave.load_rider()
	add_child(_rider)
	_cam = Camera3D.new()
	_cam.fov = 32
	add_child(_cam)
	_hud = CampRideHud.new()
	add_child(_hud)
	_hud.action.connect(_on_action)
	_hud.graph.set_workout(w)

	# Same order as Groove: the recorder exists before devices are bound.
	_runner = WorkoutRunner.new()
	add_child(_runner)
	_runner.ticked.connect(_on_tick)
	_runner.target_changed.connect(_send_target)
	_runner.segment_changed.connect(_on_segment)
	_runner.text_event.connect(func(m: String) -> void: _hud.say(m))
	_runner.erg_changed.connect(_on_erg)
	_runner.finished.connect(_on_finished)
	_runner.state_changed.connect(_on_state)
	_runner.load_workout(w, App.ftp)
	_recorder = RideRecorder.new()
	add_child(_recorder)
	_recorder.attach_runner(_runner)
	_bind_trainer(Devices.trainer)
	_bind_heart_rate(Devices.heart_rate)
	Devices.trainer_changed.connect(_bind_trainer)
	Devices.heart_rate_sensor_changed.connect(_bind_heart_rate)
	_runner.auto_pause = App.auto_pause and not _sim

	_hud.set_band("ready")
	var est := WorkoutSummary.estimates(w, App.ftp)
	_hud.show_start(w.name, "%s at %d W FTP, about %d TSS. Stay in the band to forage; harder blocks grow rarer finds.%s" % [
		WorkoutSummary.duration(w.total_duration()), App.ftp, int(round(est.tss)),
		"\nSimulator ride: nothing is recorded." if _sim else ""])
	_hud.set_hint(_hint_text())
	_place(0.0, 0.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("speed=") and _sim:
			_runner.time_scale = float(a.trim_prefix("speed="))
	if OS.get_cmdline_user_args().has("autostart"):
		_autostart.call_deferred()


## Tooling: start now, optionally from a later point (start=SECONDS).
func _autostart() -> void:
	_runner.toggle_pause()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("start="):
			_runner.advance(float(a.trim_prefix("start=")))


func _hint_text() -> String:
	var t := "Space pause   S skip   ↑↓ bias   E erg   Esc end"
	if _sim:
		t += "      Simulator:  [ ] effort   Q stop pedalling   F fast"
	return t


# ------------------------------------------------------------------ devices

func _bind_trainer(t: Trainer) -> void:
	if _trainer and is_instance_valid(_trainer):
		for sig in [["power_changed", _on_power], ["cadence_changed", _on_cadence]]:
			if _trainer.is_connected(sig[0], sig[1]):
				_trainer.disconnect(sig[0], sig[1])
	_trainer = t
	if t == null:
		return
	t.power_changed.connect(_on_power)
	t.cadence_changed.connect(_on_cadence)
	_recorder.attach_trainer(t)
	if _runner.state == WorkoutRunner.State.RUNNING:
		_send_target(_runner.current_target)


func _bind_heart_rate(h: HeartRateSensor) -> void:
	_hr_sensor = h
	if h == null:
		return
	h.heart_rate_changed.connect(func(b: int) -> void: _bpm = b)
	_recorder.attach_heart_rate(h)


func _on_power(w: int) -> void:
	_power = w
	_runner.report_power(w)


func _on_cadence(c: int) -> void:
	_cadence = c


## The simulator can be pushed off target with [ and ] to try the band.
func _send_target(w: float) -> void:
	if _trainer == null or not _runner.erg_enabled:
		return
	if w > 0:
		_trainer.set_target_power(int(round(w * (1.0 + _sim_offset))) if _sim else int(round(w)))
	else:
		_trainer.set_resistance(0.3)


func _on_erg(enabled: bool) -> void:
	if _trainer == null:
		return
	if enabled:
		_send_target(_runner.current_target)
	else:
		_trainer.set_resistance(0.35)


# ------------------------------------------------------------------ ride

func _on_state(st: int) -> void:
	if st == WorkoutRunner.State.RUNNING:
		_hud.hide_card()
		if _recorder.ride_id == "" and not App.dry_run:
			_recorder.begin(App.workout.name, App.ftp)


func _on_tick(snap: Dictionary) -> void:
	var sec := int(floor(float(snap.elapsed)))
	if sec != _last_second:
		_last_second = sec
		var seg := _runner.current_segment()
		var max_effort := seg != null and seg.kind == WorkoutSegment.Kind.MAX_EFFORT
		_forage.add_second(_power, _runner.current_target, max_effort)
		_hud.graph.add_power(float(snap.elapsed), _power / maxf(App.ftp, 1))
	_hud.graph.set_progress(float(snap.elapsed), _runner.bias)


func _on_segment(index: int, _s: WorkoutSegment) -> void:
	_resolve_segment_finds(index - 1 if index > 0 else -1)
	_forage.start_segment()
	if _sim and _trainer is SimulatedTrainer and _s:
		(_trainer as SimulatedTrainer).target_cadence = _s.cadence


func _process(dt: float) -> void:
	var running := _runner.state == WorkoutRunner.State.RUNNING
	var x := _runner.elapsed * PowerTrail.SCROLL
	_rider.cadence = float(_cadence) if running else 0.0
	_rider.speed = PowerTrail.SCROLL if running else 0.0
	_rider.advance(dt)
	_place(x, dt)
	_world.update(x, _cam.position.x)
	_spawn_ahead(x)
	_pass_finds(x)
	_move_critter(x, dt)
	_last_x = x
	var seg := _runner.current_segment()
	var seg_left := 0.0
	if seg:
		seg_left = _runner.workout.segment_end(_runner.current_index) - _runner.elapsed
	_hud.set_numbers(_power, _runner.current_target, _cadence, _bpm, seg_left)
	if _runner.state == WorkoutRunner.State.FINISHED:
		_hud.set_band("done")
	elif _runner.state == WorkoutRunner.State.PAUSED:
		_hud.set_band("paused")
	elif running:
		_hud.set_band(_forage.band(_runner.current_target))
	_hud.set_basket(_forage.basket, _forage.value())


func _place(x: float, dt: float) -> void:
	var y := _trail.height_at(x)
	_rider.position = Vector3(x, y, 0)
	_rider.rotation.z = _trail.slope_at(x) * 0.8
	# Rider on the left third, the trail ahead filling the frame.
	var want := Vector3(x + 4.4, y + 2.1, 13.0)
	if dt <= 0.0:
		_cam.position = want
	else:
		_cam.position.x = want.x
		_cam.position.y = lerpf(_cam.position.y, want.y, 1.0 - exp(-dt * 2.5))
		_cam.position.z = want.z
	_cam.look_at(_cam.position + Vector3(0, -0.75, -13.0))


# ------------------------------------------------------------------ finds

func _spawn_ahead(x: float) -> void:
	while _next_spawn < _finds.size() and float(_finds[_next_spawn].x) < x + 30.0:
		var f := _finds[_next_spawn]
		_next_spawn += 1
		if float(f.x) < x - 1.0:
			continue
		var fx := float(f.x)
		match str(f.kind):
			PowerTrail.BERRY:
				f["node"] = _spawn_prop("bush_berry", Vector3(fx, _trail.height_at(fx), -1.05), 0.85)
			PowerTrail.FLOWER:
				f["node"] = _spawn_prop("flower_patch", Vector3(fx, _trail.height_at(fx), 0.95), 1.0)
			PowerTrail.HONEY:
				f["node"] = _spawn_prop("beehive", Vector3(fx + 2.0, _trail.height_at(fx + 2.0), -1.3), 1.0)
			PowerTrail.CRITTER:
				pass      # released when the segment starts
		_live.append(f)


func _spawn_prop(kind: String, at: Vector3, s: float) -> Node3D:
	var n := PartKit.prop("nature", kind)
	n.position = at
	n.scale = Vector3.ONE * s
	n.rotation.y = randf() * TAU
	add_child(n)
	CampLook.paint(n, {})
	return n


func _pass_finds(x: float) -> void:
	var jumped := x - _last_x > 6.0         # a skip: what you jump over just withers
	for f in _live.duplicate():
		var kind := str(f.kind)
		if kind == PowerTrail.CRITTER:
			if not f.has("node") and _runner.current_index == int(f.segment) and _runner.state == WorkoutRunner.State.RUNNING:
				_release_critter(f, x)
			continue
		if kind == PowerTrail.HONEY or float(f.x) > x:
			continue
		_live.erase(f)
		var node: Node3D = f.get("node")
		if node == null:
			continue
		if jumped:
			CampLook.paint(node, {"berry": CampLook.ROLES.leaf_dark, "petal": Color("6b6b5a"), "petal2": Color("6b6b5a")})
			continue
		if _forage.in_band(_runner.current_target):
			_forage.add(kind, 1, _runner.bias, _runner.current_target / maxf(App.ftp, 1))
			_fly_from(node, kind)
		else:
			_shake(node)


## Berries or petals arc from the bush into the rider's basket.
func _fly_from(node: Node3D, kind: String) -> void:
	var colour: Color = CampLook.ROLES.berry if kind == PowerTrail.BERRY else CampLook.ROLES.petal
	CampLook.paint(node, {"berry": CampLook.ROLES.leaf_dark, "petal": CampLook.ROLES.leaf, "petal2": CampLook.ROLES.leaf})
	for i in (5 if kind == PowerTrail.BERRY else 4):
		var bit := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 6
		sm.rings = 3
		bit.mesh = sm
		bit.material_override = CampLook.material(colour, 0.35)
		add_child(bit)
		var start := node.global_position + Vector3(randf_range(-0.2, 0.2), 0.35 + randf() * 0.2, randf_range(-0.1, 0.1))
		bit.global_position = start
		var tw := create_tween()
		var dur := 0.45 + i * 0.05
		tw.tween_method(func(t: float) -> void:
			if not is_instance_valid(bit):
				return
			var target := _rider.global_position + BASKET_OFFSET
			var p := start.lerp(target, t)
			p.y += sin(t * PI) * 0.8
			bit.global_position = p
			bit.scale = Vector3.ONE * (1.0 - t * 0.6), 0.0, 1.0, dur).set_delay(i * 0.04)
		tw.tween_callback(bit.queue_free)


func _shake(node: Node3D) -> void:
	var tw := create_tween()
	var r := node.rotation
	for i in 4:
		tw.tween_property(node, "rotation", r + Vector3(0.12 * (1 if i % 2 == 0 else -1), 0, 0), 0.06)
	tw.tween_property(node, "rotation", r, 0.06)


## A critter darts out ahead at the start of a hard interval and runs with you.
func _release_critter(f: Dictionary, x: float) -> void:
	var n := _spawn_prop("rabbit", Vector3(x + 3.2, _trail.height_at(x + 3.2), 0.45), 1.1)
	n.rotation.y = 0.0
	f["node"] = n
	_critter = f


func _move_critter(x: float, dt: float) -> void:
	if _critter.is_empty() or not _critter.has("node"):
		return
	var n: Node3D = _critter.node
	if not is_instance_valid(n):
		_critter = {}
		return
	var cx := x + 3.0 + sin(_runner.elapsed * 0.7) * 0.6
	var hop := absf(sin(_runner.elapsed * 7.0)) * 0.22
	n.position = Vector3(cx, _trail.height_at(cx) + hop, 0.45)


## When a segment ends, settle its critter and honey.
func _resolve_segment_finds(seg_index: int) -> void:
	if seg_index < 0:
		return
	var skipped := seg_index == _skipped_segment
	for f in _live.duplicate():
		if int(f.segment) != seg_index:
			continue
		var kind := str(f.kind)
		if kind == PowerTrail.CRITTER:
			_live.erase(f)
			var n: Node3D = f.get("node")
			_critter = {}
			if n == null:
				continue
			if not skipped and _forage.critter_caught():
				_forage.add("critter", 1, _runner.bias)
				_catch(n)
			else:
				_run_off(n)
		elif kind == PowerTrail.HONEY:
			_live.erase(f)
			var honey := 0 if skipped else _forage.honey_earned()
			if honey > 0:
				_forage.add("honey", honey, _runner.bias)
				var hive: Node3D = f.get("node")
				if hive:
					_fly_from(hive, PowerTrail.FLOWER)


func _catch(n: Node3D) -> void:
	var tw := create_tween()
	var start := n.global_position
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(n):
			return
		var target := _rider.global_position + BASKET_OFFSET
		var p := start.lerp(target, t)
		p.y += sin(t * PI) * 1.4
		n.global_position = p
		n.scale = Vector3.ONE * 1.1 * (1.0 - t * 0.7), 0.0, 1.0, 0.7)
	tw.tween_callback(n.queue_free)
	_hud.say("Caught one!")


func _run_off(n: Node3D) -> void:
	n.rotation.y = PI * 0.5            # turn and bolt for the trees
	var tw := create_tween()
	tw.tween_property(n, "position", n.position + Vector3(2.0, 0, -7.0), 1.1)
	tw.tween_callback(n.queue_free)
	_hud.say("It got away. Hold the whole interval next time.")


# ------------------------------------------------------------------ finish

func _on_finished(completed: bool) -> void:
	_resolve_segment_finds(_runner.current_index)
	if _trainer:
		_trainer.set_target_power(0)
	var recorded := not App.dry_run and _recorder.ride_id != ""
	var tss := 0.0
	if recorded:
		_recorder.finish(completed)
		var metrics := RideMetrics.compute(_recorder.samples, App.ftp)
		tss = float(metrics.get("tss", 0.0))
		var bytes := FitEncoder.encode(_recorder.meta, _recorder.samples, metrics, true)
		var f := FileAccess.open(_recorder.fit_path(), FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
		App.last_ride_journal = _recorder.journal_path()
		App.prompt_upload = true
	else:
		var est := WorkoutSummary.estimates(_runner.workout, App.ftp)
		tss = float(est.tss) * clampf(_runner.elapsed / maxf(_runner.workout.total_duration(), 1.0), 0.0, 1.0)
	var haul := _forage.value()
	_hud.show_tally(_forage.basket, haul, tss, Forage.coins(haul, tss), recorded)


func _on_action(id: String) -> void:
	match id:
		"start":
			if _runner.state == WorkoutRunner.State.READY:
				_runner.toggle_pause()
		"again":
			App.go_to("res://camp/ride/camp_ride.tscn")
		"summary":
			App.go_to("res://ui/screens/summary_screen.tscn")
		"camp":
			App.go_to("res://camp/lab/lab_viewer.tscn")


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).keycode
	var shift := (e as InputEventKey).shift_pressed
	match k:
		KEY_SPACE, KEY_P:
			if _runner.state != WorkoutRunner.State.FINISHED:
				_runner.toggle_pause()
		KEY_S:
			_skipped_segment = _runner.current_index
			_runner.skip_segment()
		KEY_UP, KEY_EQUAL, KEY_KP_ADD:
			_runner.adjust_bias(5 if shift else 1)
		KEY_DOWN, KEY_MINUS, KEY_KP_SUBTRACT:
			_runner.adjust_bias(-5 if shift else -1)
		KEY_E:
			_runner.set_erg(not _runner.erg_enabled)
		KEY_ESCAPE:
			if _runner.state in [WorkoutRunner.State.RUNNING, WorkoutRunner.State.PAUSED]:
				_runner.end_early()
		KEY_F:
			if _sim:
				_runner.time_scale = 1.0 if _runner.time_scale > 1.0 else 20.0
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if _sim:
				_sim_offset = clampf(_sim_offset + (-0.1 if k == KEY_BRACKETLEFT else 0.1), -0.5, 0.4)
				_send_target(_runner.current_target)
				_hud.say("Simulator effort %+d %%" % int(round(_sim_offset * 100)))
		KEY_Q:
			if _sim and _trainer is SimulatedTrainer:
				var st := _trainer as SimulatedTrainer
				st.pedaling = not st.pedaling
				_hud.say("Simulator pedalling" if st.pedaling else "Simulator stopped pedalling")
