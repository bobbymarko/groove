extends Control
## Milestone 0 spike: connect to a Wahoo KICKR CORE over Bluetooth via GDBLE,
## read live power and cadence from FTMS Indoor Bike Data, and hold a target
## power in ERG mode through the FTMS Control Point.
##
## Throwaway code. The real device layer lives in devices/ once this proves out.

const FTMS_SERVICE := "00001826-0000-1000-8000-00805f9b34fb"
const INDOOR_BIKE_DATA := "00002ad2-0000-1000-8000-00805f9b34fb"
const CONTROL_POINT := "00002ad9-0000-1000-8000-00805f9b34fb"
const MACHINE_STATUS := "00002ada-0000-1000-8000-00805f9b34fb"
const SUPPORTED_POWER_RANGE := "00002ad8-0000-1000-8000-00805f9b34fb"

# FTMS Control Point opcodes
const OP_REQUEST_CONTROL := 0x00
const OP_RESET := 0x01
const OP_SET_TARGET_POWER := 0x05
const OP_START_RESUME := 0x07
const OP_STOP_PAUSE := 0x08
const OP_RESPONSE := 0x80

const RESULT_NAMES := {
	0x01: "success", 0x02: "not supported", 0x03: "invalid parameter",
	0x04: "operation failed", 0x05: "control not permitted",
}

var _bt: BluetoothManager
var _device: BleDevice
var _scan_deadline := 0.0
var _has_control := false
var _target_w := 150
var _write_queue: Array[PackedByteArray] = []
var _write_in_flight := false

# UI
var _status: Label
var _power: Label
var _cadence: Label
var _speed: Label
var _target: Label
var _devices: ItemList
var _log: RichTextLabel
var _discovered: Array[Dictionary] = []


func _ready() -> void:
	_build_ui()
	_bt = BluetoothManager.new()
	add_child(_bt)
	_bt.set_debug_mode(true)
	_bt.adapter_initialized.connect(_on_adapter_initialized)
	_bt.device_discovered.connect(_on_device_discovered)
	_bt.device_updated.connect(_on_device_discovered)
	_bt.scan_stopped.connect(func(): _log_line("Scan stopped"))
	_bt.error_occurred.connect(func(msg: String): _log_line("[color=red]Adapter error: %s[/color]" % msg))
	_set_status("Initializing Bluetooth adapter…")
	_bt.initialize()


# --- Bluetooth flow ---------------------------------------------------------

func _on_adapter_initialized(success: bool, error: String) -> void:
	if not success:
		_set_status("Bluetooth init failed: " + error)
		return
	_log_line("Adapter ready")
	_start_scan()


func _start_scan() -> void:
	_discovered.clear()
	_devices.clear()
	_set_status("Scanning… wake the trainer by turning the pedals")
	_bt.start_scan(20.0)


func _on_device_discovered(info: Dictionary) -> void:
	var address: String = info.get("address", "")
	var dname: String = info.get("name", "")
	for i in _discovered.size():
		if _discovered[i].get("address") == address:
			_discovered[i] = info
			_devices.set_item_text(i, _device_label(info))
			return
	_discovered.append(info)
	_devices.add_item(_device_label(info))
	if _device == null and "kickr" in dname.to_lower():
		_log_line("Found trainer: %s" % dname)
		_connect_to(address)


func _device_label(info: Dictionary) -> String:
	var dname: String = info.get("name", "")
	return "%s   (%s dBm)" % [dname if dname != "" else "<unnamed>", str(info.get("rssi", "?"))]


func _on_device_selected(index: int) -> void:
	if _device != null:
		return
	_connect_to(_discovered[index].get("address", ""))


func _connect_to(address: String) -> void:
	_bt.stop_scan()
	_device = _bt.connect_device(address)
	if _device == null:
		_set_status("connect_device returned null")
		return
	_device.connected.connect(_on_connected)
	_device.disconnected.connect(_on_disconnected)
	_device.connection_failed.connect(func(err: String): _set_status("Connection failed: " + err))
	_device.services_discovered.connect(_on_services_discovered)
	_device.characteristic_notified.connect(_on_notified)
	_device.characteristic_read.connect(_on_read)
	_device.characteristic_written.connect(_on_written)
	_device.operation_failed.connect(_on_operation_failed)
	_set_status("Connecting to %s…" % address)
	_device.connect_async()


func _on_connected() -> void:
	_set_status("Connected. Discovering services…")
	_device.discover_services()


func _on_disconnected() -> void:
	_set_status("Disconnected")
	_has_control = false
	_write_queue.clear()
	_write_in_flight = false
	_device = null


func _on_services_discovered(services: Array) -> void:
	var has_ftms := false
	for s in services:
		var suuid := _norm(s.get("uuid", ""))
		_log_line("Service %s" % suuid)
		for c in s.get("characteristics", []):
			_log_line("    char %s %s" % [_norm(c.get("uuid", "")), _props(c.get("properties", {}))])
		if suuid == FTMS_SERVICE:
			has_ftms = true
	if not has_ftms:
		_set_status("No FTMS service on this device")
		return
	_set_status("FTMS found. Subscribing…")
	_device.subscribe_characteristic(FTMS_SERVICE, CONTROL_POINT)
	_device.subscribe_characteristic(FTMS_SERVICE, INDOOR_BIKE_DATA)
	_device.subscribe_characteristic(FTMS_SERVICE, MACHINE_STATUS)
	_device.read_characteristic(FTMS_SERVICE, SUPPORTED_POWER_RANGE)
	# Take control, start the session, then apply the initial target.
	_enqueue(PackedByteArray([OP_REQUEST_CONTROL]))
	_enqueue(PackedByteArray([OP_START_RESUME]))
	_enqueue(_target_power_cmd(_target_w))


func _on_read(char_uuid: String, data: PackedByteArray) -> void:
	if _norm(char_uuid) == SUPPORTED_POWER_RANGE and data.size() >= 6:
		var lo := data.decode_s16(0)
		var hi := data.decode_s16(2)
		var step := data.decode_u16(4)
		_log_line("Supported power range: %d–%d W, step %d" % [lo, hi, step])


func _on_notified(char_uuid: String, data: PackedByteArray) -> void:
	match _norm(char_uuid):
		INDOOR_BIKE_DATA:
			_parse_indoor_bike_data(data)
		CONTROL_POINT:
			_parse_control_response(data)
		MACHINE_STATUS:
			_log_line("Machine status: %s" % _hex(data))


func _on_written(char_uuid: String) -> void:
	_write_in_flight = false
	_send_next()


func _on_operation_failed(op: String, err: String) -> void:
	_log_line("[color=red]%s failed: %s[/color]" % [op, err])
	if op == "write":
		_write_in_flight = false
		_send_next()


# --- FTMS Control Point ------------------------------------------------------

func _enqueue(cmd: PackedByteArray) -> void:
	_write_queue.append(cmd)
	_send_next()


func _send_next() -> void:
	if _write_in_flight or _write_queue.is_empty() or _device == null:
		return
	var cmd: PackedByteArray = _write_queue.pop_front()
	_write_in_flight = true
	_log_line("→ control point %s" % _hex(cmd))
	_device.write_characteristic(FTMS_SERVICE, CONTROL_POINT, cmd, true)


func _target_power_cmd(watts: int) -> PackedByteArray:
	var cmd := PackedByteArray([OP_SET_TARGET_POWER, 0, 0])
	cmd.encode_s16(1, watts)
	return cmd


func _set_target(watts: int) -> void:
	_target_w = clampi(watts, 0, 2000)
	_target.text = "Target %d W" % _target_w
	if _device != null and _device.is_connected():
		_enqueue(_target_power_cmd(_target_w))


func _parse_control_response(data: PackedByteArray) -> void:
	if data.size() < 3 or data[0] != OP_RESPONSE:
		_log_line("Control point notify: %s" % _hex(data))
		return
	var op := data[1]
	var result := data[2]
	var ok := result == 0x01
	_log_line("← response to op 0x%02X: %s" % [op, RESULT_NAMES.get(result, "0x%02X" % result)])
	if op == OP_REQUEST_CONTROL and ok:
		_has_control = true
		_set_status("ERG control granted")
	elif op == OP_SET_TARGET_POWER and ok:
		_set_status("Holding %d W" % _target_w)


# --- FTMS Indoor Bike Data (0x2AD2) -----------------------------------------

func _parse_indoor_bike_data(d: PackedByteArray) -> void:
	if d.size() < 2:
		return
	var flags := d.decode_u16(0)
	var i := 2
	var speed_kph := NAN
	var cadence_rpm := NAN
	var power_w := NAN

	if not (flags & (1 << 0)):  # More Data bit clear => instantaneous speed present
		if i + 2 <= d.size():
			speed_kph = d.decode_u16(i) * 0.01
		i += 2
	if flags & (1 << 1): i += 2                     # average speed
	if flags & (1 << 2):                            # instantaneous cadence
		if i + 2 <= d.size():
			cadence_rpm = d.decode_u16(i) * 0.5
		i += 2
	if flags & (1 << 3): i += 2                     # average cadence
	if flags & (1 << 4): i += 3                     # total distance (uint24)
	if flags & (1 << 5): i += 2                     # resistance level
	if flags & (1 << 6):                            # instantaneous power
		if i + 2 <= d.size():
			power_w = d.decode_s16(i)
		i += 2
	# remaining fields (avg power, energy, HR, MET, times) not needed here

	if not is_nan(power_w):
		_power.text = "%d W" % int(power_w)
	if not is_nan(cadence_rpm):
		_cadence.text = "%d rpm" % int(round(cadence_rpm))
	if not is_nan(speed_kph):
		_speed.text = "%.1f km/h" % speed_kph


# --- helpers ----------------------------------------------------------------

func _norm(uuid: String) -> String:
	var u := uuid.to_lower().strip_edges()
	if u.length() == 4:
		u = "0000%s-0000-1000-8000-00805f9b34fb" % u
	return u


func _props(p: Dictionary) -> String:
	var out: Array[String] = []
	for k in ["read", "write", "write_without_response", "notify", "indicate"]:
		if p.get(k, false):
			out.append(k)
	return "[%s]" % ", ".join(out)


func _hex(b: PackedByteArray) -> String:
	var parts: Array[String] = []
	for x in b:
		parts.append("%02x" % x)
	return " ".join(parts)


func _set_status(s: String) -> void:
	_status.text = s
	_log_line("[b]%s[/b]" % s)


func _log_line(s: String) -> void:
	print_rich(s)
	_log.append_text(s + "\n")


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)

	_power = _big_label(left, "— W", 72)
	_cadence = _big_label(left, "— rpm", 36)
	_speed = _big_label(left, "— km/h", 24)
	_target = _big_label(left, "Target %d W" % _target_w, 28)

	var row := HBoxContainer.new()
	left.add_child(row)
	for w in [100, 150, 200, 250]:
		var b := Button.new()
		b.text = "%d W" % w
		b.pressed.connect(_set_target.bind(w))
		row.add_child(b)
	var row2 := HBoxContainer.new()
	left.add_child(row2)
	var minus := Button.new(); minus.text = "−10"; minus.pressed.connect(func(): _set_target(_target_w - 10)); row2.add_child(minus)
	var plus := Button.new(); plus.text = "+10"; plus.pressed.connect(func(): _set_target(_target_w + 10)); row2.add_child(plus)
	var rescan := Button.new(); rescan.text = "Rescan"; rescan.pressed.connect(_start_scan); row2.add_child(rescan)

	var dl := Label.new(); dl.text = "Devices (click to connect)"; left.add_child(dl)
	_devices = ItemList.new()
	_devices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_devices.item_selected.connect(_on_device_selected)
	left.add_child(_devices)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log)


func _big_label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
