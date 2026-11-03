class_name PowerTrail
extends RefCounted
## The workout as a side-scroller level. X is workout time times SCROLL, so
## the level is exactly as long as the workout; the ground height at each
## point follows that moment's target power. Blocks are plateaus joined by
## short slopes. Also decides, deterministically, where every find grows.

const SCROLL := 3.0          ## metres of trail per second of workout
const SLOPE_TIME := 1.2      ## seconds a change of block takes to climb or drop
const MEADOW := 0.9          ## height of free ride and max effort meadows

## Find kinds.
const BERRY := "berry"
const FLOWER := "flower"
const CRITTER := "critter"
const HONEY := "honey"

const BERRY_EVERY := 2.5     ## seconds between berry bushes
const FLOWER_EVERY := 12.0   ## seconds between flower patches on hard plateaus
const FLOWER_FROM := 0.76    ## fraction of FTP: tempo and up grow flowers
const CRITTER_FROM := 1.06   ## fraction of FTP: VO2 and up release a critter

var workout: Workout
var _xs: PackedFloat32Array = []
var _ys: PackedFloat32Array = []


func _init(w: Workout) -> void:
	workout = w
	_build_profile()


## Ground height for a target fraction of FTP (0 = free ride).
static func height_for(fraction: float) -> float:
	if fraction <= 0.0:
		return MEADOW
	return clampf((fraction - 0.45) * 4.2, 0.0, 5.0)


func length() -> float:
	return workout.total_duration() * SCROLL


func height_at(x: float) -> float:
	if _xs.is_empty():
		return 0.0
	if x <= _xs[0]:
		return _ys[0]
	var lo := 0
	var hi := _xs.size() - 1
	if x >= _xs[hi]:
		return _ys[hi]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _xs[mid] <= x:
			lo = mid
		else:
			hi = mid
	var t := (x - _xs[lo]) / maxf(_xs[hi] - _xs[lo], 0.0001)
	return lerpf(_ys[lo], _ys[hi], t)


func slope_at(x: float) -> float:
	return atan2(height_at(x + 0.5) - height_at(x - 0.5), 1.0)


## Each segment holds its own height except for half a slope at either end,
## so a change of block reads as a quick climb or drop.
func _build_profile() -> void:
	_xs.clear()
	_ys.clear()
	var t := 0.0
	var half := SLOPE_TIME * 0.5
	for s in workout.segments:
		var h0 := height_for(_frac(s, s.power_low))
		var h1 := height_for(_frac(s, s.power_high))
		var a := t + minf(half, s.duration * 0.25)
		var b := t + s.duration - minf(half, s.duration * 0.25)
		_xs.append(a * SCROLL)
		_ys.append(h0)
		_xs.append(b * SCROLL)
		_ys.append(h1)
		t += s.duration
	if _xs.is_empty():
		_xs.append(0.0)
		_ys.append(0.0)


static func _frac(s: WorkoutSegment, p: float) -> float:
	if s.kind == WorkoutSegment.Kind.FREE_RIDE or s.kind == WorkoutSegment.Kind.MAX_EFFORT:
		return 0.0
	return p


## Every find, in time order: {kind, time, segment, x}. Critters and honey
## belong to a whole segment (time = its start); berries and flowers to a moment.
func finds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := 0.0
	for i in workout.segments.size():
		var s := workout.segments[i]
		var peak := s.peak()
		if s.kind == WorkoutSegment.Kind.MAX_EFFORT:
			out.append({"kind": HONEY, "time": t, "segment": i})
		elif peak >= CRITTER_FROM:
			out.append({"kind": CRITTER, "time": t, "segment": i})
		var steady := s.kind in [WorkoutSegment.Kind.STEADY, WorkoutSegment.Kind.INTERVAL_ON]
		if peak >= FLOWER_FROM and steady:
			var ft := t + FLOWER_EVERY * 0.5
			while ft < t + s.duration - 1.0:
				out.append({"kind": FLOWER, "time": ft, "segment": i})
				ft += FLOWER_EVERY
		t += s.duration
	var bt := BERRY_EVERY
	while bt < workout.total_duration() - 1.0:
		out.append({"kind": BERRY, "time": bt, "segment": workout.segment_index_at(bt)})
		bt += BERRY_EVERY
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for f in out:
		f["x"] = float(f.time) * SCROLL
	return out
