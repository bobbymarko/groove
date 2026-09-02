class_name SimulatedTrainer
extends Trainer
## A trainer plus a rider, in software. In ERG mode the "rider's" power settles
## on the target with a short lag and some noise, like a real ERG session.
## With ERG off, power comes from resistance level and cadence.

@export var pedaling := true
@export var noise_fraction := 0.04
@export var lag_seconds := 2.5
@export var base_cadence := 88.0

var _connected := false
var _erg := true
var _target := 0
var _resistance := 0.3
var _power := 0.0
var _cadence := 0.0
var _timer: Timer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 12345
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(func(): step(1.0))
	add_child(_timer)


func display_name() -> String:
	return "Simulated trainer"


func connect_device() -> void:
	if _connected:
		return
	_connected = true
	if _timer.is_inside_tree():
		_timer.start()
	status_changed.emit("Simulator connected")
	connected.emit()


func disconnect_device() -> void:
	if not _connected:
		return
	_connected = false
	_timer.stop()
	disconnected.emit()


func is_device_connected() -> bool:
	return _connected


func set_target_power(watts: int) -> void:
	_erg = true
	_target = maxi(watts, 0)


func set_resistance(level: float) -> void:
	_erg = false
	_resistance = clampf(level, 0.0, 1.0)


func supported_power_range() -> Vector2i:
	return Vector2i(0, 2000)


## Advance the rider model by dt seconds and emit readings. Public for tests.
func step(dt: float) -> void:
	var goal_cadence := 0.0
	var goal_power := 0.0
	if pedaling:
		goal_cadence = base_cadence + (6.0 if _target > 0 and _erg and _target > 250 else 0.0)
		if _erg:
			goal_power = float(_target)
		else:
			goal_power = _resistance * 450.0 * (_cadence / 90.0)
	var k := 1.0 - exp(-dt / lag_seconds)
	_power = lerpf(_power, goal_power, k)
	_cadence = lerpf(_cadence, goal_cadence, minf(k * 2.0, 1.0))
	var noise := 1.0 + _rng.randfn(0.0, noise_fraction) if goal_power > 0.0 else 1.0
	var p := int(round(_power * noise))
	var c := int(round(_cadence + (_rng.randfn(0.0, 1.5) if goal_cadence > 0.0 else 0.0)))
	power_changed.emit(maxi(p, 0))
	cadence_changed.emit(maxi(c, 0))
	speed_changed.emit(_speed_for(float(p)))


func current_power() -> float:
	return _power


static func _speed_for(watts: float) -> float:
	# Flat-road cruising: crude cubic drag model, tuned to feel plausible.
	return 0.0 if watts <= 0.0 else pow(watts / 0.27, 1.0 / 3.0) * 3.6 * 0.5
