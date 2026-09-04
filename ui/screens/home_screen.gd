extends Control
## Home: a grid of workout cards with plan thumbnails. Click a card for the
## detail view; device status, recent rides and settings live around it.

var _files: Array[String] = []
var _list: VBoxContainer            # sections: planned days, then the library
var _grids: Array[GridContainer] = []
var _cal_status: Label
var _devices_l: Label
var _error: Label
var _dialog: FileDialog
var _sheet: WorkoutSheet
var _side: SideSheet          # settings / devices / rides


func _ready() -> void:
	_build_ui()
	_refresh_cards()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.heart_rate_sensor_changed.connect(func(_h: HeartRateSensor) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())
	_refresh_devices()
	_recover_unfinished()
	Sync.calendar.updated.connect(_refresh_cards)
	Sync.calendar.refresh_if_stale()


## Planned workouts from intervals.icu by day (today first, highlighted), then
## the local library. Without a linked account only the library shows.
func _refresh_cards() -> void:
	for c in _list.get_children():
		c.queue_free()
	_grids.clear()
	_files = App.list_workout_files()
	var linked := Sync.intervals().is_configured()
	if linked:
		var today := IntervalsCalendar.today()
		var days := Sync.calendar.by_day()
		if days.is_empty() or str(days[0].date) != today:
			var g := _section("Today", true)
			HudStyle.label(g, "Nothing planned on intervals.icu today", 14, 500, HudStyle.TEXT_DIM)
		for day in days:
			var is_today: bool = str(day.date) == today
			var g := _section(str(day.label), is_today)
			for e in day.entries:
				var w := ZwoParser.parse_file(str(e.path))
				if w != null:
					_add_card(g, w, str(e.path), is_today)
	var lib := _section("Library" if linked else "Workouts", false)
	for f in _files:
		var w := ZwoParser.parse_file(f)
		if w == null:
			continue
		_add_card(lib, w, f, false)
	_add_open_card(lib)
	_cal_status.text = Sync.calendar.status if linked else ""
	_cal_status.visible = _cal_status.text != ""
	_relayout()


func _section(title: String, highlight: bool) -> GridContainer:
	if not _list.get_children().is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		_list.add_child(gap)
	HudStyle.label(_list, title, 18, 900 if highlight else 700, HudStyle.TEXT if highlight else HudStyle.TEXT_DIM)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	_grids.append(grid)
	return grid


func _relayout() -> void:
	var cols := maxi(1, int((size.x - 56) / 316.0))
	for g in _grids:
		g.columns = cols


func _add_card(grid: GridContainer, w: Workout, path: String, highlight: bool) -> void:
	var card := HudStyle.panel(grid, Color(0.16, 0.19, 0.27, 0.8) if highlight else HudStyle.PANEL_ROW, 10, 12)
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
			_sheet.open(ZwoParser.parse_file(path)))
	card.mouse_entered.connect(func() -> void: card.modulate = Color(1.15, 1.15, 1.2))
	card.mouse_exited.connect(func() -> void: card.modulate = Color.WHITE)


func _add_open_card(grid: GridContainer) -> void:
	var card := HudStyle.panel(grid, Color(0.10, 0.12, 0.17, 0.35), 10, 12)
	card.custom_minimum_size = Vector2(300, 150)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(c)
	var l := HudStyle.label(c, "+  Open .zwo file…", 16, 700, HudStyle.TEXT_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_open_pressed())
	card.mouse_entered.connect(func() -> void: card.modulate = Color(1.2, 1.2, 1.25))
	card.mouse_exited.connect(func() -> void: card.modulate = Color.WHITE)


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
	HudStyle.button(head, "Rides", 15, open_rides)
	HudStyle.button(head, "Devices", 15, open_devices)
	HudStyle.button(head, "Settings", 15, open_settings)

	_cal_status = HudStyle.label(v, "", 13, 500, HudStyle.TEXT_DIM)
	_cal_status.visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	resized.connect(_relayout)

	_error = HudStyle.label(v, "", 14, 500, Color(1, 0.6, 0.6))

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.zwo ; Zwift workout"])
	_dialog.file_selected.connect(_on_file_chosen)
	add_child(_dialog)

	_sheet = WorkoutSheet.new()
	_sheet.name = "WorkoutSheet"
	add_child(_sheet)
	_side = SideSheet.new()
	_side.name = "SideSheet"
	_side.width = 560.0
	add_child(_side)


func open_settings() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_side.header(v, "Settings")
	var p := SettingsPanel.new()
	p.name = "SettingsPanel"
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p)
	_side.show_content(v)
	# FTP changes the card estimates.
	if not _side.closed.is_connected(_refresh_cards):
		_side.closed.connect(_refresh_cards)


func open_devices() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_side.header(v, "Devices")
	var p := DevicesPanel.new()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p)
	_side.show_content(v)


func open_rides() -> void:
	RidesPanel.open_in(_side, true)
