extends Node
## Autoload "Devices". Owns the Bluetooth adapter, the active trainer and
## heart-rate sensor, pairing, remembered devices, and the simulator fallback.
## UI talks to this; it never touches Bluetooth directly.

signal adapter_state_changed(ok: bool, error: String)
signal scan_state_changed(scanning: bool)
signal device_found(info: Dictionary)          ## {address, name, rssi}
signal trainer_changed(trainer: Trainer)
signal heart_rate_sensor_changed(sensor: HeartRateSensor)
signal status(text: String)

const DEVICES_PATH := "user://devices.cfg"
const AUTO_CONNECT_SCAN_SECONDS := 20.0

var trainer: Trainer
var heart_rate: HeartRateSensor
var adapter: BleAdapter
var discovered: Dictionary = {}     ## address -> info
var remembered: Dictionary = {}     ## role ("trainer"|"heart_rate") -> {address, name}

var _pending: Dictionary = {}       ## address -> BlePeripheral being probed
var _adapter_ok := false
var _adapter_error := ""


func _ready() -> void:
	_load_remembered()
	status.connect(func(s: String) -> void: print("[devices] ", s))
	if DisplayServer.get_name() == "headless":
		return  # tests and tooling: never touch the radio
	adapter = BleAdapter.new()
	adapter.name = "BleAdapter"
	add_child(adapter)
	adapter.ready_changed.connect(_on_adapter_ready)
	adapter.device_found.connect(_on_device_found)
	adapter.scan_started.connect(func() -> void: scan_state_changed.emit(true))
	adapter.scan_stopped.connect(func() -> void: scan_state_changed.emit(false))
	adapter.adapter_error.connect(func(m: String) -> void: status.emit("Bluetooth: " + m))
	adapter.initialize()


# --- queries ---------------------------------------------------------------------

func adapter_ready() -> bool:
	return _adapter_ok


func adapter_error() -> String:
	return _adapter_error


func is_scanning() -> bool:
	return adapter != null and adapter.is_scanning()


func has_trainer() -> bool:
	return trainer != null and trainer.is_device_connected()


func has_real_trainer() -> bool:
	return trainer != null and trainer is FtmsTrainer


func real_trainer_ready() -> bool:
	return has_real_trainer() and trainer.is_device_connected()


func is_pairing(address: String) -> bool:
	return _pending.has(address)


func role_of(address: String) -> String:
	for role in remembered:
		if remembered[role].get("address", "") == address:
			return role
	return ""


# --- scanning and pairing --------------------------------------------------------

func start_scan(seconds := 15.0) -> void:
	if adapter == null or not _adapter_ok:
		status.emit("Bluetooth is not available" if _adapter_error == "" else _adapter_error)
		return
	adapter.start_scan(seconds)


func stop_scan() -> void:
	if adapter != null:
		adapter.stop_scan()


## Connect to a discovered device and assign it to whatever roles its services
## support (FTMS => trainer, Heart Rate => heart rate).
func pair(address: String) -> void:
	if adapter == null or _pending.has(address):
		return
	var info: Dictionary = discovered.get(address, {})
	var p := adapter.open(address, str(info.get("name", "")))
	_pending[address] = p
	status.emit("Connecting to %s…" % (p.name if p.name != "" else address))
	p.connected.connect(func() -> void: p.discover_services())
	p.connection_failed.connect(func(err: String) -> void:
		_pending.erase(address)
		status.emit("Could not connect to %s: %s" % [p.name, err]))
	p.services_discovered.connect(func(_s: Array) -> void: _assign_roles(p))
	p.connect_peripheral()


func forget(role: String) -> void:
	remembered.erase(role)
	_save_remembered()
	match role:
		"trainer":
			if trainer is FtmsTrainer:
				_drop_trainer()
		"heart_rate":
			if heart_rate is BleHeartRate:
				_drop_heart_rate()


func use_simulated_devices() -> void:
	if not (trainer is SimulatedTrainer):
		_drop_trainer()
		var t := SimulatedTrainer.new()
		t.name = "SimulatedTrainer"
		add_child(t)
		trainer = t
		t.connect_device()
		trainer_changed.emit(trainer)
	if heart_rate == null or heart_rate is SimulatedHeartRate:
		_drop_heart_rate()
		var hr := SimulatedHeartRate.new()
		hr.name = "SimulatedHeartRate"
		add_child(hr)
		hr.follow(trainer)
		heart_rate = hr
		hr.connect_device()
		heart_rate_sensor_changed.emit(heart_rate)
	status.emit("Using simulated trainer")


# --- internals -------------------------------------------------------------------

func _on_adapter_ready(ok: bool, error: String) -> void:
	_adapter_ok = ok
	_adapter_error = error
	adapter_state_changed.emit(ok, error)
	if ok and not remembered.is_empty():
		status.emit("Looking for your devices…")
		adapter.start_scan(AUTO_CONNECT_SCAN_SECONDS)
	elif not ok:
		status.emit("Bluetooth unavailable: " + error)


func _on_device_found(info: Dictionary) -> void:
	var address: String = info.address
	discovered[address] = info
	device_found.emit(info)
	# Auto-connect remembered devices whose role is still empty.
	var role := role_of(address)
	if role == "":
		return
	var slot_free := (role == "trainer" and not (trainer is FtmsTrainer)) \
		or (role == "heart_rate" and not (heart_rate is BleHeartRate))
	if slot_free and not _pending.has(address):
		pair(address)


func _assign_roles(p: BlePeripheral) -> void:
	_pending.erase(p.address)
	var assigned: Array[String] = []
	if p.has_service(Gatt.FTMS_SERVICE):
		_drop_trainer()
		var t := FtmsTrainer.new()
		t.name = "FtmsTrainer"
		add_child(t)
		t.status_changed.connect(func(s: String) -> void: status.emit(s))
		t.attach(p)
		trainer = t
		remembered["trainer"] = {"address": p.address, "name": p.name}
		assigned.append("trainer")
		trainer_changed.emit(trainer)
	if p.has_service(Gatt.HEART_RATE_SERVICE):
		_drop_heart_rate()
		var hr := BleHeartRate.new()
		hr.name = "BleHeartRate"
		add_child(hr)
		hr.attach(p)
		heart_rate = hr
		remembered["heart_rate"] = {"address": p.address, "name": p.name}
		assigned.append("heart_rate")
		heart_rate_sensor_changed.emit(heart_rate)
	if assigned.is_empty():
		status.emit("%s is not a trainer or heart-rate sensor" % (p.name if p.name != "" else p.address))
		p.disconnect_peripheral()
		return
	_save_remembered()
	status.emit("%s paired as %s" % [p.name if p.name != "" else p.address, " and ".join(assigned)])
	if _all_remembered_connected():
		adapter.stop_scan()


func _all_remembered_connected() -> bool:
	for role in remembered:
		if role == "trainer" and not (trainer is FtmsTrainer):
			return false
		if role == "heart_rate" and not (heart_rate is BleHeartRate):
			return false
	return true


func _drop_trainer() -> void:
	if trainer != null:
		trainer.disconnect_device()
		trainer.queue_free()
		trainer = null
		trainer_changed.emit(null)


func _drop_heart_rate() -> void:
	if heart_rate != null:
		heart_rate.disconnect_device()
		heart_rate.queue_free()
		heart_rate = null
		heart_rate_sensor_changed.emit(null)


func _load_remembered() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DEVICES_PATH) != OK:
		return
	for role in ["trainer", "heart_rate"]:
		var addr := str(cfg.get_value(role, "address", ""))
		if addr != "":
			remembered[role] = {"address": addr, "name": str(cfg.get_value(role, "name", ""))}


func _save_remembered() -> void:
	var cfg := ConfigFile.new()
	for role in remembered:
		cfg.set_value(role, "address", remembered[role].address)
		cfg.set_value(role, "name", remembered[role].name)
	cfg.save(DEVICES_PATH)
