extends Control
## Post-ride summary: metrics, the FIT file, and upload status per connector.

var _journal_path := ""
var _fit_path := ""
var _meta: Dictionary = {}
var _metrics: Dictionary = {}
var _upload_l: Label
var _upload_btn: Button


func _ready() -> void:
	_journal_path = App.last_ride_journal
	var j := RideRecorder.load_journal(_journal_path) if _journal_path != "" else {}
	_meta = j.get("meta", {})
	_fit_path = _journal_path.get_basename() + ".fit"
	_metrics = RideMetrics.compute(j.get("samples", []), int(_meta.get("ftp", App.ftp)))
	_build_ui(j)
	Sync.changed.connect(_refresh_upload)
	_refresh_upload()
	if App.prompt_upload:
		App.prompt_upload = false
		if not Sync.configured_connectors().is_empty() and Sync.jobs_for(_fit_path).is_empty():
			_ask_to_share()


## One dialog, a checkbox per connected service.
func _ask_to_share() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Share this ride?"
	dlg.ok_button_text = "Share"
	dlg.cancel_button_text = "Not now"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dlg.add_child(v)
	var head := Label.new()
	head.text = "%s\n%s" % [str(_meta.get("workout", "Ride")), _description()]
	v.add_child(head)
	var boxes: Array[CheckBox] = []
	for c in Sync.configured_connectors():
		var cb := CheckBox.new()
		cb.text = "Post to " + c.display_name()
		cb.button_pressed = Sync.jobs_for(_fit_path).filter(func(j): return j.connector == c.id()).is_empty()
		cb.set_meta("connector", c.id())
		v.add_child(cb)
		boxes.append(cb)
	dlg.confirmed.connect(func() -> void:
		for cb in boxes:
			if cb.button_pressed:
				_share_to(str(cb.get_meta("connector"))))
	add_child(dlg)
	dlg.popup_centered()


func _share_to(connector_id: String) -> void:
	for j in Sync.jobs_for(_fit_path):
		if j.connector == connector_id:
			Sync.retry(j.id)
			return
	Sync.enqueue(connector_id, _fit_path, str(_meta.get("workout", "Ride")), _description())


## Screenshots saved beside the ride: <id>-*.png
func _screenshots() -> Array[String]:
	var out: Array[String] = []
	var dir := _fit_path.get_base_dir()
	var stem := _fit_path.get_file().get_basename()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with(stem) and f.ends_with(".png"):
			out.append(dir.path_join(f))
	out.sort()
	return out


func _refresh_upload() -> void:
	var lines: Array[String] = []
	for job in Sync.jobs_for(_fit_path):
		var c: Connector = Sync.connectors.get(job.connector)
		var label := c.display_name() if c else str(job.connector)
		match str(job.status):
			"done": lines.append("%s: uploaded" % label)
			"uploading": lines.append("%s: uploading…" % label)
			"failed": lines.append("%s: failed after %d attempts. %s" % [label, int(job.attempts), str(job.last_error)])
			_: lines.append("%s: waiting to upload%s" % [label, (" (%s)" % str(job.last_error)) if str(job.last_error) != "" else ""])
	if lines.is_empty():
		if Sync.configured_connectors().is_empty():
			lines.append("Connect intervals.icu or Strava in Settings to share rides")
		else:
			lines.append("Not shared yet")
	_upload_l.text = "\n".join(lines)
	_upload_btn.disabled = Sync.configured_connectors().is_empty() or not FileAccess.file_exists(_fit_path)


func _on_upload_pressed() -> void:
	_ask_to_share()


func _description() -> String:
	return "Ride · %d W avg · NP %d W · %d kJ · TSS %d" % [
		int(_metrics.avg_power), int(_metrics.normalized_power), int(_metrics.kj), int(round(float(_metrics.tss)))]


func _fmt(seconds: int) -> String:
	return "%d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]


func _build_ui(j: Dictionary) -> void:
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
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var completed: bool = bool(j.get("end", {}).get("completed", false))
	_label(v, str(_meta.get("workout", "Ride")), 30)
	var when := Time.get_datetime_string_from_unix_time(int(_meta.get("started_at", 0)), true).replace("T", " ")
	_label(v, "%s  ·  %s  ·  FTP %d W" % [when, "Completed" if completed else "Ended early", int(_meta.get("ftp", 0))], 16).modulate = Color(1, 1, 1, 0.7)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 16)
	v.add_child(grid)
	_stat(grid, "Time", _fmt(int(_metrics.duration_s)))
	_stat(grid, "Avg power", "%d W" % int(_metrics.avg_power))
	_stat(grid, "Normalized", "%d W" % int(_metrics.normalized_power))
	_stat(grid, "Max power", "%d W" % int(_metrics.max_power))
	_stat(grid, "Work", "%d kJ" % int(_metrics.kj))
	var kcal := RideMetrics.kcal_from_kj(float(_metrics.kj))
	_stat(grid, "Burned", "%d kcal" % int(round(kcal)))
	_stat(grid, "That is", "%.1f slices of pizza" % RideMetrics.pizza_slices(kcal))
	_stat(grid, "Intensity", "%.2f" % float(_metrics.intensity_factor))
	_stat(grid, "TSS", "%d" % int(round(float(_metrics.tss))))
	_stat(grid, "Avg HR", ("%d bpm" % int(_metrics.avg_heart_rate)) if int(_metrics.avg_heart_rate) > 0 else "—")
	_stat(grid, "Max HR", ("%d bpm" % int(_metrics.max_heart_rate)) if int(_metrics.max_heart_rate) > 0 else "—")
	_stat(grid, "Avg cadence", ("%d rpm" % int(_metrics.avg_cadence)) if int(_metrics.avg_cadence) > 0 else "—")
	_stat(grid, "Distance", "%s %s" % [App.distance_text(float(_metrics.distance_m)), App.distance_unit().to_lower()])
	_stat(grid, "Samples", str(int(_metrics.duration_s)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	_label(v, "Sync", 18)
	_upload_l = _label(v, "", 15)
	_upload_l.modulate = Color(1, 1, 1, 0.8)
	var file_l := _label(v, "FIT file: %s" % ProjectSettings.globalize_path(_fit_path), 13)
	file_l.modulate = Color(1, 1, 1, 0.5)
	file_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	# Screenshots from the ride, for posting by hand (Strava's API takes no photos from third parties).
	var shots := _screenshots()
	if not shots.is_empty():
		_label(v, "Screenshots  ·  add these to the activity in the Strava app", 14).modulate = Color(1, 1, 1, 0.7)
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 10)
		v.add_child(strip)
		for path in shots:
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img == null:
				continue
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.custom_minimum_size = Vector2(240, 135)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			strip.add_child(tr)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_upload_btn = _button(bar, "Share…", _on_upload_pressed)
	_button(bar, "Show ride files in Finder", func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(_fit_path)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_button(bar, "Home", func() -> void: App.go_to("res://ui/screens/home_screen.tscn"))


func _stat(grid: GridContainer, title: String, value: String) -> void:
	var box := VBoxContainer.new()
	grid.add_child(box)
	_label(box, title, 13).modulate = Color(1, 1, 1, 0.6)
	_label(box, value, 28)


func _label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
