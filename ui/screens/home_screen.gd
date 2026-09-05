extends Control
## Home: a grid of workout cards with plan thumbnails. Click a card for the
## detail view; device status, recent rides and settings live around it.

var _files: Array[String] = []
var _list: VBoxContainer            # sections: planned days, then the library
var _grids: Array[GridContainer] = []
var _cal_status: Label
var _cards: Array[Control] = []      # tiles in build order, for the entrance cascade
var _filter_duration := 0            # 0 any, 1 under 30 min, 2 30-60, 3 over 60
var _filter_source := 0              # 0 all, 1 uploaded, 2 bundled
const FILTER_LABELS := ["Any duration", "Under 30 min", "30 to 60 min", "Over 60 min", "", "All workouts", "Uploaded", "Bundled"]
var _cascaded := false               # animate once per visit, not on every calendar refresh
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
	_cards.clear()
	_files = App.list_workout_files()
	var linked := Sync.intervals().is_configured()
	if linked:
		_add_training_plan()
	else:
		_add_onboarding()
	var lib := _section("Library", false, true)
	_add_open_card(lib)
	for f in _files:
		var w := WorkoutLoader.load_file(f, App.ftp)
		if w == null or not _passes_filter(w, f):
			continue
		_add_card(lib, w, f, false, true)   # flexible: shares the five-column grid with the plan
	_cal_status.text = Sync.calendar.status if linked else ""
	_cal_status.visible = _cal_status.text != ""
	_relayout()
	if not _cascaded:
		_cascaded = true
		_cascade_in()


## Tiles fade and grow in one after another, quickly.
func _cascade_in() -> void:
	for c in _cards:
		c.modulate.a = 0.0
	await get_tree().process_frame   # sizes are known now, so scaling can pivot on the centre
	if not is_inside_tree():
		return                      # the screen was replaced while we waited (dev launch options do this)
	# The window and background take a moment to appear; hold so the cascade is seen.
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		return
	var delay := 0.0
	for c in _cards:
		if not is_instance_valid(c):
			continue
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(0.94, 0.94)
		var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(delay)
		tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_delay(delay)
		delay += 0.07


const PLAN_DAYS := 5
const CARD_HEIGHT := 196.0

## "Training plan": one row of the next five days, each a column with a day
## subhead and that day's planned rides, or an equally sized "Nothing planned" box.
func _add_training_plan() -> void:
	HudStyle.section_label(_list, "Training plan", 20)
	var today := IntervalsCalendar.today()
	var by_date: Dictionary = {}
	for day in Sync.calendar.by_day():
		by_date[str(day.date)] = day.entries
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(row)
	for i in PLAN_DAYS:
		var date := IntervalsCalendar.date_offset(today, i)
		var is_today := i == 0
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_stretch_ratio = 1.0
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		var label := IntervalsCalendar.day_label(date, today)
		if "," in label:
			label = label.split(",")[0]   # "Wednesday, Sep 9" -> "Wednesday"
		HudStyle.section_label(col, label, 12, HudStyle.ORANGE if is_today else HudStyle.TEXT_DIM)
		var entries: Array = by_date.get(date, [])
		var shown := 0
		for e in entries:
			var w := WorkoutLoader.load_file(str(e.path), App.ftp)
			if w != null:
				_add_card(col, w, str(e.path), is_today, true)
				shown += 1
		if shown == 0:
			_add_empty_card(col)


## No intervals.icu yet: say what linking gets you and point at Settings.
func _add_onboarding() -> void:
	HudStyle.section_label(_list, "Training plan", 20)
	var card := HudStyle.panel(_list, HudStyle.CARD, HudStyle.RADIUS, 16)
	card.add_theme_stylebox_override("panel", HudStyle.flat(HudStyle.CARD, HudStyle.RADIUS, 20, 18, HudStyle.BORDER))
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size.x = 720
	_cards.append(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	card.add_child(h)
	HudStyle.icon(h, "signal", 44, HudStyle.CYAN).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)
	HudStyle.label(v, "Connect intervals.icu for live training", 20, 900)
	var body := HudStyle.label(v, "Link your account and the next five days of planned rides show up here, ready to ride, with today's workout first. Finished rides can be shared back too.", 14, 500, HudStyle.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	HudStyle.button(row, "Connect in Settings", 13, open_settings, "primary")
	HudStyle.label(row, "or upload a workout file below", 13, 500, HudStyle.TEXT_DIM).size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _add_empty_card(parent: Control) -> void:
	var card := HudStyle.panel(parent, Color(HudStyle.CARD, 0.45), HudStyle.RADIUS, 16)
	card.add_theme_stylebox_override("panel", HudStyle.flat(Color(HudStyle.CARD, 0.45), HudStyle.RADIUS, 16, 16, HudStyle.BORDER))
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.append(card)
	# An empty slot says it by being empty.


## Three-dot menu in a card's top-right corner: Ride (straight to the scene
## picker) or Delete (confirmed; the file moves to workouts/deleted, never destroyed).
func _add_card_menu(card: PanelContainer, w: Workout, path: String) -> void:
	var menu := PopupMenu.new()
	menu.add_item("Ride", 0)
	menu.add_item("Delete", 1)
	menu.add_theme_font_override("font", HudStyle.font(500, 22))
	menu.add_theme_font_size_override("font_size", 22)
	card.add_child(menu)
	var btn := HudStyle.icon_button(card, "more", func() -> void: pass, 18)
	btn.pressed.connect(func() -> void: HudStyle.popup_below(menu, btn, true))
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -44.0
	btn.offset_right = -10.0
	btn.offset_top = 10.0
	btn.offset_bottom = 40.0
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_sheet.open(w)
			_sheet.choose_scene(false)
		else:
			_confirm_delete(w, path))


func _confirm_delete(w: Workout, path: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete workout?"
	dlg.dialog_text = "%s will move to the deleted folder. Nothing is erased." % w.name
	dlg.ok_button_text = "Delete"
	dlg.cancel_button_text = "Keep"
	dlg.confirmed.connect(func() -> void:
		if App.delete_workout(path):
			_refresh_cards()
		else:
			_error.text = "Could not move %s" % path.get_file())
	add_child(dlg)
	dlg.popup_centered()


## Header button with an icon and an uppercase word.
func _nav_button(parent: Control, icon_name: String, text: String, on_pressed: Callable) -> Button:
	var b := HudStyle.button(parent, text, 13, on_pressed)
	b.icon = HudStyle.icon_texture(icon_name)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 22)
	b.add_theme_constant_override("h_separation", 8)
	if not HudStyle.is_sprite(icon_name):
		for st in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(st, HudStyle.CYAN)
	return b


func _passes_filter(w: Workout, path: String) -> bool:
	var minutes := w.total_duration() / 60.0
	match _filter_duration:
		1: if minutes >= 30.0: return false
		2: if minutes < 30.0 or minutes > 60.0: return false
		3: if minutes <= 60.0: return false
	match _filter_source:
		1: if not App.is_user_workout(path): return false
		2: if App.is_user_workout(path): return false
	return true


## Filter menu on the Library header: one duration choice, one source choice.
func _filter_menu(parent: Control) -> void:
	var menu := PopupMenu.new()
	menu.add_theme_font_override("font", HudStyle.font(500, 22))
	menu.add_theme_font_size_override("font_size", 22)
	for i in FILTER_LABELS.size():
		if FILTER_LABELS[i] == "":
			menu.add_separator()
		else:
			menu.add_radio_check_item(FILTER_LABELS[i], i)
	menu.set_item_checked(_filter_duration, true)
	menu.set_item_checked(5 + _filter_source, true)
	parent.add_child(menu)
	var active := _filter_duration != 0 or _filter_source != 0
	var btn := HudStyle.icon_button(parent, "filter", func() -> void: pass, 18, "secondary" if active else "ghost")
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The menu hangs directly off the button's bottom-left corner.
	btn.pressed.connect(func() -> void: HudStyle.popup_below(menu, btn))
	menu.id_pressed.connect(func(id: int) -> void:
		if id <= 3:
			_filter_duration = id
		else:
			_filter_source = id - 5
		_refresh_cards())


## Section title in display type (the day labels below it stay small UI type).
func _section(title: String, highlight: bool, with_filter := false) -> GridContainer:
	if not _list.get_children().is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		_list.add_child(gap)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_list.add_child(head)
	HudStyle.section_label(head, title, 20, HudStyle.ORANGE if highlight else HudStyle.CYAN)
	if with_filter:
		_filter_menu(head)   # sits right after the word
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	_grids.append(grid)
	return grid


## Every grid uses the training plan's five columns so the two sections line up.
func _relayout() -> void:
	for g in _grids:
		g.columns = PLAN_DAYS


## flexible: fill the parent's width (plan columns) instead of a fixed card width.
func _add_card(parent: Control, w: Workout, path: String, highlight: bool, flexible := false) -> void:
	var card := HudStyle.panel(parent, HudStyle.CARD, HudStyle.RADIUS, 16)
	card.add_theme_stylebox_override("panel", HudStyle.flat(HudStyle.CARD, HudStyle.RADIUS, 16, 16, HudStyle.BORDER))   # equal padding all round
	# Today's card looks like every other card; the orange subhead marks the day.
	card.custom_minimum_size = Vector2(0.0 if flexible else 300.0, CARD_HEIGHT)
	if flexible:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_cards.append(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var graph := WorkoutGraph.new()
	graph.custom_minimum_size = Vector2(0.0 if flexible else 268.0, 96)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL   # spare height goes into the graph, not under the text
	graph.show_marker = false
	graph.set_workout(w)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(graph)
	var name_l := HudStyle.label(v, w.name, 16, 700, HudStyle.CYAN)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if App.is_user_workout(path):
		_add_card_menu(card, w, path)
	var est := WorkoutSummary.estimates(w, App.ftp)
	var meta_l := HudStyle.label(v, "%s   %s   %d TSS" % [WorkoutSummary.duration(w.total_duration()), WorkoutSummary.headline(w, App.ftp), int(round(est.tss))], 13, 500, HudStyle.TEXT_DIM)
	meta_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # text never widens the column
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_sheet.open(WorkoutLoader.load_file(path, App.ftp)))
	card.mouse_entered.connect(func() -> void: card.modulate = Color(1.15, 1.15, 1.2))
	card.mouse_exited.connect(func() -> void: card.modulate = Color.WHITE)


func _add_open_card(grid: GridContainer) -> void:
	var card := HudStyle.panel(grid, Color(HudStyle.CARD, 0.5), HudStyle.RADIUS, 16)
	card.add_theme_stylebox_override("panel", HudStyle.flat(Color(HudStyle.CARD, 0.5), HudStyle.RADIUS, 16, 16, HudStyle.BORDER))
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_cards.append(card)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(c)
	var l := HudStyle.label(c, "+  UPLOAD WORKOUT", 14, 700, HudStyle.CYAN)
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
	var w := WorkoutLoader.load_file(path, App.ftp)
	if w == null:
		_error.text = "Could not load %s: %s" % [path.get_file(), WorkoutLoader.last_error]
		return
	var dest := App.USER_WORKOUTS_DIR.path_join(path.get_file())
	DirAccess.copy_absolute(path, ProjectSettings.globalize_path(dest))
	_refresh_cards()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = HudStyle.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Pixel night mountains behind everything, under an ink wash so cards stay legible.
	var art := TextureRect.new()
	art.texture = load("res://assets/images/menu-bg.png")
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var wash := ColorRect.new()
	wash.color = Color(HudStyle.INK, 0.45)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
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
	var title := TextureRect.new()
	title.texture = load("res://assets/images/groove-wordmark-transparent.png")
	title.custom_minimum_size = Vector2(212, 46)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_devices_l = HudStyle.label(head, "", 13, 500, HudStyle.TEXT_DIM)
	_devices_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_nav_button(head, "bluetooth", "Devices", open_devices)   # beside the device status text
	_nav_button(head, "history", "Rides", open_rides)
	_nav_button(head, "gear", "Settings", open_settings)

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
	_dialog.filters = PackedStringArray([WorkoutLoader.FILTER])
	_dialog.file_selected.connect(_on_file_chosen)
	add_child(_dialog)

	_sheet = WorkoutSheet.new()
	_sheet.name = "WorkoutSheet"
	add_child(_sheet)
	_side = SideSheet.new()
	_side.name = "SideSheet"
	_side.width = 740.0   # pixel type is wide; settings rows need the room
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
