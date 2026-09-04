class_name SettingsPanel
extends VBoxContainer
## Settings for a side sheet: rider, connectors, look (with live preview and
## the scene tuning sliders). Saves as values change.

var _ftp: SpinBox
var _key: LineEdit
var _key_status: Label
var _strava_id: LineEdit
var _strava_secret: LineEdit
var _strava_status: Label
var _strava_connect: Button
var _shake: OptionButton


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_ui()
	Sync.intervals().test_finished.connect(func(ok: bool, msg: String) -> void:
		_key_status.text = msg
		_key_status.modulate = Color(0.6, 1, 0.6) if ok else Color(1, 0.6, 0.6))
	Sync.strava().auth_state_changed.connect(func(ok: bool, msg: String) -> void:
		_strava_status.text = msg
		_strava_status.modulate = Color(0.6, 1, 0.6) if ok else Color(1, 1, 1, 0.7)
		_strava_connect.text = "Disconnect" if Sync.strava().is_configured() else "Connect")


func save() -> void:
	App.ftp = int(_ftp.value)
	App.save_settings()
	var key := _key.text.strip_edges()
	if key != App.get_secret("intervals_api_key"):
		App.set_secret("intervals_api_key", key)
		Sync.configure_intervals(key)
	_save_strava_app()


func _save_strava_app() -> void:
	var cid := _strava_id.text.strip_edges()
	var sec := _strava_secret.text.strip_edges()
	if cid != App.get_secret("strava_client_id") or sec != App.get_secret("strava_client_secret"):
		App.set_secret("strava_client_id", cid)
		App.set_secret("strava_client_secret", sec)
		Sync.configure_strava(cid, sec)


func _strava_button() -> void:
	_save_strava_app()
	var s := Sync.strava()
	if s.is_configured():
		s.disconnect_account()
		App.set_secret("strava_refresh_token", "")
		App.set_secret("strava_access_token", "")
	else:
		s.connect_account()


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
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	# --- Rider & sync ---
	var rider := VBoxContainer.new()
	rider.name = "Rider & sync"
	rider.add_theme_constant_override("separation", 10)
	tabs.add_child(rider)
	_section(rider, "Rider")
	var ftp_row := HBoxContainer.new()
	rider.add_child(ftp_row)
	HudStyle.label(ftp_row, "FTP (W)", 14, 500).custom_minimum_size.x = 120
	_ftp = SpinBox.new()
	_ftp.min_value = 50
	_ftp.max_value = 600
	_ftp.value = App.ftp
	_ftp.value_changed.connect(func(_v: float) -> void: save())
	ftp_row.add_child(_ftp)

	_section(rider, "intervals.icu")
	_help(rider, "Paste your personal API key from intervals.icu → Settings → Developer Settings. Planned workouts from your calendar show up on the home screen, and finished rides can be shared there.")
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	rider.add_child(key_row)
	_key = LineEdit.new()
	_key.secret = true
	_key.text = App.get_secret("intervals_api_key")
	_key.placeholder_text = "API key"
	_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key.text_submitted.connect(func(_t: String) -> void: save())
	_key.focus_exited.connect(save)
	key_row.add_child(_key)
	HudStyle.button(key_row, "Test", 13, _test_key)
	_key_status = HudStyle.label(rider, "", 12, 500, HudStyle.TEXT_DIM)

	_section(rider, "Strava")
	_help(rider, "Create an API application at strava.com/settings/api with Authorization Callback Domain \"localhost\", paste its Client ID and Client Secret, then press Connect. Strava requires a subscription for API apps and accepts no photos from third-party apps; add screenshots in the Strava app.")
	_strava_id = LineEdit.new()
	_strava_id.text = App.get_secret("strava_client_id")
	_strava_id.placeholder_text = "Client ID"
	_strava_id.focus_exited.connect(_save_strava_app)
	rider.add_child(_strava_id)
	var sec_row := HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 8)
	rider.add_child(sec_row)
	_strava_secret = LineEdit.new()
	_strava_secret.secret = true
	_strava_secret.text = App.get_secret("strava_client_secret")
	_strava_secret.placeholder_text = "Client Secret"
	_strava_secret.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strava_secret.focus_exited.connect(_save_strava_app)
	sec_row.add_child(_strava_secret)
	_strava_connect = HudStyle.button(sec_row, "Disconnect" if Sync.strava().is_configured() else "Connect", 13, _strava_button)
	_strava_status = HudStyle.label(rider, ("Connected as %s" % Sync.strava().athlete_name) if Sync.strava().is_configured() else "Not connected", 12, 500,
		Color(0.6, 1, 0.6) if Sync.strava().is_configured() else HudStyle.TEXT_DIM)

	# --- Look ---
	var look := VBoxContainer.new()
	look.name = "Look"
	look.add_theme_constant_override("separation", 8)
	tabs.add_child(look)
	var opts := GridContainer.new()
	opts.columns = 2
	opts.add_theme_constant_override("h_separation", 12)
	opts.add_theme_constant_override("v_separation", 6)
	look.add_child(opts)
	HudStyle.label(opts, "Look", 14, 500)
	var look_ob := OptionButton.new()
	look_ob.add_item("8-bit  (palette, chunky)")
	look_ob.add_item("16-bit (posterized, finer)")
	look_ob.add_item("Off    (native)")
	look_ob.selected = ["8bit", "16bit", "off"].find(App.look_mode)
	opts.add_child(look_ob)
	HudStyle.label(opts, "Camera shake", 14, 500)
	_shake = OptionButton.new()
	for o in ["Off", "Low", "High"]:
		_shake.add_item(o)
	_shake.selected = ["off", "low", "high"].find(App.camera_shake)
	opts.add_child(_shake)
	HudStyle.label(opts, "FPS readout", 14, 500)
	var fps_cb := CheckButton.new()
	fps_cb.button_pressed = App.show_fps
	fps_cb.toggled.connect(func(on: bool) -> void: App.show_fps = on; App.save_settings())
	opts.add_child(fps_cb)

	var preview := RideScene.new()
	preview.custom_minimum_size = Vector2(0, 250)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.riding = true
	preview.power = 200.0
	preview.cadence = 88.0
	look.add_child(preview)
	look_ob.item_selected.connect(func(i: int) -> void:
		App.look_mode = ["8bit", "16bit", "off"][i]
		App.save_settings()
		preview.set_look_mode(App.look_mode))
	_shake.item_selected.connect(func(i: int) -> void:
		App.camera_shake = ["off", "low", "high"][i]
		App.save_settings()
		preview.set_shake(App.camera_shake))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	look.add_child(scroll)
	var panel := TuningPanel.new()
	panel.scene = preview
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)


func _section(parent: Control, title: String) -> void:
	var l := HudStyle.label(parent, title, 15, 700, HudStyle.TEXT_DIM)
	l.add_theme_constant_override("line_spacing", 0)


func _help(parent: Control, text: String) -> void:
	var l := HudStyle.label(parent, text, 12, 500, Color(1, 1, 1, 0.55))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
