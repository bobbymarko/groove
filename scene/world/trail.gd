class_name Trail
extends RefCounted
## The trail the rider follows. It runs along +Z, meanders in X, and its height
## profile comes from a grade provider: by default gentle rolling terrain, during
## a workout the upcoming power targets (hard efforts climb, recoveries descend).
## Heights are integrated once per metre and cached so the terrain and the rider
## agree exactly.

const STEP := 1.0                 # metres per height sample
const GRADE_SMOOTHING := 0.16     # per metre; ~6 m to settle

var grade_provider: Callable      # func(z: float) -> float grade in percent, or invalid
var _heights: PackedFloat64Array = [0.0]
var _grade := 0.0
var _noise := FastNoiseLite.new()
var _seed := 7


func _init(seed_value: int = 7) -> void:
	_seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.02
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


## An independent copy for worker threads: same meander and the heights cached
## so far. The copy extends itself with the default profile if asked further,
## so callers must extend the original first (see TerrainStreamer._pump).
func snapshot() -> Trail:
	var t := Trail.new(_seed)
	t._heights = _heights.duplicate()
	t._grade = _grade
	return t


## Lateral position of the trail centre at distance z.
func x_at(z: float) -> float:
	# Wavelengths of roughly 200 m and 70 m: sweeping bends, no wobble.
	return _noise.get_noise_2d(z * 0.25, 0.0) * 14.0 + _noise.get_noise_2d(z * 0.7, 50.0) * 3.0


## Lateral slope dx/dz, used for heading and lean.
func dx_at(z: float) -> float:
	return (x_at(z + 0.5) - x_at(z - 0.5))


## Curvature (second derivative of x over a 6 m baseline), positive bends right.
func curvature_at(z: float) -> float:
	return (x_at(z + 3.0) - 2.0 * x_at(z) + x_at(z - 3.0)) / 9.0


## Height of the trail at distance z (extends the cache as needed).
func h_at(z: float) -> float:
	if z <= 0.0:
		return _heights[0]
	var idx := int(floor(z / STEP))
	while _heights.size() <= idx + 1:
		_extend()
	var f := z / STEP - idx
	return lerpf(_heights[idx], _heights[idx + 1], f)


## Current grade in percent at z (from the cached profile).
func grade_at(z: float) -> float:
	return (h_at(z + 1.0) - h_at(z - 1.0)) / 2.0 * 100.0


func heading_at(z: float) -> Vector3:
	return Vector3(dx_at(z), (h_at(z + 0.5) - h_at(z - 0.5)), 1.0).normalized()


func position_at(z: float) -> Vector3:
	return Vector3(x_at(z), h_at(z), z)


func _extend() -> void:
	var z := _heights.size() * STEP
	var target := _default_grade(z)
	if grade_provider.is_valid():
		var g: Variant = grade_provider.call(z)
		if g is float or g is int:
			target = float(g)
	_grade = lerpf(_grade, target, GRADE_SMOOTHING)
	_heights.append(_heights[-1] + _grade / 100.0 * STEP)


func _default_grade(z: float) -> float:
	return _noise.get_noise_2d(z * 0.35, 200.0) * 5.0


## Map a workout target (fraction of FTP) to a visual grade: easy spins
## descend, threshold and above climb. Exaggerated well beyond real trails so
## a hard interval reads as a wall at this render scale: 0.5 FTP -> -8 %,
## 0.7 flat, 1.06 -> +14 %, 1.2 -> +20 %, capped at 24 %.
static func grade_for_target(fraction: float) -> float:
	return clampf((fraction - 0.7) * 40.0, -10.0, 24.0)
