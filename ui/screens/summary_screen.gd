extends Control
## Post-ride summary in the Groove style: the ride's trace, the numbers, and a
## Sharing card with one checkbox per connected service. Nothing is posted
## until Share is pressed.

var _journal_path := ""
var _ride: Dictionary = {}


func _ready() -> void:
	_journal_path = App.last_ride_journal
	var j := RideRecorder.load_journal(_journal_path) if _journal_path != "" else {}
	var meta: Dictionary = j.get("meta", {})
	var samples: Array = j.get("samples", [])
	_ride = {
		"journal": _journal_path, "fit": _journal_path.get_basename() + ".fit", "meta": meta,
		"samples": samples.size(), "trace": samples,
		"completed": bool(j.get("end", {}).get("completed", false)), "finished": j.has("end"),
	}
	App.prompt_upload = false   # the Sharing card below is the prompt
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = HudStyle.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/images/menu-bg.png")
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(art)
	var wash := ColorRect.new()
	wash.color = Color(HudStyle.INK, 0.6)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(wash)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var meta: Dictionary = _ride.meta
	var ftp := int(meta.get("ftp", App.ftp))
	var m := RideMetrics.compute(_ride.trace, ftp)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	head.add_child(title_box)
	HudStyle.section_label(title_box, "Ride complete" if _ride.completed else "Ride ended", 12, HudStyle.ORANGE if not _ride.completed else HudStyle.CYAN)
	HudStyle.label(title_box, str(meta.get("workout", "Ride")), 34, 900)
	var when := Time.get_datetime_string_from_unix_time(int(meta.get("started_at", 0)), true).left(16)
	HudStyle.label(title_box, "%s   ·   FTP %d W" % [when, ftp], 13, 500, HudStyle.TEXT_DIM)
	HudStyle.button(head, "Home", 16, func() -> void: App.go_to("res://ui/screens/home_screen.tscn"), "primary").size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var trace := RideTrace.new()
	trace.custom_minimum_size.y = 180
	trace.set_samples(_ride.trace, ftp)
	v.add_child(trace)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_stat(grid, _fmt(int(m.duration_s)), "time")
	_stat(grid, "%d" % int(m.avg_power), "W avg")
	_stat(grid, "%d" % int(m.normalized_power), "W normalized")
	_stat(grid, "%d" % int(m.max_power), "W max")
	_stat(grid, "%d" % int(round(float(m.tss))), "TSS")
	_stat(grid, "%.2f" % float(m.intensity_factor), "intensity")
	_stat(grid, "%d" % int(m.kj), "kJ")
	var kcal := RideMetrics.kcal_from_kj(float(m.kj))
	_stat(grid, "%d" % int(round(kcal)), "kcal")
	_stat(grid, "%.1f" % RideMetrics.pizza_slices(kcal), "slices of pizza")
	_stat(grid, App.distance_text(float(m.distance_m)), App.distance_unit().to_lower())
	_stat(grid, ("%d" % int(m.avg_heart_rate)) if int(m.avg_heart_rate) > 0 else "—", "bpm avg")
	_stat(grid, ("%d" % int(m.max_heart_rate)) if int(m.max_heart_rate) > 0 else "—", "bpm max")
	_stat(grid, ("%d" % int(m.avg_cadence)) if int(m.avg_cadence) > 0 else "—", "rpm")

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	cols.add_child(right)

	# Sharing: same card as the ride sheet, so the two never drift apart.
	var share := HudStyle.section(left, "Sharing")
	var share_body := VBoxContainer.new()
	share_body.add_theme_constant_override("separation", 6)
	share.add_child(share_body)
	RidesPanel._fill_sharing(share_body, _ride)
	var on_change := func() -> void:
		if is_instance_valid(share_body):
			RidesPanel._fill_sharing(share_body, _ride)
	Sync.changed.connect(on_change)
	share_body.tree_exiting.connect(func() -> void: Sync.changed.disconnect(on_change))
	var files := HudStyle.section(left, "Files")
	var path_l := HudStyle.label(files, ProjectSettings.globalize_path(str(_ride.fit)), 12, 500, HudStyle.TEXT_DIM)
	path_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	HudStyle.button(files, HudStyle.file_manager_label(), 13, func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(str(_ride.fit)))).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var shots := RidesPanel._screenshots(str(_ride.fit))
	if not shots.is_empty():
		var shots_box := HudStyle.section(right, "Screenshots", "Strava's API takes no photos from other apps; add these to the activity in the Strava app.")
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 10)
		shots_box.add_child(strip)
		for i in mini(shots.size(), 4):
			_thumb(strip, shots, i, Vector2(288, 162))


## Clickable thumbnail: opens the Lightbox on that shot.
static func _thumb(strip: Control, shots: Array[String], i: int, size: Vector2) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(shots[i]))
	if img == null:
		return
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tr.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Lightbox.open(shots, i))
	tr.mouse_entered.connect(func() -> void: tr.modulate = Color(1.15, 1.15, 1.2))
	tr.mouse_exited.connect(func() -> void: tr.modulate = Color.WHITE)
	strip.add_child(tr)


func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 30, 900)
	var u := HudStyle.label(h, unit, 13, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)


func _fmt(seconds: int) -> String:
	return "%d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]
