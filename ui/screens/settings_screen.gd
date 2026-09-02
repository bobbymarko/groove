extends Control
## Settings: rider, connectors, scene.

var _ftp: SpinBox
var _key: LineEdit
var _key_status: Label
var _shake: OptionButton


func _ready() -> void:
	_build_ui()
	Sync.intervals().test_finished.connect(func(ok: bool, msg: String) -> void:
		_key_status.text = msg
		_key_status.modulate = Color(0.6, 1, 0.6) if ok else Color(1, 0.6, 0.6))


func _save() -> void:
	App.ftp = int(_ftp.value)
	App.camera_shake = ["off", "low", "high"][_shake.selected]
	App.save_settings()
	var key := _key.text.strip_edges()
	if key != App.get_secret("intervals_api_key"):
		App.set_secret("intervals_api_key", key)
		Sync.configure_intervals(key)
	_key_status.text = "Saved"
	_key_status.modulate = Color(1, 1, 1, 0.7)


func _test_key() -> void:
	var key := _key.text.strip_edges()
	if key == "":
		_key_status.text = "Enter an API key first"
		return
	Sync.intervals().api_key = key
	_key_status.text = "Testing…"
	_key_status.modulate = Color(1, 1, 1, 0.7)
	Sync.intervals().test_connection()


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
	_label(v, "Settings", 30)

	_label(v, "Rider", 18)
	var ftp_row := HBoxContainer.new()
	v.add_child(ftp_row)
	_label(ftp_row, "FTP (W)", 15).custom_minimum_size.x = 160
	_ftp = SpinBox.new()
	_ftp.min_value = 50
	_ftp.max_value = 600
	_ftp.value = App.ftp
	ftp_row.add_child(_ftp)

	_label(v, "intervals.icu", 18)
	var help := _label(v, "Paste your personal API key. Find it at intervals.icu → Settings → Developer Settings. Rides upload automatically when they finish.", 13)
	help.modulate = Color(1, 1, 1, 0.6)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	v.add_child(key_row)
	_label(key_row, "API key", 15).custom_minimum_size.x = 160
	_key = LineEdit.new()
	_key.secret = true
	_key.text = App.get_secret("intervals_api_key")
	_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key.placeholder_text = "API key"
	key_row.add_child(_key)
	_button(key_row, "Test", _test_key)
	_key_status = _label(v, "", 13)
	_key_status.modulate = Color(1, 1, 1, 0.7)

	_label(v, "Scene", 18)
	var shake_row := HBoxContainer.new()
	v.add_child(shake_row)
	_label(shake_row, "Camera shake", 15).custom_minimum_size.x = 160
	_shake = OptionButton.new()
	for o in ["Off", "Low", "High"]:
		_shake.add_item(o)
	_shake.selected = ["off", "low", "high"].find(App.camera_shake)
	shake_row.add_child(_shake)

	# Scene tuning with a live preview.
	var tune_row := HBoxContainer.new()
	tune_row.add_theme_constant_override("separation", 16)
	tune_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tune_row)
	var preview := RideScene.new()
	preview.custom_minimum_size = Vector2(560, 315)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.riding = true
	preview.power = 200.0
	preview.cadence = 88.0
	tune_row.add_child(preview)
	var panel := TuningPanel.new()
	panel.scene = preview
	panel.custom_minimum_size.x = 520
	tune_row.add_child(panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_button(bar, "Save", _save)
	_button(bar, "Open rides folder", func() -> void: OS.shell_open(RideRecorder.rides_dir_abs()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_button(bar, "Home", func() -> void: _save(); App.go_to("res://ui/screens/home_screen.tscn"))


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
