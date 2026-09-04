class_name ErgParser
extends RefCounted
## Parses .mrc (percent of FTP) and .erg (watts) course files: the plain-text
## format from CompuTrainer and early TrainerRoad, still exported by
## intervals.icu and TrainingPeaks.
##
##   [COURSE HEADER]           [COURSE DATA]        [COURSE TEXT]
##   DESCRIPTION = ...         0.00  50             0  Spin easy  10
##   FTP = 250 (erg only)      5.00  50             ^ seconds  ^ message  ^ duration
##   MINUTES PERCENT           5.00  100
##   [END COURSE HEADER]       [END COURSE DATA]    [END COURSE TEXT]
##
## Each pair of consecutive data points is one segment: flat when both powers
## match, a ramp otherwise. Points at the same minute are step changes.

static var last_error := ""


static func parse_file(path: String, ftp: int) -> Workout:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "Cannot open %s" % path
		return null
	return parse(f.get_as_text(), path.get_extension().to_lower(), ftp, path.get_file().get_basename())


## `ext` is "mrc" or "erg"; `ftp` is used for .erg when the header has no FTP.
static func parse(text: String, ext: String, ftp: int, fallback_name := "Workout") -> Workout:
	last_error = ""
	var w := Workout.new()
	w.name = fallback_name
	var section := ""
	var watts := ext == "erg"
	var file_ftp := 0
	var points: Array[Vector2] = []   # (seconds, fraction of FTP)
	var texts: Array[Dictionary] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			continue
		if line.begins_with("["):
			section = line.to_upper()
			continue
		match section:
			"[COURSE HEADER]":
				if "=" in line:
					var kv := line.split("=", true, 1)
					var key := kv[0].strip_edges().to_upper()
					var val := kv[1].strip_edges()
					match key:
						"DESCRIPTION": w.description = val
						"FILE NAME": w.name = val.get_basename() if val != "" else w.name
						"FTP": file_ftp = int(val)
				else:
					var cols := line.to_upper().split(" ", false)
					if cols.size() >= 2 and cols[0] == "MINUTES":
						watts = cols[1] == "WATTS"
			"[COURSE DATA]":
				var cols := line.split("\t", false) if "\t" in line else line.split(" ", false)
				if cols.size() >= 2 and cols[0].is_valid_float() and cols[1].is_valid_float():
					var p := float(cols[1])
					var f_ftp := file_ftp if file_ftp > 0 else ftp
					var frac := (p / maxf(float(f_ftp), 1.0)) if watts else (p / 100.0)
					points.append(Vector2(float(cols[0]) * 60.0, frac))
			"[COURSE TEXT]":
				var cols := line.split("\t", false) if "\t" in line else line.split(" ", false)
				if cols.size() >= 2 and cols[0].is_valid_float():
					var msg := cols[1]
					if cols.size() >= 3 and not cols[-1].is_valid_float():
						msg = " ".join(cols.slice(1))
					texts.append({"time": float(cols[0]), "message": msg})
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var dur := b.x - a.x
		if dur <= 0.0:
			continue
		var s := WorkoutSegment.new()
		s.duration = dur
		s.power_low = a.y
		s.power_high = b.y
		if s.is_ramp():
			s.kind = WorkoutSegment.Kind.RAMP
		else:
			s.kind = WorkoutSegment.Kind.STEADY
		w.segments.append(s)
	if w.segments.is_empty():
		last_error = "No course data found"
		return null
	# A ramp up at the start is a warm-up; a ramp down at the end a cool-down.
	if w.segments[0].is_ramp() and w.segments[0].power_high > w.segments[0].power_low:
		w.segments[0].kind = WorkoutSegment.Kind.WARMUP
	var last := w.segments[-1]
	if last.is_ramp() and last.power_high < last.power_low:
		last.kind = WorkoutSegment.Kind.COOLDOWN
	w.text_events = texts
	w.rebuild_index()
	return w
