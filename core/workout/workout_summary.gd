class_name WorkoutSummary
extends RefCounted
## Display helpers for a Workout: collapsed block rows for lists, one-line
## summaries for cards, and plan-level estimates at a given FTP.


## Human duration like "10min", "1min", "30s", "1:30".
static func duration(seconds: float) -> String:
	var s := int(round(seconds))
	if s % 60 == 0:
		return "%dmin" % (s / 60)
	if s < 60:
		return "%ds" % s
	return "%d:%02d" % [s / 60, s % 60]


## Rows for a block list. Interval sets collapse into one row:
## {"kind": "intervals", first, last, count, on_dur, on_w, off_dur, off_w} or
## {"kind": "single", first, last, text}.
static func rows(w: Workout, ftp: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < w.segments.size():
		var s := w.segments[i]
		if s.kind == WorkoutSegment.Kind.INTERVAL_ON and s.rep == 1:
			var last := i
			var off: WorkoutSegment = null
			while last + 1 < w.segments.size() and w.segments[last + 1].kind in [WorkoutSegment.Kind.INTERVAL_ON, WorkoutSegment.Kind.INTERVAL_OFF] and w.segments[last + 1].rep_count == s.rep_count:
				last += 1
				if off == null and w.segments[last].kind == WorkoutSegment.Kind.INTERVAL_OFF:
					off = w.segments[last]
			out.append({"kind": "intervals", "first": i, "last": last, "count": s.rep_count, "peak": s.power_low, "has_target": true,
				"on_dur": s.duration, "on_w": round(s.power_low * ftp),
				"off_dur": off.duration if off else 0.0, "off_w": round(off.power_low * ftp) if off else 0.0})
			i = last + 1
			continue
		var text := ""
		match s.kind:
			WorkoutSegment.Kind.WARMUP: text = "%s warmup" % duration(s.duration)
			WorkoutSegment.Kind.COOLDOWN: text = "%s cool down" % duration(s.duration)
			WorkoutSegment.Kind.FREE_RIDE: text = "%s free ride" % duration(s.duration)
			WorkoutSegment.Kind.MAX_EFFORT: text = "%s max effort" % duration(s.duration)
			_:
				if s.is_ramp():
					text = "%s %d→%dw" % [duration(s.duration), int(round(s.power_low * ftp)), int(round(s.power_high * ftp))]
				else:
					text = "%s @ %dw" % [duration(s.duration), int(round(s.power_low * ftp))]
		out.append({"kind": "single", "first": i, "last": i, "text": text, "peak": s.peak(), "has_target": s.has_target()})
		i += 1
	return out


## One line for a card, e.g. "6 x 1min @ 212w" or "60min @ 150w".
static func headline(w: Workout, ftp: int) -> String:
	var best := ""
	var best_peak := -1.0
	for r in rows(w, ftp):
		if r.kind == "intervals":
			return "%d x %s @ %dw" % [int(r.count), duration(r.on_dur), int(r.on_w)]
		var seg := w.segments[int(r.first)]
		if seg.has_target() and seg.peak() > best_peak:
			best_peak = seg.peak()
			best = r.text
	return best


## Plan estimates assuming perfect compliance: {kj, tss, intensity_factor}.
static func estimates(w: Workout, ftp: int) -> Dictionary:
	var kj := 0.0
	var tss := 0.0
	var weighted := 0.0
	for s in w.segments:
		if not s.has_target():
			continue
		var mean_frac := (s.power_low + s.power_high) * 0.5
		kj += mean_frac * ftp * s.duration / 1000.0
		# TSS = seconds * IF^2 / 3600 * 100 with IF = fraction of FTP.
		tss += s.duration * mean_frac * mean_frac / 3600.0 * 100.0
		weighted += mean_frac * s.duration
	var total := maxf(w.total_duration(), 1.0)
	return {"kj": kj, "tss": tss, "intensity_factor": weighted / total}
