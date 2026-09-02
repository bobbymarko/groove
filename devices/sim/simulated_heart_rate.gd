class_name SimulatedHeartRate
extends HeartRateSensor
## Heart rate that follows a trainer's power with a slow lag.

@export var resting_bpm := 62.0
@export var max_bpm := 178.0
@export var reference_ftp := 250.0
@export var lag_seconds := 25.0

var _connected := false
var _bpm := 62.0
var _last_power := 0.0
var _timer: Timer


func _ready() -> void:
	_bpm = resting_bpm
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(func(): step(1.0))
	add_child(_timer)


func follow(trainer: Trainer) -> void:
	trainer.power_changed.connect(func(w: int): _last_power = float(w))


func display_name() -> String:
	return "Simulated heart rate"


func connect_device() -> void:
	_connected = true
	if _timer.is_inside_tree():
		_timer.start()
	connected.emit()


func disconnect_device() -> void:
	_connected = false
	_timer.stop()
	disconnected.emit()


func is_device_connected() -> bool:
	return _connected


func step(dt: float) -> void:
	var intensity := clampf(_last_power / reference_ftp, 0.0, 1.3)
	var goal := resting_bpm + (max_bpm - resting_bpm) * pow(intensity, 0.8) * 0.85
	_bpm = lerpf(_bpm, goal, 1.0 - exp(-dt / lag_seconds))
	heart_rate_changed.emit(int(round(_bpm)))
