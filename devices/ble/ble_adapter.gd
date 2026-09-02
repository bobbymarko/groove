class_name BleAdapter
extends Node
## The only file that talks to the GDBLE extension. Scans for devices and
## opens BlePeripheral handles. Swapping the Bluetooth backend (for iOS, say)
## means replacing this file and nothing else.
##
## Every call into GDBLE is deferred to the end of the frame. GDBLE emits its
## signals from inside its own process() while it holds a mutable borrow on
## itself; calling back into it synchronously from a handler panics.

signal ready_changed(ok: bool, error: String)
signal device_found(info: Dictionary)          ## {address, name, rssi}
signal scan_started
signal scan_stopped
signal adapter_error(message: String)

var _bt: Variant = null       # GDBLE BluetoothManager; untyped so the project loads without the extension
var _ready_ok := false
var _scanning := false
var _scan_requested := false   # start_scan deferred but not yet confirmed
var _waiting: Dictionary = {}  # address -> GdblePeripheral waiting to be rediscovered
var _rescan_wait := 0.0

const REDISCOVERY_SCAN_SECONDS := 15.0
const RESCAN_PAUSE := 1.0


func _ready() -> void:
	if not ClassDB.class_exists("BluetoothManager"):
		ready_changed.emit.call_deferred(false, "Bluetooth extension (GDBLE) is not loaded")
		return
	_bt = ClassDB.instantiate("BluetoothManager")
	add_child(_bt)
	_bt.adapter_initialized.connect(_on_initialized)
	_bt.device_discovered.connect(_on_device)
	_bt.device_updated.connect(_on_device)
	_bt.scan_started.connect(func() -> void: _scanning = true; _scan_requested = false; scan_started.emit())
	_bt.scan_stopped.connect(func() -> void: _scanning = false; _scan_requested = false; scan_stopped.emit())
	_bt.error_occurred.connect(func(msg: String) -> void: adapter_error.emit(msg))
	if _bt.has_signal("ble_event"):
		_bt.ble_event.connect(_on_ble_event)


## GDBLE 0.6 reports every operation phase here. Log connection-level ones.
func _on_ble_event(event: Dictionary) -> void:
	var op := str(event.get("operation", ""))
	var phase := str(event.get("phase", ""))
	if op == "scan" and phase in ["failed", "cancelled"]:
		_scan_requested = false
	if op in ["connect", "disconnect", "scan"] and phase != "progress":
		var err: Dictionary = event.get("error", {})
		var err_text := str(err.get("message", "")) if err is Dictionary else str(err)
		print("[ble] %s %s %s %s" % [op, phase, str(event.get("device_address", "")), err_text])


func initialize() -> void:
	if _bt == null or _ready_ok:
		return
	_bt.initialize()


func is_adapter_ready() -> bool:
	return _ready_ok


func is_scanning() -> bool:
	return _scanning


func start_scan(seconds: float = 15.0) -> void:
	if _bt != null and _ready_ok and not _scanning and not _scan_requested:
		_scan_requested = true
		_bt.call_deferred("start_scan", seconds)


func stop_scan() -> void:
	if _bt != null and _scanning:
		_bt.call_deferred("stop_scan")


func open(address: String, device_name := "") -> BlePeripheral:
	var p := GdblePeripheral.new()
	p.setup(self, _bt, address, device_name)
	return p


## A peripheral GDBLE no longer knows (it forgets devices after a disconnect)
## asks to be reconnected as soon as a scan sees it again.
func request_rediscovery(p: GdblePeripheral) -> void:
	_waiting[p.address] = p
	start_scan(REDISCOVERY_SCAN_SECONDS)


func cancel_rediscovery(address: String) -> void:
	_waiting.erase(address)


func _process(delta: float) -> void:
	# Keep scanning while anyone is waiting to be rediscovered.
	if _waiting.is_empty() or _scanning or not _ready_ok:
		return
	_rescan_wait -= delta
	if _rescan_wait <= 0.0:
		_rescan_wait = RESCAN_PAUSE
		start_scan(REDISCOVERY_SCAN_SECONDS)


func _on_initialized(success: bool, error: String) -> void:
	_ready_ok = success
	ready_changed.emit(success, error)


func _on_device(info: Dictionary) -> void:
	var rssi: Variant = info.get("rssi")
	var address := str(info.get("address", ""))
	device_found.emit({
		"address": address,
		"name": str(info.get("name", "")),
		"rssi": int(rssi) if (rssi is int or rssi is float) else 0,
	})
	if _waiting.has(address):
		var p: GdblePeripheral = _waiting[address]
		_waiting.erase(address)
		print("[ble] %s rediscovered, connecting" % (p.name if p.name != "" else address))
		p.connect_after_rediscovery()


## BlePeripheral over a GDBLE BleDevice. GDBLE keeps one BleDevice per address
## and hands the same object back on every connect_device() call, so handlers
## are wired exactly once per object and the object is kept across dropouts.
class GdblePeripheral:
	extends BlePeripheral

	var _adapter: BleAdapter
	var _bt: Variant
	var _dev: Variant = null
	var _needs_rediscovery := false   # set after a remote disconnect

	func setup(adapter: BleAdapter, bt: Variant, addr: String, nm: String) -> void:
		_adapter = adapter
		_bt = bt
		address = addr
		name = nm

	func connect_peripheral() -> void:
		_connect_now.call_deferred()

	## The adapter calls this once a scan has seen the device again.
	func connect_after_rediscovery() -> void:
		_needs_rediscovery = false
		_connect_now.call_deferred()

	func _connect_now() -> void:
		if _bt == null:
			connection_failed.emit("Bluetooth adapter unavailable")
			return
		if _needs_rediscovery:
			# After a dropout the backend's handle may be stale and a connect
			# would pend forever. Scan until the device advertises again.
			print("[ble] %s waiting to be rediscovered" % (name if name != "" else address))
			_adapter.request_rediscovery(self)
			return
		var dev: Variant = _bt.connect_device(address)
		if dev == null:
			_needs_rediscovery = true
			_adapter.request_rediscovery(self)
			operation_failed.emit("connect", "%s is out of reach, waiting for it to reappear" % (name if name != "" else address))
			return
		print("[ble] connecting to %s" % (name if name != "" else address))
		if dev != _dev:
			_dev = dev
			_wire(_dev)
		_dev.call_deferred("connect_async")

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
		_adapter.cancel_rediscovery(address)
		if _bt != null and _connected:
			_bt.call_deferred("disconnect_device", address)

	func mark_lost() -> void:
		if not _connected:
			return
		# Best effort: GDBLE 0.5.5 only notices disconnects it initiated, so
		# ask it to tear the stale link down before we reconnect.
		if _bt != null:
			_bt.call_deferred("disconnect_device", address)
		_needs_rediscovery = true
		super.mark_lost()

	func discover_services() -> void:
		if _dev != null:
			_dev.call_deferred("discover_services")

	func read(service_uuid: String, char_uuid: String) -> void:
		if _dev != null:
			_dev.call_deferred("read_characteristic", service_uuid, char_uuid)

	func write(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> void:
		if _dev != null:
			_dev.call_deferred("write_characteristic", service_uuid, char_uuid, data, with_response)

	func subscribe(service_uuid: String, char_uuid: String) -> void:
		if _dev != null:
			_dev.call_deferred("subscribe_characteristic", service_uuid, char_uuid)

	func unsubscribe(service_uuid: String, char_uuid: String) -> void:
		if _dev != null:
			_dev.call_deferred("unsubscribe_characteristic", service_uuid, char_uuid)

	func _on_connected() -> void:
		_connected = true
		if name == "" and _dev != null:
			name = str(_dev.get_name())
		connected.emit()

	func _on_disconnected() -> void:
		_connected = false
		_services = []
		_needs_rediscovery = true
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
