extends Node
## Autoload "Devices". Owns the active trainer and heart-rate sensor and hands
## them to the UI. Milestone 1 only knows the simulator; Bluetooth devices and
## pairing arrive in milestone 2 behind the same two properties.

signal trainer_changed(trainer: Trainer)
signal heart_rate_sensor_changed(sensor: HeartRateSensor)

var trainer: Trainer
var heart_rate: HeartRateSensor


func use_simulated_devices() -> void:
	_clear()
	var t := SimulatedTrainer.new()
	t.name = "SimulatedTrainer"
	add_child(t)
	var hr := SimulatedHeartRate.new()
	hr.name = "SimulatedHeartRate"
	add_child(hr)
	hr.follow(t)
	trainer = t
	heart_rate = hr
	t.connect_device()
	hr.connect_device()
	trainer_changed.emit(trainer)
	heart_rate_sensor_changed.emit(heart_rate)


func has_trainer() -> bool:
	return trainer != null and trainer.is_device_connected()


func _clear() -> void:
	for n in [trainer, heart_rate]:
		if n != null:
			n.disconnect_device()
			n.queue_free()
	trainer = null
	heart_rate = null
