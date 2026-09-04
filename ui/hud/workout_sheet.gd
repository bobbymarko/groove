class_name WorkoutSheet
extends SideSheet
## Side sheet with one workout's details: plan graph, estimates, description,
## block list and the Ride buttons.

var workout: Workout
var _ride: Button
var _devices_l: Label


func _ready() -> void:
	width = 500.0
	super._ready()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())


func open(w: Workout) -> void:
	workout = w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_build_content(v)
	show_content(v)
	_refresh_devices()


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


func _build_content(v: VBoxContainer) -> void:
	var w := workout
	var ftp := App.ftp
	header(v, w.name)

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
