class_name SettingsPanel
extends VBoxContainer
## Settings for the side sheet: two pages (Rider & sync, Look) picked with a
## segmented control, each a scroll of cards. Values save as they change.

var _pages: Array[Control] = []
var _tabs: HBoxContainer
var _ftp: LineEdit
var _weight: LineEdit
var _key: LineEdit
var _key_status: Label
var _strava_id: LineEdit
var _strava_secret: LineEdit
var _strava_status: Label
var _strava_connect: Button
var _update_status: Label
var _about: Control


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_build_ui()
	Sync.intervals().test_finished.connect(func(ok: bool, msg: String) -> void:
		_set_status(_key_status, msg, ok))
	Sync.strava().auth_state_changed.connect(func(ok: bool, msg: String) -> void:
		_set_status(_strava_status, msg, ok)
		_strava_connect.text = "Disconnect" if Sync.strava().is_configured() else "Connect")


func save() -> void:
	App.ftp = clampi(int(_ftp.text), 50, 600)
	_ftp.text = str(App.ftp)
	_save_weight()
	App.save_settings()
	var key := _key.text.strip_edges()
	if key != App.get_secret("intervals_api_key"):
		App.set_secret("intervals_api_key", key)
		Sync.configure_intervals(key)
	_save_strava_app()


func _weight_text() -> String:
	return "%d" % int(round(App.weight_kg * (2.20462 if App.imperial() else 1.0)))


func _save_weight() -> void:
	var v := float(_weight.text)
	if v <= 0.0:
		_weight.text = _weight_text()
		return
	var kg := v / (2.20462 if App.imperial() else 1.0)
	App.weight_kg = clampf(kg, 30.0, 200.0)
	App.save_settings()
	_weight.text = _weight_text()


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
		_set_status(_key_status, "Enter an API key first", false)
		return
	Sync.intervals().api_key = key
	_key_status.text = "Testing…"
	_key_status.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	Sync.intervals().test_connection()


func _set_status(l: Label, msg: String, ok: bool) -> void:
	l.text = ("●  " if msg != "" else "") + msg
	l.add_theme_color_override("font_color", HudStyle.OK_GREEN if ok else HudStyle.WARN_RED)


## Select a page as if its tab were clicked.
func show_page(i: int) -> void:
	_tabs.get_child(i).pressed.emit()


## Show the About card (version and updates), for the app menu's "About Groove".
func show_about() -> void:
	show_page(0)
	await get_tree().process_frame   # the cards need a layout pass before they can be scrolled to
	(_pages[0] as ScrollContainer).ensure_control_visible(_about)


func _show_page(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i


func _page() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)
	_pages.append(scroll)
	return v


func _build_ui() -> void:
	_tabs = HudStyle.segmented(self, ["Rider & sync", "Look"], 0, _show_page, 14)

	# --- Rider & sync ---
	var rider := _page()
	var r := HudStyle.section(rider, "Rider")
	var ftp_row := HudStyle.row(r, "FTP")
	_ftp = HudStyle.input(ftp_row, str(App.ftp))
	_ftp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ftp.custom_minimum_size.x = 84
	_ftp.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ftp.text_submitted.connect(func(_t: String) -> void: save())
	_ftp.focus_exited.connect(save)
	HudStyle.label(ftp_row, "watts", 13, 500, HudStyle.TEXT_DIM).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Weight with its unit beside it; the unit choice also switches the HUD to mph and miles.
	var w_row := HudStyle.row(r, "Weight")
	_weight = HudStyle.input(w_row, _weight_text())
	_weight.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_weight.custom_minimum_size.x = 84
	_weight.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weight.text_submitted.connect(func(_t: String) -> void: _save_weight())
	_weight.focus_exited.connect(_save_weight)
	HudStyle.segmented(w_row, ["kg", "lbs"], 1 if App.imperial() else 0, func(i: int) -> void:
		_save_weight()
		App.units = "imperial" if i == 1 else "metric"
		App.save_settings()
		_weight.text = _weight_text())

	var ride := HudStyle.section(rider, "Ride",
		"With auto-pause on, the workout starts when you start pedalling, stops the clock when you stop and carries on when you pedal again, as Zwift does. Off: only the Start and Pause buttons do.")
	HudStyle.segmented(HudStyle.row(ride, "Auto-pause"), ["On", "Off"], 0 if App.auto_pause else 1,
		func(i: int) -> void:
			App.auto_pause = i == 0
			App.save_settings())

	var icu := HudStyle.section(rider, "intervals.icu",
		"Personal API key from intervals.icu → Settings → Developer Settings. Planned workouts appear on the home screen and finished rides can be shared.")
	var key_row := HudStyle.row(icu, "API key")
	_key = HudStyle.input(key_row, App.get_secret("intervals_api_key"), "Paste key", true)
	_key.text_submitted.connect(func(_t: String) -> void: save())
	_key.focus_exited.connect(save)
	HudStyle.button(key_row, "Test", 13, _test_key)
	_key_status = _status_line(icu, "", false)

	var strava := HudStyle.section(rider, "Strava",
		"Needs your own API app from strava.com/settings/api with callback domain \"localhost\". Strava's API takes no photos from other apps; add ride screenshots in the Strava app.")
	_strava_id = HudStyle.input(HudStyle.row(strava, "Client ID"), App.get_secret("strava_client_id"), "Client ID")
	_strava_id.focus_exited.connect(_save_strava_app)
	_strava_secret = HudStyle.input(HudStyle.row(strava, "Client secret"), App.get_secret("strava_client_secret"), "Client secret", true)
	_strava_secret.focus_exited.connect(_save_strava_app)
	var connected := Sync.strava().is_configured()
	var foot := HudStyle.row(strava, "")
	_strava_status = _status_line(foot, ("Connected as %s" % Sync.strava().athlete_name) if connected else "Not connected", connected)
	_strava_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strava_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # never widens the sheet
	_strava_connect = HudStyle.button(foot, "Disconnect" if connected else "Connect", 13, _strava_button, "secondary")

	# --- About ---
	var about := HudStyle.section(rider, "About")
	_about = about
	var ver_row := HudStyle.row(about, "Version")
	HudStyle.label(ver_row, "Groove %s" % Updates.current_version, 13, 700).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var upd_row := HudStyle.row(about, "Updates")
	var check_btn := HudStyle.button(upd_row, "Check now", 13, func() -> void: Updates.check(true))
	_update_status = _status_line(upd_row, "", false)
	_update_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var get_btn := HudStyle.button(upd_row, "Update", 13, func() -> void:
		var screen := get_tree().current_scene
		if screen and screen.has_method("open_update"):
			screen.call("open_update"), "primary")
	get_btn.visible = false
	Updates.checked.connect(func(available: bool, msg: String) -> void:
		_set_status(_update_status, msg, not available and msg == "Up to date")
		get_btn.visible = available
		_update_status.visible = not available   # the button carries the version instead
		if available:
			get_btn.text = ("Update to %s" % Updates.latest.version).to_upper())
	check_btn.pressed.connect(func() -> void:
		_update_status.visible = true
		_update_status.text = "Checking…")
	if not Updates.latest.is_empty():
		Updates.checked.emit(Updates.update_available(), "Groove %s is available" % Updates.latest.version if Updates.update_available() else "Up to date")

	# --- Look ---
	var look := _page()
	var l := HudStyle.section(look, "Look")
	var preview := RideScene.new()
	preview.custom_minimum_size = Vector2(0, 240)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.riding = true
	preview.power = 200.0
	preview.cadence = 88.0
	var looks := ["16bit", "off", "real"]
	var look_note := HudStyle.label(l, "", 12, 500, HudStyle.TEXT_DIM)
	look_note.visible = false
	var qualities := ["low", "medium", "high"]
	var quality_row := HudStyle.row(l, "Quality")
	HudStyle.segmented(quality_row, ["Low", "Medium", "High"], maxi(qualities.find(App.real_quality), 0),
		func(i: int) -> void:
			App.real_quality = qualities[i]
			App.save_settings()
			# Plants, grass, shadows and effects are read when the ride's world is built.
			look_note.text = "Quality applies from the next ride."
			look_note.visible = true)
	quality_row.visible = App.look_mode == "real"
	HudStyle.segmented(HudStyle.row(l, "Look"), ["Pixel", "Smooth", "Realistic"], maxi(looks.find(App.look_mode), 0),
		func(i: int) -> void:
			var was_real: bool = App.look_mode == "real"
			App.look_mode = looks[i]
			App.save_settings()
			preview.set_look_mode(App.look_mode)
			# The realistic look (first person, its own sky and plants) is built with the world.
			look_note.text = "Realistic shows from the next ride." if (App.look_mode == "real") != was_real else ""
			quality_row.visible = App.look_mode == "real"
			look_note.visible = look_note.text != "")
	l.move_child(quality_row, l.get_child_count() - 1)
	l.move_child(look_note, l.get_child_count() - 1)
	var times := ["live", "morning", "noon", "sunset", "night"]
	HudStyle.segmented(HudStyle.row(l, "Time of day"), ["Live", "Morning", "Noon", "Sunset", "Night"], maxi(times.find(App.time_of_day), 0),
		func(i: int) -> void:
			App.time_of_day = times[i]
			App.save_settings()
			preview.set_time_mode(App.time_of_day))
	HudStyle.segmented(HudStyle.row(l, "FPS readout"), ["Hide", "Show"], 1 if App.show_fps else 0,
		func(i: int) -> void:
			App.show_fps = i == 1
			App.save_settings())
	l.add_child(preview)

	var tuning := TuningPanel.new()
	tuning.embedded = true
	tuning.scene = preview
	var t := HudStyle.section(look, "Scene tuning", "", "Reset", tuning.reset)
	t.add_child(tuning)
	_show_page(0)


func _status_line(parent: Control, text: String, ok: bool) -> Label:
	var l := HudStyle.label(parent, ("●  " if text != "" else "") + text, 12, 700, HudStyle.OK_GREEN if ok else HudStyle.TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l
