class_name FtmsTrainer
extends Trainer
## Smart trainer over the Bluetooth Fitness Machine Service. Owns one
## BlePeripheral, runs the FTMS control handshake, serializes Control Point
## writes (one in flight, wait for the response), and reconnects on its own
## after a dropout, re-applying the last target so the ride carries on.

const RECONNECT_DELAY := 3.0
const RECONNECT_MAX := 30.0
const WRITE_TIMEOUT := 2.5
## Trainers stream Indoor Bike Data about once a second even at rest. Silence
## this long means the link is gone, whether or not the backend says so.
const DATA_TIMEOUT := 6.0

var peripheral: BlePeripheral
var auto_reconnect := true

var _want_connection := false
var _setup_done := false
var _has_control := false
var _target := -1          # last ERG target, -1 = none
var _grade := NAN          # last sim grade (ERG off), NAN = none
var _queue: Array[PackedByteArray] = []
var _in_flight := false
var _write_elapsed := 0.0
var _reconnect_wait := 0.0
var _reconnect_attempts := 0
var _power_range := Vector2i(0, 0)
var _since_data := 0.0


func attach(p: BlePeripheral) -> void:
	peripheral = p
	p.connected.connect(_on_connected)
	p.disconnected.connect(_on_disconnected)
	p.connection_failed.connect(_on_connection_failed)
	p.services_discovered.connect(_on_services)
	p.notified.connect(_on_notified)
	p.read_completed.connect(_on_read)
	p.write_completed.connect(_on_written)
	p.operation_failed.connect(_on_failed)
	_want_connection = true
	if p.is_peripheral_connected():
		if p.get_services().is_empty():
			p.discover_services()
		else:
			_on_services(p.get_services())
	else:
		p.connect_peripheral()


# --- Trainer interface ---------------------------------------------------------

func display_name() -> String:
	return peripheral.name if peripheral != null and peripheral.name != "" else "Trainer"


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
	return peripheral != null and peripheral.is_peripheral_connected() and _setup_done


func set_target_power(watts: int) -> void:
	_target = maxi(watts, 0)
	_grade = NAN
	if _setup_done:
		_enqueue(Gatt.ftms_set_target_power(_target))


## ERG off: emulate a hill. level 0..1 maps to a 0–8 % grade.
func set_resistance(level: float) -> void:
	_grade = clampf(level, 0.0, 1.0) * 8.0
	_target = -1
	if _setup_done:
		_enqueue(Gatt.ftms_set_sim_grade(_grade))


func supported_power_range() -> Vector2i:
	return _power_range


func has_control() -> bool:
	return _has_control


# --- peripheral events ---------------------------------------------------------

func _on_connected() -> void:
	status_changed.emit("Connected to %s, discovering services" % display_name())
	peripheral.discover_services()


func _on_services(_services: Array) -> void:
	if not peripheral.has_service(Gatt.FTMS_SERVICE):
		status_changed.emit("%s has no Fitness Machine service" % display_name())
		return
	peripheral.subscribe(Gatt.FTMS_SERVICE, Gatt.FTMS_CONTROL_POINT)
	peripheral.subscribe(Gatt.FTMS_SERVICE, Gatt.FTMS_INDOOR_BIKE_DATA)
	peripheral.subscribe(Gatt.FTMS_SERVICE, Gatt.FTMS_STATUS)
	peripheral.read(Gatt.FTMS_SERVICE, Gatt.FTMS_POWER_RANGE)
	_queue.clear()
	_in_flight = false
	_has_control = false
	_setup_done = true
	_reconnect_attempts = 0
	_since_data = 0.0
	_enqueue(Gatt.ftms_request_control())
	_enqueue(Gatt.ftms_start())
	if _target >= 0:
		_enqueue(Gatt.ftms_set_target_power(_target))
	elif not is_nan(_grade):
		_enqueue(Gatt.ftms_set_sim_grade(_grade))
	status_changed.emit("%s ready" % display_name())
	connected.emit()


func _on_disconnected() -> void:
	var was_ready := _setup_done
	_setup_done = false
	_has_control = false
	_in_flight = false
	_queue.clear()
	if was_ready:
		disconnected.emit()
	if _want_connection and auto_reconnect:
		_schedule_reconnect()
		status_changed.emit("%s disconnected, reconnecting…" % display_name())
	else:
		status_changed.emit("%s disconnected" % display_name())


func _on_connection_failed(err: String) -> void:
	status_changed.emit("Connection failed: %s" % err)
	if _want_connection and auto_reconnect:
		_schedule_reconnect()


func _on_notified(char_uuid: String, data: PackedByteArray) -> void:
	_since_data = 0.0
	match char_uuid:
		Gatt.FTMS_INDOOR_BIKE_DATA:
			var r := Gatt.parse_indoor_bike_data(data)
			if r.has("power_w"):
				power_changed.emit(int(r.power_w))
			if r.has("cadence_rpm"):
				cadence_changed.emit(int(round(r.cadence_rpm)))
			if r.has("speed_kph"):
				speed_changed.emit(float(r.speed_kph))
		Gatt.FTMS_CONTROL_POINT:
			var resp := Gatt.parse_control_response(data)
			if resp.is_empty():
				return
			if resp.op == Gatt.FtmsOp.REQUEST_CONTROL:
				_has_control = resp.ok
				if not resp.ok:
					status_changed.emit("Trainer refused control: %s" % Gatt.result_name(resp.result))
			elif not resp.ok:
				status_changed.emit("Trainer rejected command 0x%02X: %s" % [resp.op, Gatt.result_name(resp.result)])
				if resp.result == Gatt.FtmsResult.CONTROL_NOT_PERMITTED:
					_enqueue(Gatt.ftms_request_control())


func _on_read(char_uuid: String, data: PackedByteArray) -> void:
	if char_uuid == Gatt.FTMS_POWER_RANGE:
		var r := Gatt.parse_power_range(data)
		if not r.is_empty():
			_power_range = Vector2i(r.min, r.max)


func _on_written(char_uuid: String) -> void:
	if char_uuid == Gatt.FTMS_CONTROL_POINT:
		_in_flight = false
		_send_next()


func _on_failed(operation: String, err: String) -> void:
	status_changed.emit("%s failed: %s" % [operation, err])
	if operation == "write":
		_in_flight = false
		_send_next()


# --- write queue and timers ------------------------------------------------------

func _enqueue(cmd: PackedByteArray) -> void:
	# A newer target supersedes any queued target of the same opcode.
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i][0] == cmd[0] and cmd[0] != Gatt.FtmsOp.REQUEST_CONTROL:
			_queue.remove_at(i)
	_queue.append(cmd)
	_send_next()


func _send_next() -> void:
	if _in_flight or _queue.is_empty() or not _setup_done:
		return
	var cmd: PackedByteArray = _queue.pop_front()
	_in_flight = true
	_write_elapsed = 0.0
	peripheral.write(Gatt.FTMS_SERVICE, Gatt.FTMS_CONTROL_POINT, cmd, true)


func _process(delta: float) -> void:
	tick(delta)


## Time-driven bookkeeping. Public so tests can drive it without a scene tree.
func tick(delta: float) -> void:
	if _setup_done:
		_since_data += delta
		if _since_data > DATA_TIMEOUT:
			status_changed.emit("%s: no data for %d s, treating as disconnected" % [display_name(), int(DATA_TIMEOUT)])
			peripheral.mark_lost()
	if _in_flight:
		_write_elapsed += delta
		if _write_elapsed > WRITE_TIMEOUT:
			_in_flight = false
			_send_next()
	if _reconnect_wait > 0.0:
		_reconnect_wait -= delta
		if _reconnect_wait <= 0.0 and _want_connection and peripheral != null and not peripheral.is_peripheral_connected():
			peripheral.connect_peripheral()


func _schedule_reconnect() -> void:
	_reconnect_wait = minf(RECONNECT_DELAY * pow(2.0, _reconnect_attempts), RECONNECT_MAX)
	_reconnect_attempts += 1
