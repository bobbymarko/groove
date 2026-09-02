class_name Trainer
extends Node
## Abstract smart trainer. Implementations: devices/ble (FTMS over Bluetooth),
## devices/sim (simulator). Everything above the device layer talks to this.

signal connected
signal disconnected
signal power_changed(watts: int)
signal cadence_changed(rpm: int)
signal speed_changed(kph: float)
signal status_changed(text: String)


func display_name() -> String:
	return "Trainer"


func connect_device() -> void:
	pass


func disconnect_device() -> void:
	pass


func is_device_connected() -> bool:
	return false


## ERG mode: the trainer holds this power regardless of cadence.
func set_target_power(_watts: int) -> void:
	pass


## Resistance mode: fixed brake level 0..1. Used when ERG is off or for free ride.
func set_resistance(_level: float) -> void:
	pass


func supported_power_range() -> Vector2i:
	return Vector2i(0, 0)
