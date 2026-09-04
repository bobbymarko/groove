extends Control
## One workout in detail: the plan graph, description, block list, estimates,
## and the Ride buttons. App.workout must be set before entering.

var _ride: Button
var _devices_l: Label


func _ready() -> void:
	_build_ui()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())
	_refresh_devices()


func _refresh_devices() -> void:
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
	if simulator:
		Devices.use_simulated_devices()
	App.go_to("res://ui/screens/ride_screen.tscn")


func _build_ui() -> void:
	var w: Workout = App.workout
	var ftp := App.ftp
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	HudStyle.button(head, "‹ Workouts", 16, func() -> void: App.go_to("res://ui/screens/home_screen.tscn"))
	var title := HudStyle.label(head, w.name, 30, 900)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_devices_l = HudStyle.label(head, "", 14, 500, HudStyle.TEXT_DIM)

	var est := WorkoutSummary.estimates(w, ftp)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 36)
	v.add_child(meta)
	_stat(meta, WorkoutSummary.duration(w.total_duration()), "duration")
	_stat(meta, "%d" % int(round(est.kj)), "kJ at %d W FTP" % ftp)
	_stat(meta, "%d" % int(round(est.tss)), "TSS")
	_stat(meta, "%.2f" % float(est.intensity_factor), "intensity")
	_stat(meta, str(w.segments.size()), "segments")
	if w.author != "":
		_stat(meta, w.author, "author")

	var graph := WorkoutGraph.new()
	graph.custom_minimum_size.y = 200
	graph.set_workout(w)
	v.add_child(graph)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var desc := RichTextLabel.new()
	desc.text = w.description if w.description != "" else "No description."
	desc.add_theme_font_override("normal_font", HudStyle.font(500))
	desc.add_theme_font_size_override("normal_font_size", 17)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.size_flags_stretch_ratio = 1.4
	body.add_child(desc)
	var blocks := VBoxContainer.new()
	blocks.custom_minimum_size.x = 340
	blocks.add_theme_constant_override("separation", 6)
	body.add_child(blocks)
	HudStyle.label(blocks, "Blocks", 16, 700, HudStyle.TEXT_DIM)
	for r in WorkoutSummary.rows(w, ftp):
		var row := HudStyle.panel(blocks, HudStyle.PANEL_ROW, 6, 10)
		if r.kind == "intervals":
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			row.add_child(h)
			var c := HudStyle.label(h, "%d x" % int(r.count), 24, 700)
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var lines := VBoxContainer.new()
			lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(lines)
			HudStyle.label(lines, "%s @ %dw" % [WorkoutSummary.duration(r.on_dur), int(r.on_w)], 16, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			HudStyle.label(lines, "%s @ %dw" % [WorkoutSummary.duration(r.off_dur), int(r.off_w)], 16, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			HudStyle.label(row, r.text, 16, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	_ride = HudStyle.button(bar, "Ride", 20, _start.bind(false))
	_ride.custom_minimum_size = Vector2(200, 48)
	HudStyle.button(bar, "Ride on simulator", 16, _start.bind(true))


func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 26, 900)
	var u := HudStyle.label(h, unit, 14, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)
