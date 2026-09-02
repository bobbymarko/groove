class_name FakePeripheral
extends BlePeripheral
## In-memory peripheral for tests. Records every call; tests trigger events.

var connect_calls := 0
var disconnect_calls := 0
var discover_calls := 0
var subscribes: Array[String] = []
var reads: Array[String] = []
var writes: Array[PackedByteArray] = []
var fail_next_connect := false
var services_to_report: Array = []


static func ftms_services() -> Array:
	return [{"uuid": Gatt.FTMS_SERVICE, "characteristics": [
		{"uuid": Gatt.FTMS_CONTROL_POINT, "properties": {"write": true, "indicate": true}},
		{"uuid": Gatt.FTMS_INDOOR_BIKE_DATA, "properties": {"notify": true}},
		{"uuid": Gatt.FTMS_POWER_RANGE, "properties": {"read": true}},
	]}]


static func hr_services() -> Array:
	return [{"uuid": Gatt.HEART_RATE_SERVICE, "characteristics": [
		{"uuid": Gatt.HEART_RATE_MEASUREMENT, "properties": {"notify": true}}]}]


func connect_peripheral() -> void:
	connect_calls += 1
	if fail_next_connect:
		fail_next_connect = false
		connection_failed.emit("simulated failure")


func disconnect_peripheral() -> void:
	disconnect_calls += 1
	simulate_disconnect()


func discover_services() -> void:
	discover_calls += 1


func read(_service_uuid: String, char_uuid: String) -> void:
	reads.append(Gatt.norm(char_uuid))


func write(_service_uuid: String, _char_uuid: String, data: PackedByteArray, _with_response: bool) -> void:
	writes.append(data)


func subscribe(_service_uuid: String, char_uuid: String) -> void:
	subscribes.append(Gatt.norm(char_uuid))


# --- test controls ---------------------------------------------------------------

func simulate_connect() -> void:
	_connected = true
	connected.emit()


func simulate_services(services: Array = services_to_report) -> void:
	_services = BlePeripheral.normalize_services(services)
	services_discovered.emit(_services)


func simulate_disconnect() -> void:
	if _connected:
		_connected = false
		_services = []
		disconnected.emit()


func simulate_written(char_uuid: String = Gatt.FTMS_CONTROL_POINT) -> void:
	write_completed.emit(Gatt.norm(char_uuid))


func simulate_notify(char_uuid: String, data: PackedByteArray) -> void:
	notified.emit(Gatt.norm(char_uuid), data)


func simulate_control_response(op: int, result: int = Gatt.FtmsResult.SUCCESS) -> void:
	simulate_notify(Gatt.FTMS_CONTROL_POINT, PackedByteArray([Gatt.FtmsOp.RESPONSE, op, result]))


## Complete the write in flight: ack it and send the trainer's response.
func ack_last_write(result: int = Gatt.FtmsResult.SUCCESS) -> void:
	var op := writes[-1][0]
	simulate_written()
	simulate_control_response(op, result)
