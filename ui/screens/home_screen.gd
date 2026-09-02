extends Control
## Home: pick a workout, set FTP, ride on the simulator.

var _files: Array[String] = []
var _list: ItemList
var _title: Label
var _meta: Label
var _desc: RichTextLabel
var _ftp: SpinBox
var _ride: Button
var _error: Label
var _dialog: FileDialog
var _devices_l: Label


func _ready() -> void:
	_build_ui()
	_refresh_list()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.heart_rate_sensor_changed.connect(func(_h: HeartRateSensor) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())
	_refresh_devices()


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
	_ride.text = "Ride" if Devices.has_real_trainer() else "Ride on simulator"


func _refresh_list() -> void:
	_files = App.list_workout_files()
	_list.clear()
	for f in _files:
		var w := ZwoParser.parse_file(f)
		_list.add_item(w.name if w else f.get_file())
	if _files.size() > 0:
		_list.select(0)
		_on_selected(0)


func _on_selected(i: int) -> void:
	var w := ZwoParser.parse_file(_files[i])
	if w == null:
		_title.text = _files[i].get_file()
		_meta.text = ""
		_desc.text = ""
		_error.text = ZwoParser.last_error
		_ride.disabled = true
		return
	App.workout = w
	_error.text = ""
	_title.text = w.name
	var mins := int(w.total_duration() / 60.0)
	_meta.text = "%s  ·  %d min  ·  %d segments  ·  ~%d kJ at %d W FTP" % [
		w.author, mins, w.segments.size(), int(w.estimated_kj(App.ftp)), App.ftp]
	_desc.text = w.description
	_ride.disabled = false


func _on_ftp_changed(v: float) -> void:
	App.ftp = int(v)
	App.save_settings()
	if _list.get_selected_items().size() > 0:
		_on_selected(_list.get_selected_items()[0])


func _on_open_pressed() -> void:
	_dialog.popup_centered_ratio(0.7)


func _on_file_chosen(path: String) -> void:
	var w := ZwoParser.parse_file(path)
	if w == null:
		_error.text = "Could not load %s: %s" % [path.get_file(), ZwoParser.last_error]
		return
	# Copy into the user library so it shows up next time.
	var dest := App.USER_WORKOUTS_DIR.path_join(path.get_file())
	DirAccess.copy_absolute(path, ProjectSettings.globalize_path(dest))
	_refresh_list()
	for i in _files.size():
		if _files[i] == dest:
			_list.select(i)
			_on_selected(i)


func _on_ride_pressed() -> void:
	if App.workout == null:
		return
	if not Devices.has_real_trainer():
		Devices.use_simulated_devices()
	App.go_to("res://ui/screens/ride_screen.tscn")


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	var h := Label.new()
	h.text = "Workouts"
	h.add_theme_font_size_override("font_size", 22)
	left.add_child(h)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)

	var open := Button.new()
	open.text = "Open .zwo file…"
	open.pressed.connect(_on_open_pressed)
	left.add_child(open)

	var ftp_row := HBoxContainer.new()
	left.add_child(ftp_row)
	var ftp_label := Label.new()
	ftp_label.text = "FTP (W)"
	ftp_row.add_child(ftp_label)
	_ftp = SpinBox.new()
	_ftp.min_value = 50
	_ftp.max_value = 600
	_ftp.value = App.ftp
	_ftp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ftp.value_changed.connect(_on_ftp_changed)
	ftp_row.add_child(_ftp)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_title)
	_meta = Label.new()
	_meta.modulate = Color(1, 1, 1, 0.7)
	right.add_child(_meta)
	_desc = RichTextLabel.new()
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc.fit_content = false
	right.add_child(_desc)
	_error = Label.new()
	_error.modulate = Color(1, 0.5, 0.5)
	right.add_child(_error)

	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 12)
	right.add_child(dev_row)
	_devices_l = Label.new()
	_devices_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_devices_l.modulate = Color(1, 1, 1, 0.7)
	dev_row.add_child(_devices_l)
	var dev_btn := Button.new()
	dev_btn.text = "Devices…"
	dev_btn.pressed.connect(func() -> void: App.go_to("res://ui/screens/devices_screen.tscn"))
	dev_row.add_child(dev_btn)

	_ride = Button.new()
	_ride.text = "Ride on simulator"
	_ride.custom_minimum_size.y = 44
	_ride.pressed.connect(_on_ride_pressed)
	right.add_child(_ride)

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.zwo ; Zwift workout"])
	_dialog.file_selected.connect(_on_file_chosen)
	add_child(_dialog)
