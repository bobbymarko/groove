class_name FitWorkoutParser
extends RefCounted
## Parses FIT workout files (Garmin, TrainingPeaks, Wahoo): message 26 names
## the workout, message 27 lists steps. Time-based steps with power targets
## become segments; repeat steps are expanded; other targets (heart rate,
## cadence, open) become free-ride blocks. Power is stored as % FTP or, above
## 1000, as watts + 1000.

const MSG_WORKOUT := 26
const MSG_WORKOUT_STEP := 27

const DURATION_TIME := 0
const DURATION_OPEN := 5
const DURATION_REPEAT := 6
const TARGET_POWER := 4
const INTENSITY_ACTIVE := 0
const INTENSITY_REST := 1
const INTENSITY_WARMUP := 2
const INTENSITY_COOLDOWN := 3
const INTENSITY_RECOVERY := 4
const OPEN_STEP_S := 300.0        # a "press lap" step has no length; give it five minutes
## Coggan power zones as FTP fractions [low, high], used when a step targets a zone.
const ZONES := [[0.4, 0.55], [0.56, 0.75], [0.76, 0.9], [0.91, 1.05], [1.06, 1.2], [1.21, 1.5], [1.5, 2.0]]

static var last_error := ""


static func parse_file(path: String, ftp: int) -> Workout:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "Cannot open %s" % path
		return null
	return parse(f.get_buffer(f.get_length()), ftp, path.get_file().get_basename())


static func parse(bytes: PackedByteArray, ftp: int, fallback_name := "Workout") -> Workout:
	last_error = ""
	var decoded := FitReader.read(bytes)
	if decoded.messages.is_empty():
		last_error = "Not a FIT file"
		return null
	var steps: Array[Dictionary] = []
	for m in FitReader.of_type(decoded, MSG_WORKOUT_STEP):
		steps.append(m)
	if steps.is_empty():
		last_error = "No workout steps in this FIT file"
		return null
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get(254, 0)) < int(b.get(254, 0)))
	var w := Workout.new()
	w.name = fallback_name
	for m in FitReader.of_type(decoded, MSG_WORKOUT):
		if str(m.get(8, "")) != "":
			w.name = str(m.get(8))
	for entry in _expand(steps):
		var st: Dictionary = entry.step
		var s := WorkoutSegment.new()
		var dtype := int(st.get(1, DURATION_TIME))
		s.duration = float(int(st.get(2, 0))) / 1000.0 if dtype == DURATION_TIME else OPEN_STEP_S
		var intensity := int(st.get(7, INTENSITY_ACTIVE))
		if int(st.get(3, 0)) == TARGET_POWER:
			var tv := int(st.get(4, 0))
			var lo := 0.0
			var hi := 0.0
			if tv >= 1 and tv <= 7:
				lo = ZONES[tv - 1][0]
				hi = ZONES[tv - 1][1]
			else:
				lo = _power_fraction(int(st.get(5, 0)), ftp)
				hi = _power_fraction(int(st.get(6, 0)), ftp)
			var mid := (lo + hi) * 0.5 if hi > 0.0 else lo
			s.power_low = mid
			s.power_high = mid
			match intensity:
				INTENSITY_WARMUP: s.kind = WorkoutSegment.Kind.WARMUP
				INTENSITY_COOLDOWN: s.kind = WorkoutSegment.Kind.COOLDOWN
				_:
					if int(entry.rep_count) > 0:
						s.kind = WorkoutSegment.Kind.INTERVAL_OFF if intensity in [INTENSITY_REST, INTENSITY_RECOVERY] else WorkoutSegment.Kind.INTERVAL_ON
						s.rep = int(entry.rep)
						s.rep_count = int(entry.rep_count)
					else:
						s.kind = WorkoutSegment.Kind.STEADY
		else:
			s.kind = WorkoutSegment.Kind.FREE_RIDE
		if s.duration <= 0.0:
			continue
		var start := 0.0
		for prev in w.segments:
			start += prev.duration
		var note := str(st.get(8, ""))
		if note != "" and (int(entry.rep) <= 1):
			w.text_events.append({"time": start, "message": note})
		w.segments.append(s)
	if w.segments.is_empty():
		last_error = "No usable steps (time-based steps needed)"
		return null
	w.rebuild_index()
	return w


static func _power_fraction(v: int, ftp: int) -> float:
	if v <= 0 or v == 0xFFFFFFFF:
		return 0.0
	if v > 1000:
		return float(v - 1000) / maxf(float(ftp), 1.0)
	return float(v) / 100.0


## Expand repeat steps: [{step, rep, rep_count}] in ride order. A repeat step
## says "go back to step N until this block has run K times".
static func _expand(steps: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var marks: Array[int] = []   # out.size() when each step began
	for i in steps.size():
		var st := steps[i]
		marks.append(out.size())
		if int(st.get(1, 0)) == DURATION_REPEAT:
			var from := clampi(int(st.get(2, 0)), 0, i)
			var count := maxi(int(st.get(4, 1)), 1)
			var block := out.slice(marks[from])
			out = out.slice(0, marks[from])
			for r in count:
				for e in block:
					var copy: Dictionary = e.duplicate()
					if int(copy.rep_count) == 0:
						copy.rep = r + 1
						copy.rep_count = count
					out.append(copy)
		else:
			out.append({"step": st, "rep": 0, "rep_count": 0})
	return out
