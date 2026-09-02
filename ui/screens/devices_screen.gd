extends Control
## Pairing screen: shows the active trainer and heart-rate sensor, scans for
## Bluetooth devices, and connects the one you pick. Roles are assigned from
## the services a device exposes, so there is nothing to choose.

var _adapter_l: Label
var _status_l: Label
var _trainer_name: Label
var _trainer_state: Label
var _trainer_live: Label
var _hr_name: Label
var _hr_state: Label
var _hr_live: Label
var _scan_btn: Button
var _list: ItemList
var _addresses: Array[String] = []
var _connect_btn: Button

var _live_power := -1
var _live_bpm := -1


func _ready() -> void:
	_build_ui()
	Devices.adapter_state_changed.connect(func(_ok: bool, _e: String) -> void: _refresh())
	Devices.scan_state_changed.connect(func(_s: bool) -> void: _refresh())
	Devices.device_found.connect(_on_device_found)
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _wire_live(); _refresh())
	Devices.heart_rate_sensor_changed.connect(func(_h: HeartRateSensor) -> void: _wire_live(); _refresh())
	Devices.status.connect(func(s: String) -> void: _status_l.text = s)
	for addr in Devices.discovered:
		_on_device_found(Devices.discovered[addr])
	_wire_live()
	_refresh()
	if Devices.adapter_ready() and not Devices.is_scanning():
		Devices.start_scan(15.0)


func _wire_live() -> void:
	_live_power = -1
	_live_bpm = -1
	if Devices.trainer != null and not Devices.trainer.power_changed.is_connected(_on_power):
		Devices.trainer.power_changed.connect(_on_power)
		Devices.trainer.connected.connect(_refresh)
		Devices.trainer.disconnected.connect(_refresh)
	if Devices.heart_rate != null and not Devices.heart_rate.heart_rate_changed.is_connected(_on_bpm):
		Devices.heart_rate.heart_rate_changed.connect(_on_bpm)
		Devices.heart_rate.connected.connect(_refresh)
		Devices.heart_rate.disconnected.connect(_refresh)


func _on_power(w: int) -> void:
	_live_power = w
	_trainer_live.text = "%d W" % w


func _on_bpm(b: int) -> void:
	_live_bpm = b
	_hr_live.text = "%d bpm" % b


func _refresh() -> void:
	if Devices.adapter_ready():
		_adapter_l.text = "Bluetooth ready" + ("  ·  scanning…" if Devices.is_scanning() else "")
	else:
		_adapter_l.text = "Bluetooth: " + (Devices.adapter_error() if Devices.adapter_error() != "" else "starting…")
	_scan_btn.text = "Stop scan" if Devices.is_scanning() else "Scan"
	_scan_btn.disabled = not Devices.adapter_ready()

	var t := Devices.trainer
	var remembered_t: Dictionary = Devices.remembered.get("trainer", {})
	_trainer_name.text = t.display_name() if t else str(remembered_t.get("name", "No trainer"))
	_trainer_state.text = _state_text(t, remembered_t)
	if _live_power < 0:
		_trainer_live.text = ""

	var h := Devices.heart_rate
	var remembered_h: Dictionary = Devices.remembered.get("heart_rate", {})
	_hr_name.text = h.display_name() if h else str(remembered_h.get("name", "No heart-rate sensor"))
	_hr_state.text = _state_text(h, remembered_h)
	if _live_bpm < 0:
		_hr_live.text = ""


func _state_text(dev: Node, remembered: Dictionary) -> String:
	if dev == null:
		return "Remembered, not found yet" if not remembered.is_empty() else "Not paired"
	if dev is SimulatedTrainer or dev is SimulatedHeartRate:
		return "Simulated"
	return "Connected" if dev.is_device_connected() else "Reconnecting…"


func _on_device_found(info: Dictionary) -> void:
	var addr: String = info.address
	var label := "%s   %d dBm%s" % [
		info.name if info.name != "" else "(unnamed)", info.rssi,
		("   · remembered " + Devices.role_of(addr).replace("_", " ")) if Devices.role_of(addr) != "" else ""]
	var i := _addresses.find(addr)
	if i >= 0:
		_list.set_item_text(i, label)
	else:
		_addresses.append(addr)
		_list.add_item(label)


func _on_connect_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	Devices.pair(_addresses[sel[0]])


func _on_scan_pressed() -> void:
	if Devices.is_scanning():
		Devices.stop_scan()
	else:
		_list.clear()
		_addresses.clear()
		Devices.discovered.clear()
		Devices.start_scan(15.0)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	var title := _label(top, "Devices", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adapter_l = _label(top, "", 16)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	v.add_child(cards)
	var tcard := _card(cards, "Trainer")
	_trainer_name = _label(tcard, "", 20)
	_trainer_state = _label(tcard, "", 14)
	_trainer_live = _label(tcard, "", 32)
	var tf := _button(tcard, "Forget", func() -> void: Devices.forget("trainer"); _refresh())
	tf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var hcard := _card(cards, "Heart rate")
	_hr_name = _label(hcard, "", 20)
	_hr_state = _label(hcard, "", 14)
	_hr_live = _label(hcard, "", 32)
	var hf := _button(hcard, "Forget", func() -> void: Devices.forget("heart_rate"); _refresh())
	hf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var scan_row := HBoxContainer.new()
	scan_row.add_theme_constant_override("separation", 8)
	v.add_child(scan_row)
	_label(scan_row, "Nearby devices", 18).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scan_btn = _button(scan_row, "Scan", _on_scan_pressed)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i: int) -> void: _on_connect_pressed())
	v.add_child(_list)

	_status_l = _label(v, "", 14)
	_status_l.modulate = Color(1, 1, 1, 0.7)
	_status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_connect_btn = _button(bar, "Connect selected", _on_connect_pressed)
	_button(bar, "Use simulator", func() -> void: Devices.use_simulated_devices())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_button(bar, "Home", func() -> void: App.go_to("res://ui/screens/home_screen.tscn"))


func _card(parent: Control, heading: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(m)
	var box := VBoxContainer.new()
	m.add_child(box)
	var h := _label(box, heading, 14)
	h.modulate = Color(1, 1, 1, 0.6)
	return box


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
