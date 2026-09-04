class_name RideTrace
extends Control
## A recorded ride at a glance: power per second as bars coloured by effort
## relative to FTP, an FTP line, and optionally the heart-rate trace on top.

const COLOR_EASY := Color(0.35, 0.55, 0.85)
const COLOR_TEMPO := Color(0.62, 0.55, 0.72)
const COLOR_HARD := Color(0.95, 0.45, 0.35)
const HR_COLOR := Color(1.0, 0.42, 0.5)
const HR_MIN := 60.0
const HR_MAX := 190.0

var ftp := 200
var show_hr := true
var _power: PackedFloat32Array = []
var _hr: PackedFloat32Array = []


func set_samples(samples: Array, ftp_w: int) -> void:
	ftp = maxi(ftp_w, 1)
	_power.resize(samples.size())
	_hr.resize(samples.size())
	for i in samples.size():
		var s: Dictionary = samples[i]
		_power[i] = float(s.get("p", 0))
		_hr[i] = float(s.get("h", 0))
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.35))
	var n := _power.size()
	if n == 0:
		return
	var peak := maxf(1.5, _max(_power) / ftp * 1.05)
	var buckets := mini(int(r.size.x), n)
	var bw := r.size.x / buckets
	for b in buckets:
		var i0 := int(float(b) / buckets * n)
		var i1 := maxi(int(float(b + 1) / buckets * n), i0 + 1)
		var sum := 0.0
		for i in range(i0, i1):
			sum += _power[i]
		var frac := (sum / (i1 - i0)) / ftp
		var h := clampf(frac / peak, 0.0, 1.0) * r.size.y
		var col := COLOR_EASY if frac < 0.76 else (COLOR_TEMPO if frac < 0.95 else COLOR_HARD)
		draw_rect(Rect2(b * bw, r.size.y - h, maxf(bw - (1.0 if bw > 2.0 else 0.0), 1.0), h), col)
	var ftp_y := r.size.y - (1.0 / peak) * r.size.y
	draw_line(Vector2(0, ftp_y), Vector2(r.size.x, ftp_y), Color(1, 1, 1, 0.3), 1.0)
	if show_hr:
		var pts := PackedVector2Array()
		var step := maxi(1, n / maxi(int(r.size.x), 1))
		for i in range(0, n, step):
			if _hr[i] <= 0.0:
				continue
			pts.append(Vector2(float(i) / n * r.size.x, r.size.y - clampf((_hr[i] - HR_MIN) / (HR_MAX - HR_MIN), 0.0, 1.0) * r.size.y))
		if pts.size() >= 2:
			draw_polyline(pts, HR_COLOR, 1.5, true)


static func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m
