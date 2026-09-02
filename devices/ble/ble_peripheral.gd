class_name BlePeripheral
extends RefCounted
## Abstract Bluetooth LE peripheral: the six operations the app needs
## (connect, discover, subscribe, read, write, plus disconnect) and their
## events. devices/ble/ble_adapter.gd implements it over GDBLE; tests use
## FakePeripheral. Profile classes (FtmsTrainer, BleHeartRate) only see this.

signal connected
signal disconnected
signal connection_failed(error: String)
signal services_discovered(services: Array)    ## [{uuid, characteristics: [{uuid, properties}]}]
signal notified(char_uuid: String, data: PackedByteArray)
signal read_completed(char_uuid: String, data: PackedByteArray)
signal write_completed(char_uuid: String)
signal operation_failed(operation: String, error: String)

var address := ""
var name := ""

var _services: Array = []
var _connected := false


func connect_peripheral() -> void:
	pass


func disconnect_peripheral() -> void:
	pass


func is_peripheral_connected() -> bool:
	return _connected


## Called by a profile when the link has clearly died (no data for several
## seconds) but the backend never reported it. Tears down local state and
## emits `disconnected` so the normal reconnect path runs.
func mark_lost() -> void:
	if not _connected:
		return
	_connected = false
	_services = []
	disconnected.emit()


func discover_services() -> void:
	pass


func get_services() -> Array:
	return _services


func has_service(uuid: String) -> bool:
	var u := Gatt.norm(uuid)
	for s in _services:
		if s.get("uuid", "") == u:
			return true
	return false


func read(_service_uuid: String, _char_uuid: String) -> void:
	pass


func write(_service_uuid: String, _char_uuid: String, _data: PackedByteArray, _with_response: bool) -> void:
	pass


func subscribe(_service_uuid: String, _char_uuid: String) -> void:
	pass


func unsubscribe(_service_uuid: String, _char_uuid: String) -> void:
	pass


## Normalize a raw services array into lower-case UUIDs.
static func normalize_services(raw: Array) -> Array:
	var out: Array = []
	for s in raw:
		var chars: Array = []
		for c in s.get("characteristics", []):
			chars.append({"uuid": Gatt.norm(c.get("uuid", "")), "properties": c.get("properties", {})})
		out.append({"uuid": Gatt.norm(s.get("uuid", "")), "characteristics": chars})
	return out
