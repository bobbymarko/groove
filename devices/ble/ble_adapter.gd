class_name BleAdapter
extends Node
## The only file that talks to the GDBLE extension. Scans for devices and
## opens BlePeripheral handles. Swapping the Bluetooth backend (for iOS, say)
## means replacing this file and nothing else.

signal ready_changed(ok: bool, error: String)
signal device_found(info: Dictionary)          ## {address, name, rssi}
signal scan_started
signal scan_stopped
signal adapter_error(message: String)

var _bt: Variant = null       # GDBLE BluetoothManager; untyped so the project loads without the extension
var _ready_ok := false
var _scanning := false


func _ready() -> void:
	if not ClassDB.class_exists("BluetoothManager"):
		ready_changed.emit.call_deferred(false, "Bluetooth extension (GDBLE) is not loaded")
		return
	_bt = ClassDB.instantiate("BluetoothManager")
	add_child(_bt)
	_bt.adapter_initialized.connect(_on_initialized)
	_bt.device_discovered.connect(_on_device)
	_bt.device_updated.connect(_on_device)
	_bt.scan_started.connect(func() -> void: _scanning = true; scan_started.emit())
	_bt.scan_stopped.connect(func() -> void: _scanning = false; scan_stopped.emit())
	_bt.error_occurred.connect(func(msg: String) -> void: adapter_error.emit(msg))


func initialize() -> void:
	if _bt == null or _ready_ok:
		return
	_bt.initialize()


func is_adapter_ready() -> bool:
	return _ready_ok


func is_scanning() -> bool:
	return _scanning


func start_scan(seconds: float = 15.0) -> void:
	if _bt != null and _ready_ok and not _scanning:
		_bt.start_scan(seconds)


func stop_scan() -> void:
	if _bt != null and _scanning:
		_bt.stop_scan()


func open(address: String, device_name := "") -> BlePeripheral:
	var p := GdblePeripheral.new()
	p.setup(_bt, address, device_name)
	return p


func _on_initialized(success: bool, error: String) -> void:
	_ready_ok = success
	ready_changed.emit(success, error)


func _on_device(info: Dictionary) -> void:
	var rssi: Variant = info.get("rssi")
	device_found.emit({
		"address": str(info.get("address", "")),
		"name": str(info.get("name", "")),
		"rssi": int(rssi) if (rssi is int or rssi is float) else 0,
	})


## BlePeripheral over a GDBLE BleDevice. GDBLE keeps one BleDevice per address
## and hands the same object back on every connect_device() call, so handlers
## are wired exactly once per object and the object is kept across dropouts.
class GdblePeripheral:
	extends BlePeripheral

	var _bt: Variant
	var _dev: Variant = null

	func setup(bt: Variant, addr: String, nm: String) -> void:
		_bt = bt
		address = addr
		name = nm

	func connect_peripheral() -> void:
		if _bt == null:
			connection_failed.emit("Bluetooth adapter unavailable")
			return
		var dev: Variant = _bt.connect_device(address)
		if dev == null:
			connection_failed.emit("Device %s not found. Scan first." % address)
			return
		if dev != _dev:
			_dev = dev
			_wire(_dev)
		_dev.connect_async()

	func _wire(dev: Variant) -> void:
		_wire_one(dev.connected, _on_connected)
		_wire_one(dev.disconnected, _on_disconnected)
		_wire_one(dev.connection_failed, _on_connection_failed)
		_wire_one(dev.services_discovered, _on_services)
		_wire_one(dev.characteristic_notified, _on_notified)
		_wire_one(dev.characteristic_read, _on_read)
		_wire_one(dev.characteristic_written, _on_written)
		_wire_one(dev.operation_failed, _on_failed)

	static func _wire_one(sig: Signal, handler: Callable) -> void:
		if not sig.is_connected(handler):
			sig.connect(handler)

	func disconnect_peripheral() -> void:
		if _bt != null and _connected:
			_bt.disconnect_device(address)

	func mark_lost() -> void:
		if not _connected:
			return
		# Best effort: GDBLE 0.5.5 only notices disconnects it initiated, so
		# ask it to tear the stale link down before we reconnect.
		if _bt != null:
			_bt.disconnect_device(address)
		super.mark_lost()

	func discover_services() -> void:
		if _dev != null:
			_dev.discover_services()

	func read(service_uuid: String, char_uuid: String) -> void:
		if _dev != null:
			_dev.read_characteristic(service_uuid, char_uuid)

	func write(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> void:
		if _dev != null:
			_dev.write_characteristic(service_uuid, char_uuid, data, with_response)

	func subscribe(service_uuid: String, char_uuid: String) -> void:
		if _dev != null:
			_dev.subscribe_characteristic(service_uuid, char_uuid)

	func unsubscribe(service_uuid: String, char_uuid: String) -> void:
		if _dev != null:
			_dev.unsubscribe_characteristic(service_uuid, char_uuid)

	func _on_connected() -> void:
		_connected = true
		if name == "" and _dev != null:
			name = str(_dev.get_name())
		connected.emit()

	func _on_disconnected() -> void:
		_connected = false
		_services = []
		disconnected.emit()

	func _on_connection_failed(err: String) -> void:
		_connected = false
		connection_failed.emit(err)

	func _on_services(raw: Array) -> void:
		_services = BlePeripheral.normalize_services(raw)
		services_discovered.emit(_services)

	func _on_notified(u: String, d: PackedByteArray) -> void:
		notified.emit(Gatt.norm(u), d)

	func _on_read(u: String, d: PackedByteArray) -> void:
		read_completed.emit(Gatt.norm(u), d)

	func _on_written(u: String) -> void:
		write_completed.emit(Gatt.norm(u))

	func _on_failed(op: String, e: String) -> void:
		operation_failed.emit(op, e)
