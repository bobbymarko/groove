class_name RidesPanel
extends RefCounted
## Recent rides inside a side sheet: a list with a trace thumbnail per ride,
## and a detail view that replaces it in place (back arrow returns to the list).


static func open_in(sheet: SideSheet, animate: bool) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	sheet.header(v, "Recent rides")
	var entries := App.list_rides()
	if entries.is_empty():
		HudStyle.label(v, "No rides yet.", 15, 500, HudStyle.TEXT_DIM)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		for r in entries:
			_row(list, r, sheet)
	HudStyle.button(v, "Open rides folder", 13, func() -> void: OS.shell_open(RideRecorder.rides_dir_abs())).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if animate:
		sheet.show_content(v)
	else:
		sheet.replace_content(v)


static func _row(list: Control, r: Dictionary, sheet: SideSheet) -> void:
	var row := HudStyle.panel(list, HudStyle.PANEL_ROW, 8, 10)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var trace := RideTrace.new()
	trace.custom_minimum_size = Vector2(120, 44)
	trace.show_hr = false
	trace.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trace.set_samples(r.trace, int(r.meta.get("ftp", App.ftp)))
	h.add_child(trace)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(left)
	var name_l := HudStyle.label(left, str(r.meta.get("workout", "Ride")), 16, 700)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HudStyle.label(left, _when(r) + ("" if r.finished else "   ·   unfinished"), 12, 500, HudStyle.TEXT_DIM)
	var mins := HudStyle.label(h, "%d min" % (int(r.samples) / 60), 18, 900)
	mins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_ride(sheet, r))
	row.mouse_entered.connect(func() -> void: row.modulate = Color(1.15, 1.15, 1.2))
	row.mouse_exited.connect(func() -> void: row.modulate = Color.WHITE)


static func _when(r: Dictionary) -> String:
	return Time.get_datetime_string_from_unix_time(int(r.meta.get("started_at", 0)), true).left(16).replace(" ", "   ")


## One ride's details in the sheet.
static func open_ride(sheet: SideSheet, r: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	sheet.header(v, str(r.meta.get("workout", "Ride")), func() -> void: open_in(sheet, false))
	var ftp := int(r.meta.get("ftp", App.ftp))
	var m := RideMetrics.compute(r.trace, ftp)
	var state := "Completed" if r.completed else ("Ended early" if r.finished else "Unfinished")
	HudStyle.label(v, "%s   ·   %s   ·   FTP %d W" % [_when(r), state, ftp], 13, 500, HudStyle.TEXT_DIM)

	var trace := RideTrace.new()
	trace.custom_minimum_size.y = 140
	trace.set_samples(r.trace, ftp)
	v.add_child(trace)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	_stat(grid, _fmt(int(m.duration_s)), "time")
	_stat(grid, "%d" % int(m.avg_power), "W avg")
	_stat(grid, "%d" % int(m.normalized_power), "W normalized")
	_stat(grid, "%d" % int(round(float(m.tss))), "TSS")
	_stat(grid, "%.2f" % float(m.intensity_factor), "intensity")
	_stat(grid, "%d" % int(m.kj), "kJ")
	_stat(grid, ("%d" % int(m.avg_heart_rate)) if int(m.avg_heart_rate) > 0 else "—", "bpm avg")
	_stat(grid, ("%d" % int(m.max_heart_rate)) if int(m.max_heart_rate) > 0 else "—", "bpm max")
	_stat(grid, ("%d" % int(m.avg_cadence)) if int(m.avg_cadence) > 0 else "—", "rpm")

	var fit: String = r.fit
	var sync := HudStyle.section(v, "Sharing")
	var lines: Array[String] = []
	for job in Sync.jobs_for(fit):
		var c: Connector = Sync.connectors.get(job.connector)
		var label := c.display_name() if c else str(job.connector)
		match str(job.status):
			"done": lines.append("%s   ·   uploaded" % label)
			"uploading": lines.append("%s   ·   uploading…" % label)
			"failed": lines.append("%s   ·   failed: %s" % [label, str(job.last_error)])
			_: lines.append("%s   ·   waiting to upload" % label)
	if lines.is_empty():
		lines.append("Not shared yet" if not Sync.configured_connectors().is_empty() else "Connect intervals.icu or Strava in Settings to share rides")
	for line in lines:
		HudStyle.label(sync, line, 13, 500, HudStyle.TEXT_DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var shots := _screenshots(fit)
	if not shots.is_empty():
		HudStyle.label(v, "Screenshots  ·  add these to the activity in the Strava app", 12, 500, HudStyle.TEXT_DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 8)
		v.add_child(strip)
		for path in shots.slice(0, 3):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img == null:
				continue
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.custom_minimum_size = Vector2(160, 90)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			strip.add_child(tr)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	var share := HudStyle.button(bar, "Share…", 15, func() -> void:
		App.last_ride_journal = r.journal
		App.prompt_upload = true
		App.go_to("res://ui/screens/summary_screen.tscn"))
	share.disabled = Sync.configured_connectors().is_empty() or not FileAccess.file_exists(fit)
	HudStyle.button(bar, "Show in Finder", 13, func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(fit)))
	sheet.replace_content(v)


static func _screenshots(fit: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(fit.get_base_dir())
	if d == null:
		return out
	var stem := fit.get_file().get_basename()
	for f in d.get_files():
		if f.begins_with(stem) and f.ends_with(".png"):
			out.append(fit.get_base_dir().path_join(f))
	out.sort()
	return out


static func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 20, 900)
	var u := HudStyle.label(h, unit, 12, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)


static func _fmt(seconds: int) -> String:
	return "%d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]
