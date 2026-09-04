class_name WorkoutGraph
extends Control
## The groove: the workout drawn as one continuous path whose height is the
## target power and whose colour is the zone (WorkoutColors). While riding, a
## glowing marker travels along it, the part behind it brightens, the rider's
## own power runs as a thin ice line and heart rate as a thin red one.

var workout: Workout
var elapsed := 0.0
var bias := 100
var show_marker := true        ## false for cards and sheets (no ride in progress)

var _hr_times: PackedFloat32Array = []
var _hr_values: PackedFloat32Array = []
var _pw_times: PackedFloat32Array = []
var _pw_values: PackedFloat32Array = []   # fraction of FTP
const HR_MIN := 60.0
const HR_MAX := 190.0


func set_workout(w: Workout) -> void:
	workout = w
	_hr_times.clear(); _hr_values.clear(); _pw_times.clear(); _pw_values.clear()
	queue_redraw()


func set_progress(t: float, b: int) -> void:
	elapsed = t
	bias = b
	queue_redraw()


func add_heart_rate(t: float, bpm: int) -> void:
	if bpm > 0:
		_hr_times.append(t)
		_hr_values.append(float(bpm))


## Actual power as a fraction of FTP, once a second.
func add_power(t: float, fraction: float) -> void:
	_pw_times.append(t)
	_pw_values.append(fraction)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(HudStyle.INK, 0.45))
	if workout == null or workout.total_duration() <= 0.0:
		return
	var total := workout.total_duration()
	var peak := maxf(workout.peak_fraction(), 1.0) * 1.12
	var pad := 4.0
	var h := r.size.y - pad * 2.0
	var y_of := func(frac: float) -> float: return pad + h - clampf(frac / peak, 0.0, 1.0) * h
	var x_of := func(t: float) -> float: return t / total * r.size.x
	var line_w := clampf(r.size.y * 0.06, 2.0, 6.0)
	# FTP guide.
	var ftp_y: float = y_of.call(1.0)
	draw_dashed_line(Vector2(0, ftp_y), Vector2(r.size.x, ftp_y), Color(HudStyle.ICE, 0.18), 1.0, 6.0)
	# Soft fill under the groove, then the path itself, segment by segment.
	var riding := show_marker and elapsed > 0.0
	var prev_end := Vector2(-1, -1)
	for i in workout.segments.size():
		var s := workout.segments[i]
		var t0 := workout.segment_start(i)
		var t1 := workout.segment_end(i)
		var lo := s.power_low if s.has_target() else 0.3
		var hi := s.power_high if s.has_target() else 0.3
		var a := Vector2(x_of.call(t0), y_of.call(lo))
		var b := Vector2(x_of.call(t1), y_of.call(hi))
		var col := WorkoutColors.for_segment(s)
		var done := riding and t1 <= elapsed
		var ahead := riding and t0 > elapsed
		var alpha := 1.0 if not riding else (0.55 if ahead else 1.0)
		var fill := Color(col, 0.16 * alpha)
		draw_colored_polygon(PackedVector2Array([Vector2(a.x, pad + h), a, b, Vector2(b.x, pad + h)]), fill)
		var stroke := Color(col, alpha)
		if done:
			stroke = col.lightened(0.15)
		# Vertical riser from the previous block to this one, in this block's colour.
		if prev_end.x >= 0.0 and absf(prev_end.y - a.y) > 0.5:
			draw_line(Vector2(a.x, prev_end.y), a, stroke, line_w)
		draw_line(a, b, stroke, line_w)
		prev_end = b
	# Rider's power, then heart rate, as thin lines.
	if _pw_times.size() > 1:
		var pts := PackedVector2Array()
		for i in _pw_times.size():
			pts.append(Vector2(x_of.call(_pw_times[i]), y_of.call(_pw_values[i])))
		draw_polyline(pts, Color(WorkoutColors.POWER, 0.85), 1.5, true)
	if _hr_times.size() > 1:
		var pts := PackedVector2Array()
		for i in _hr_times.size():
			pts.append(Vector2(x_of.call(_hr_times[i]), pad + h - clampf((_hr_values[i] - HR_MIN) / (HR_MAX - HR_MIN), 0.0, 1.0) * h))
		draw_polyline(pts, Color(WorkoutColors.HR, 0.9), 1.5, true)
	# The marker: a white glow sitting on the groove at the current target.
	if riding:
		var t := clampf(elapsed, 0.0, total)
		var frac := workout.target_fraction_at(t) * bias / 100.0
		var m := Vector2(x_of.call(t), y_of.call(frac))
		draw_line(Vector2(m.x, pad), Vector2(m.x, pad + h), Color(HudStyle.ICE, 0.25), 1.0)
		var rad := line_w * 1.1
		draw_circle(m, rad * 3.2, Color(WorkoutColors.GLOW, 0.10))
		draw_circle(m, rad * 2.1, Color(WorkoutColors.GLOW, 0.22))
		draw_circle(m, rad * 1.35, Color(WorkoutColors.GLOW, 0.55))
		draw_circle(m, rad * 0.8, WorkoutColors.GLOW)
