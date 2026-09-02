class_name Workout
extends RefCounted
## A structured workout: ordered segments plus text events at absolute times.

var name := ""
var author := ""
var description := ""
var segments: Array[WorkoutSegment] = []
var text_events: Array[Dictionary] = []   ## {time: float (seconds from start), message: String}

var _starts: PackedFloat64Array = []
var _total := 0.0


func rebuild_index() -> void:
	_starts.clear()
	var t := 0.0
	for s in segments:
		_starts.append(t)
		t += s.duration
	_total = t
	text_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)


func total_duration() -> float:
	return _total


func segment_start(index: int) -> float:
	return _starts[index] if index >= 0 and index < _starts.size() else _total


func segment_end(index: int) -> float:
	return segment_start(index) + segments[index].duration


## Index of the segment containing time t, or -1 when t is past the end.
func segment_index_at(t: float) -> int:
	if t < 0.0 or t >= _total or segments.is_empty():
		return -1
	# Segments are few (tens); a linear scan is fine and avoids edge cases.
	for i in range(segments.size() - 1, -1, -1):
		if t >= _starts[i]:
			return i
	return 0


## Target as a fraction of FTP at time t. 0 when the segment has no target.
func target_fraction_at(t: float) -> float:
	var i := segment_index_at(t)
	if i < 0:
		return 0.0
	var s := segments[i]
	return s.power_at(t - _starts[i]) if s.has_target() else 0.0


func peak_fraction() -> float:
	var p := 0.0
	for s in segments:
		p = maxf(p, s.peak())
	return p


## Simple work estimate in kilojoules at a given FTP, assuming perfect compliance.
func estimated_kj(ftp: int) -> float:
	var kj := 0.0
	for s in segments:
		if s.has_target():
			kj += (s.power_low + s.power_high) * 0.5 * ftp * s.duration / 1000.0
	return kj
