class_name WorkoutSheet
extends Control
## Side sheet with one workout's details: plan graph, estimates, description,
## block list and the Ride buttons. Slides in from the right over the home grid;
## a scrim behind it dismisses on click.

signal closed

const WIDTH := 500.0

var workout: Workout
var _panel: PanelContainer
var _scrim: ColorRect
var _ride: Button
var _devices_l: Label
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.45)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_scrim)
	_panel = HudStyle.panel(self, Color(0.11, 0.12, 0.17, 0.98), 0, 22)
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.custom_minimum_size.x = WIDTH
	_panel.offset_left = -WIDTH
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	visible = false
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())


func open(w: Workout) -> void:
	workout = w
	for c in _panel.get_children():
		c.queue_free()
	_build_content()
	_refresh_devices()
	visible = true
	_scrim.modulate.a = 0.0
	_panel.offset_left = 0.0
	_panel.offset_right = WIDTH
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_left", -WIDTH, 0.25)
	_tween.tween_property(_panel, "offset_right", 0.0, 0.25)
	_tween.tween_property(_scrim, "modulate:a", 1.0, 0.25)


func close() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_left", 0.0, 0.2)
	_tween.tween_property(_panel, "offset_right", WIDTH, 0.2)
	_tween.tween_property(_scrim, "modulate:a", 0.0, 0.2)
	_tween.chain().tween_callback(func() -> void: visible = false; closed.emit())


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()


func _refresh_devices() -> void:
	if _ride == null or not is_instance_valid(_ride):
		return
	if Devices.real_trainer_ready():
		_ride.text = "Ride"
		_ride.disabled = false
		_devices_l.text = "%s connected" % Devices.trainer.display_name()
	elif Devices.remembered.has("trainer"):
		_ride.text = "Waiting for %s…" % Devices.remembered.trainer.name
		_ride.disabled = true
		_devices_l.text = "Looking for your trainer"
	else:
		_ride.text = "Pair a trainer to ride"
		_ride.disabled = true
		_devices_l.text = "No trainer paired"


func _start(simulator: bool) -> void:
	App.workout = workout
	if simulator:
		Devices.use_simulated_devices()
	App.go_to("res://ui/screens/ride_screen.tscn")


func _build_content() -> void:
	var w := workout
	var ftp := App.ftp
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var title := HudStyle.label(head, w.name, 24, 900)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.button(head, "✕", 16, close)

	var graph := WorkoutGraph.new()
	graph.custom_minimum_size.y = 130
	graph.set_workout(w)
	v.add_child(graph)

	var est := WorkoutSummary.estimates(w, ftp)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_stat(grid, WorkoutSummary.duration(w.total_duration()), "duration")
	_stat(grid, "%d" % int(round(est.kj)), "kJ at %d W FTP" % ftp)
	_stat(grid, "%d" % int(round(est.tss)), "TSS")
	_stat(grid, "%.2f" % float(est.intensity_factor), "intensity")

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	HudStyle.label(body, "Blocks", 14, 700, HudStyle.TEXT_DIM)
	for r in WorkoutSummary.rows(w, ftp):
		var row := HudStyle.panel(body, HudStyle.PANEL_ROW, 6, 10)
		if r.kind == "intervals":
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			row.add_child(h)
			var c := HudStyle.label(h, "%d x" % int(r.count), 22, 700)
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var lines := VBoxContainer.new()
			lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(lines)
			HudStyle.label(lines, "%s @ %dw" % [WorkoutSummary.duration(r.on_dur), int(r.on_w)], 15, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			HudStyle.label(lines, "%s @ %dw" % [WorkoutSummary.duration(r.off_dur), int(r.off_w)], 15, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			HudStyle.label(row, r.text, 15, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if w.description != "":
		HudStyle.label(body, "About", 14, 700, HudStyle.TEXT_DIM)
		var desc := HudStyle.label(body, w.description, 15, 500)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if w.author != "":
		HudStyle.label(body, "by %s" % w.author, 13, 500, HudStyle.TEXT_DIM)

	_devices_l = HudStyle.label(v, "", 13, 500, HudStyle.TEXT_DIM)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	_ride = HudStyle.button(bar, "Ride", 18, _start.bind(false))
	_ride.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ride.custom_minimum_size.y = 44
	HudStyle.button(bar, "Simulator", 15, _start.bind(true))


func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 22, 900)
	var u := HudStyle.label(h, unit, 13, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)
