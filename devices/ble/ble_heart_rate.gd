class_name BleHeartRate
extends HeartRateSensor
## Heart-rate strap over the Bluetooth Heart Rate Service, with auto-reconnect.

const RECONNECT_DELAY := 3.0
const RECONNECT_MAX := 30.0
const DATA_TIMEOUT := 10.0

var peripheral: BlePeripheral
var auto_reconnect := true

var _want_connection := false
var _ready_flag := false
var _reconnect_wait := 0.0
var _reconnect_attempts := 0
var _since_data := 0.0


func attach(p: BlePeripheral) -> void:
	peripheral = p
	p.connected.connect(_on_connected)
	p.disconnected.connect(_on_disconnected)
	p.connection_failed.connect(func(_e: String) -> void: if _want_connection and auto_reconnect: _schedule_reconnect())
	p.services_discovered.connect(_on_services)
	p.notified.connect(_on_notified)
	_want_connection = true
	if p.is_peripheral_connected():
		if p.get_services().is_empty():
			p.discover_services()
		else:
			_on_services(p.get_services())
	else:
		p.connect_peripheral()


func display_name() -> String:
	return peripheral.name if peripheral != null and peripheral.name != "" else "Heart rate"


func connect_device() -> void:
	_want_connection = true
	if peripheral != null and not peripheral.is_peripheral_connected():
		peripheral.connect_peripheral()


func disconnect_device() -> void:
	_want_connection = false
	_reconnect_wait = 0.0
	if peripheral != null:
		peripheral.disconnect_peripheral()


func is_device_connected() -> bool:
	return peripheral != null and peripheral.is_peripheral_connected() and _ready_flag


func _on_connected() -> void:
	peripheral.discover_services()


func _on_services(_services: Array) -> void:
	if not peripheral.has_service(Gatt.HEART_RATE_SERVICE):
		return
	peripheral.subscribe(Gatt.HEART_RATE_SERVICE, Gatt.HEART_RATE_MEASUREMENT)
	_ready_flag = true
	_reconnect_attempts = 0
	_since_data = 0.0
	connected.emit()


func _on_disconnected() -> void:
	var was_ready := _ready_flag
	_ready_flag = false
	if was_ready:
		disconnected.emit()
	if _want_connection and auto_reconnect:
		_schedule_reconnect()


func _on_notified(char_uuid: String, data: PackedByteArray) -> void:
	_since_data = 0.0
	if char_uuid == Gatt.HEART_RATE_MEASUREMENT:
		var bpm := Gatt.parse_heart_rate(data)
		if bpm >= 0:
			heart_rate_changed.emit(bpm)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _ready_flag:
		_since_data += delta
		if _since_data > DATA_TIMEOUT:
			peripheral.mark_lost()
	if _reconnect_wait > 0.0:
		_reconnect_wait -= delta
		if _reconnect_wait <= 0.0 and _want_connection and peripheral != null and not peripheral.is_peripheral_connected():
			peripheral.connect_peripheral()


func _schedule_reconnect() -> void:
	_reconnect_wait = minf(RECONNECT_DELAY * pow(2.0, _reconnect_attempts), RECONNECT_MAX)
	_reconnect_attempts += 1
