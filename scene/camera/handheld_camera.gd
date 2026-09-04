class_name HandheldCamera
extends Camera3D
## Third-person follow camera with smoothed motion. (The handheld shake and
## its off/low/high setting were removed on 2026-09-03: nobody turned it on.)

var follow_distance := 7.8
var follow_height := 2.7
var look_ahead := 4.5
var orbit := 0.0            ## debug: yaw offset around the rider (radians), 0 = behind
var ground_height: Callable ## func(x, z) -> float; terrain height, for clearance
const CLEARANCE := 1.0      ## metres the lens stays above the ground

var _t := 0.0
var _noise := FastNoiseLite.new()
var _smooth_pos := Vector3.ZERO
var _initialized := false


func _init() -> void:
	fov = 56.0
	near = 0.3
	far = 3000.0
	_noise.seed = 99
	_noise.frequency = 1.0
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


## anchor: a point on the trail behind the rider; ground_y: terrain height under it.
func _ground(at: Vector3, fallback: float) -> float:
	if ground_height.is_valid():
		var h: Variant = ground_height.call(at.x, at.z)
		if h is float:
			return h
	return fallback


func update_follow(rider_pos: Vector3, heading: Vector3, anchor: Vector3, ground_y: float, speed: float, delta: float) -> void:
	_t += delta
	var flat := Vector3(heading.x, 0.0, heading.z).normalized()
	var target := anchor + Vector3.UP * follow_height
	if absf(orbit) > 0.001:
		target = rider_pos + (Basis(Vector3.UP, orbit) * (-flat)) * follow_distance + Vector3.UP * follow_height
	target.y = maxf(target.y, _ground(target, ground_y) + CLEARANCE)
	if not _initialized:
		_smooth_pos = target
		_initialized = true
	_smooth_pos = _smooth_pos.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	# Never let smoothing carry the lens into a rising slope.
	_smooth_pos.y = maxf(_smooth_pos.y, _ground(_smooth_pos, ground_y) + CLEARANCE)
	var pos := _smooth_pos
	pos.y = maxf(pos.y, _ground(pos, ground_y) + CLEARANCE * 0.8)
	global_position = pos
	var look := rider_pos + Vector3.UP * 0.9 + (flat * look_ahead if absf(orbit) <= 0.001 else Vector3.ZERO)
	look_at(look, Vector3.UP)
