class_name HeartRateSensor
extends Node
## Abstract heart-rate source.

signal connected
signal disconnected
signal heart_rate_changed(bpm: int)
signal status_changed(text: String)


func display_name() -> String:
	return "Heart rate"


func connect_device() -> void:
	pass


func disconnect_device() -> void:
	pass


func is_device_connected() -> bool:
	return false
