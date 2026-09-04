class_name DevicesPanel
extends VBoxContainer
## Pairing controls for a side sheet: active trainer and heart-rate sensor,
## scan, connect the selected device, simulator fallback.

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
var _live_power := -1
var _live_bpm := -1


func _ready() -> void:
	add_theme_constant_override("separation", 10)
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
	var role := Devices.role_of(addr)
	var name := str(info.get("name", ""))
	# Nameless advertisers (phones, beacons, "<null>" from the BLE layer) are noise
	# in a list of trainers and straps; only a remembered device earns a row without a name.
	if (name == "" or name == "<null>") and role == "":
		return
	var label := "%s   %d dBm%s" % [name if name != "" and name != "<null>" else "(unnamed)", info.rssi,
		("   · remembered " + role.replace("_", " ")) if role != "" else ""]
	var i := _addresses.find(addr)
	if i >= 0:
		_list.set_item_text(i, label)
	else:
		_addresses.append(addr)
		_list.add_item(label)


func _on_connect_pressed() -> void:
	var sel := _list.get_selected_items()
	if not sel.is_empty():
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
	_adapter_l = HudStyle.label(self, "", 13, 500, HudStyle.TEXT_DIM)
	var tcard := _card("Trainer")
	_trainer_name = HudStyle.label(tcard, "", 18, 700)
	_trainer_state = HudStyle.label(tcard, "", 13, 500, HudStyle.TEXT_DIM)
	_trainer_live = HudStyle.label(tcard, "", 26, 900)
	HudStyle.button(tcard, "Forget", 13, func() -> void: Devices.forget("trainer"); _refresh()).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var hcard := _card("Heart rate")
	_hr_name = HudStyle.label(hcard, "", 18, 700)
	_hr_state = HudStyle.label(hcard, "", 13, 500, HudStyle.TEXT_DIM)
	_hr_live = HudStyle.label(hcard, "", 26, 900)
	HudStyle.button(hcard, "Forget", 13, func() -> void: Devices.forget("heart_rate"); _refresh()).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var scan_row := HBoxContainer.new()
	scan_row.add_theme_constant_override("separation", 8)
	add_child(scan_row)
	HudStyle.label(scan_row, "Nearby devices", 16, 700).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scan_btn = HudStyle.button(scan_row, "Scan", 14, _on_scan_pressed)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 160
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i: int) -> void: _on_connect_pressed())
	add_child(_list)
	_status_l = HudStyle.label(self, "", 13, 500, HudStyle.TEXT_DIM)
	_status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	HudStyle.button(bar, "Connect selected", 14, _on_connect_pressed)
	HudStyle.button(bar, "Use simulator", 14, func() -> void: Devices.use_simulated_devices())


func _card(heading: String) -> VBoxContainer:
	var panel := HudStyle.panel(self, HudStyle.PANEL_ROW, 8, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	HudStyle.label(box, heading, 12, 700, HudStyle.TEXT_DIM)
	return box
