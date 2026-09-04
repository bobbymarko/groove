extends Control
## Home: a grid of workout cards with plan thumbnails. Click a card for the
## detail view; device status, recent rides and settings live around it.

var _files: Array[String] = []
var _grid: GridContainer
var _devices_l: Label
var _rides: ItemList
var _ride_entries: Array[Dictionary] = []
var _error: Label
var _dialog: FileDialog


func _ready() -> void:
	_build_ui()
	_refresh_cards()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.heart_rate_sensor_changed.connect(func(_h: HeartRateSensor) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())
	_refresh_devices()
	_refresh_rides()
	_recover_unfinished()


func _refresh_cards() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_files = App.list_workout_files()
	for f in _files:
		var w := ZwoParser.parse_file(f)
		if w == null:
			continue
		_add_card(w, f)
	_add_open_card()


func _add_card(w: Workout, path: String) -> void:
	var card := HudStyle.panel(_grid, HudStyle.PANEL_ROW, 10, 12)
	card.custom_minimum_size = Vector2(300, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var graph := WorkoutGraph.new()
	graph.custom_minimum_size = Vector2(276, 96)
	graph.set_workout(w)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(graph)
	var name_l := HudStyle.label(v, w.name, 18, 700)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var est := WorkoutSummary.estimates(w, App.ftp)
	HudStyle.label(v, "%s  ·  %s  ·  %d TSS" % [WorkoutSummary.duration(w.total_duration()), WorkoutSummary.headline(w, App.ftp), int(round(est.tss))], 13, 500, HudStyle.TEXT_DIM)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			App.workout = ZwoParser.parse_file(path)
			App.go_to("res://ui/screens/workout_detail_screen.tscn"))
	card.mouse_entered.connect(func() -> void: card.modulate = Color(1.15, 1.15, 1.2))
	card.mouse_exited.connect(func() -> void: card.modulate = Color.WHITE)


func _add_open_card() -> void:
	var card := HudStyle.panel(_grid, Color(0.10, 0.12, 0.17, 0.35), 10, 12)
	card.custom_minimum_size = Vector2(300, 150)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(c)
	HudStyle.button(c, "+  Open .zwo file…", 16, _on_open_pressed)


func _refresh_devices() -> void:
	var parts: Array[String] = []
	var t := Devices.trainer
	if t != null and not (t is SimulatedTrainer):
		parts.append("%s %s" % [t.display_name(), "connected" if t.is_device_connected() else "reconnecting…"])
	elif Devices.remembered.has("trainer"):
		parts.append("Looking for %s…" % Devices.remembered.trainer.name)
	else:
		parts.append("No trainer paired")
	var h := Devices.heart_rate
	if h != null and not (h is SimulatedHeartRate):
		parts.append("%s %s" % [h.display_name(), "connected" if h.is_device_connected() else "reconnecting…"])
	_devices_l.text = "  ·  ".join(parts)


func _refresh_rides() -> void:
	_ride_entries = App.list_rides()
	_rides.clear()
	for r in _ride_entries:
		var when := Time.get_datetime_string_from_unix_time(int(r.meta.get("started_at", 0)), true).replace("T", " ")
		_rides.add_item("%s   %s   %d min%s" % [when.left(16), str(r.meta.get("workout", "Ride")), int(r.samples) / 60, "" if r.finished else "   (unfinished)"])


func _on_ride_selected(i: int) -> void:
	App.last_ride_journal = _ride_entries[i].journal
	App.go_to("res://ui/screens/summary_screen.tscn")


## A journal without an end line means the app died mid-ride. Finalize it so
## the FIT file exists and the ride can be shared.
func _recover_unfinished() -> void:
	for path in RideRecorder.unfinished_journals():
		var j := RideRecorder.load_journal(path)
		var meta: Dictionary = j.meta
		var samples: Array = j.samples
		var metrics := RideMetrics.compute(samples, int(meta.get("ftp", App.ftp)))
		var fit := path.get_basename() + ".fit"
		if not FileAccess.file_exists(fit):
			var f := FileAccess.open(fit, FileAccess.WRITE)
			if f:
				f.store_buffer(FitEncoder.encode(meta, samples, metrics, true))
				f.close()
		var jf := FileAccess.open(path, FileAccess.READ_WRITE)
		if jf:
			jf.seek_end()
			jf.store_line(JSON.stringify({"end": {"ended_at": int(samples[-1].t), "completed": false, "recovered": true}}))
			jf.close()
		_error.text = "Recovered an unfinished ride: %s" % str(meta.get("workout", path.get_file()))
	if RideRecorder.unfinished_journals().is_empty():
		_refresh_rides()


func _on_open_pressed() -> void:
	_dialog.popup_centered_ratio(0.7)


func _on_file_chosen(path: String) -> void:
	var w := ZwoParser.parse_file(path)
	if w == null:
		_error.text = "Could not load %s: %s" % [path.get_file(), ZwoParser.last_error]
		return
	var dest := App.USER_WORKOUTS_DIR.path_join(path.get_file())
	DirAccess.copy_absolute(path, ProjectSettings.globalize_path(dest))
	_refresh_cards()


func _build_ui() -> void:
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
	var title := HudStyle.label(head, "Ride", 34, 900)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_devices_l = HudStyle.label(head, "", 14, 500, HudStyle.TEXT_DIM)
	HudStyle.button(head, "Devices…", 15, func() -> void: App.go_to("res://ui/screens/devices_screen.tscn"))
	HudStyle.button(head, "Settings…", 15, func() -> void: App.go_to("res://ui/screens/settings_screen.tscn"))

	HudStyle.label(v, "Workouts", 18, 700, HudStyle.TEXT_DIM)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	resized.connect(func() -> void: _grid.columns = maxi(1, int((size.x - 56) / 316.0)))

	_error = HudStyle.label(v, "", 14, 500, Color(1, 0.6, 0.6))

	HudStyle.label(v, "Recent rides", 16, 700, HudStyle.TEXT_DIM)
	_rides = ItemList.new()
	_rides.custom_minimum_size.y = 110
	_rides.item_activated.connect(_on_ride_selected)
	v.add_child(_rides)

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.zwo ; Zwift workout"])
	_dialog.file_selected.connect(_on_file_chosen)
	add_child(_dialog)
