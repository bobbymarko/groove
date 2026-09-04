class_name WorkoutGraph
extends Control
## Draws the workout as bars: width = duration, height = power fraction of FTP.
## Ramps draw as slopes. A playhead marks the current time.

var workout: Workout
var elapsed := 0.0
var bias := 100
## Heart-rate trace: one sample per second, drawn over the plan as the ride progresses.
var _hr_times: PackedFloat32Array = []
var _hr_values: PackedFloat32Array = []
const HR_MIN := 60.0
const HR_MAX := 190.0
const HR_COLOR := WorkoutColors.HR


func set_workout(w: Workout) -> void:
	workout = w
	queue_redraw()


func set_progress(t: float, b: int) -> void:
	elapsed = t
	bias = b
	queue_redraw()


func add_heart_rate(t: float, bpm: int) -> void:
	if bpm <= 0:
		return
	_hr_times.append(t)
	_hr_values.append(bpm)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.35))
	if workout == null or workout.total_duration() <= 0.0:
		return
	var total := workout.total_duration()
	var peak := maxf(workout.peak_fraction(), 1.0) * 1.05
	var ftp_y := r.size.y - (1.0 / peak) * r.size.y
	draw_line(Vector2(0, ftp_y), Vector2(r.size.x, ftp_y), Color(1, 1, 1, 0.25), 1.0)

	for i in workout.segments.size():
		var s := workout.segments[i]
		var x0 := workout.segment_start(i) / total * r.size.x
		var x1 := workout.segment_end(i) / total * r.size.x
		var w := maxf(x1 - x0 - 1.0, 1.0)
		var col := WorkoutColors.for_segment(s)
		if workout.segment_end(i) <= elapsed:
			col.a = WorkoutColors.DONE_ALPHA
		var lo := s.power_low if s.has_target() else 0.3
		var hi := s.power_high if s.has_target() else 0.3
		var y_lo := r.size.y - (lo / peak) * r.size.y
		var y_hi := r.size.y - (hi / peak) * r.size.y
		var pts := PackedVector2Array([
			Vector2(x0, r.size.y), Vector2(x0, y_lo), Vector2(x0 + w, y_hi), Vector2(x0 + w, r.size.y)])
		draw_colored_polygon(pts, col)

	# Heart rate over the plan, scaled from HR_MIN (bottom) to HR_MAX (top).
	if _hr_times.size() > 1:
		var pts := PackedVector2Array()
		for i in _hr_times.size():
			var x := _hr_times[i] / total * r.size.x
			var y := r.size.y - clampf((_hr_values[i] - HR_MIN) / (HR_MAX - HR_MIN), 0.0, 1.0) * r.size.y
			pts.append(Vector2(x, y))
		draw_polyline(pts, HR_COLOR, 2.0, true)
		draw_circle(pts[-1], 3.5, HR_COLOR)
	var px := clampf(elapsed / total, 0.0, 1.0) * r.size.x
	draw_line(Vector2(px, 0), Vector2(px, r.size.y), Color(1, 1, 1, 0.9), 2.0)
