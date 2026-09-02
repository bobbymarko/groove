class_name ZwoParser
extends RefCounted
## Parses Zwift .zwo workout files into a Workout.
##
## Supported blocks: Warmup, Cooldown, Ramp, SteadyState, IntervalsT, FreeRide,
## MaxEffort. textevent children are attached at absolute times; inside a block
## their timeoffset is relative to the start of that block, which for
## IntervalsT means the start of the whole repeat set (Zwift's behavior).

static var last_error := ""


static func parse_file(path: String) -> Workout:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "Cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		return null
	return parse(f.get_as_text())


static func parse(text: String) -> Workout:
	last_error = ""
	var p := XMLParser.new()
	if p.open_buffer(text.to_utf8_buffer()) != OK:
		last_error = "File is not valid XML"
		return null

	var w := Workout.new()
	var in_workout := false
	var block: Dictionary = {}                 # {name, attrs} of the block being read
	var block_events: Array[Dictionary] = []
	var text_field := ""                       # name/author/description being read
	var sport := "bike"

	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := p.get_node_name()
				var attrs := _attributes(p)
				if n == "workout":
					in_workout = true
				elif in_workout:
					if n == "textevent":
						block_events.append({
							"offset": float(attrs.get("timeoffset", "0")),
							"message": _unescape(attrs.get("message", "")),
						})
					elif block.is_empty():
						block = {"name": n, "attrs": attrs}
						block_events = []
						if p.is_empty():
							_add_block(w, block, block_events)
							block = {}
				elif n in ["name", "author", "description", "sportType"]:
					text_field = n
			XMLParser.NODE_TEXT:
				if text_field != "":
					var t := _unescape(p.get_node_data().strip_edges())
					if t != "":
						match text_field:
							"name": w.name = t
							"author": w.author = t
							"description": w.description = t
							"sportType": sport = t
			XMLParser.NODE_ELEMENT_END:
				var n := p.get_node_name()
				if n == "workout":
					in_workout = false
				elif in_workout and not block.is_empty() and n == block["name"]:
					_add_block(w, block, block_events)
					block = {}
				elif n == text_field:
					text_field = ""

	if sport.to_lower() != "bike":
		last_error = "Not a cycling workout (sportType=%s)" % sport
		return null
	if w.segments.is_empty():
		last_error = "No workout segments found"
		return null
	w.rebuild_index()
	return w


static func _add_block(w: Workout, block: Dictionary, events: Array[Dictionary]) -> void:
	var a: Dictionary = block["attrs"]
	var start := _sum_duration(w)
	match block["name"]:
		"Warmup":
			_add_ramp(w, a, WorkoutSegment.Kind.WARMUP)
		"Cooldown":
			_add_ramp(w, a, WorkoutSegment.Kind.COOLDOWN)
		"Ramp":
			_add_ramp(w, a, WorkoutSegment.Kind.RAMP)
		"SteadyState":
			var s := WorkoutSegment.new()
			s.kind = WorkoutSegment.Kind.STEADY
			s.duration = _num(a, "Duration")
			s.power_low = _num(a, "Power", 0.5)
			s.power_high = s.power_low
			s.cadence = int(_num(a, "Cadence"))
			_append(w, s)
		"IntervalsT":
			var reps := int(_num(a, "Repeat", 1))
			for r in reps:
				var on := WorkoutSegment.new()
				on.kind = WorkoutSegment.Kind.INTERVAL_ON
				on.duration = _num(a, "OnDuration")
				on.power_low = _num(a, "OnPower", 1.0)
				on.power_high = on.power_low
				on.cadence = int(_num(a, "Cadence"))
				on.rep = r + 1
				on.rep_count = reps
				_append(w, on)
				var off := WorkoutSegment.new()
				off.kind = WorkoutSegment.Kind.INTERVAL_OFF
				off.duration = _num(a, "OffDuration")
				off.power_low = _num(a, "OffPower", 0.5)
				off.power_high = off.power_low
				off.cadence = int(_num(a, "CadenceResting"))
				off.rep = r + 1
				off.rep_count = reps
				_append(w, off)
		"FreeRide":
			var s := WorkoutSegment.new()
			s.kind = WorkoutSegment.Kind.FREE_RIDE
			s.duration = _num(a, "Duration")
			_append(w, s)
		"MaxEffort":
			var s := WorkoutSegment.new()
			s.kind = WorkoutSegment.Kind.MAX_EFFORT
			s.duration = _num(a, "Duration")
			_append(w, s)
		_:
			return  # unknown block: ignore, including its text events
	for e in events:
		w.text_events.append({"time": start + e.offset, "message": e.message})


static func _add_ramp(w: Workout, a: Dictionary, kind: WorkoutSegment.Kind) -> void:
	var s := WorkoutSegment.new()
	s.kind = kind
	s.duration = _num(a, "Duration")
	var flat := _num(a, "Power", -1.0)
	s.power_low = _num(a, "PowerLow", flat if flat >= 0.0 else 0.5)
	s.power_high = _num(a, "PowerHigh", flat if flat >= 0.0 else s.power_low)
	s.cadence = int(_num(a, "Cadence"))
	_append(w, s)


static func _append(w: Workout, s: WorkoutSegment) -> void:
	if s.duration > 0.0:
		w.segments.append(s)


static func _sum_duration(w: Workout) -> float:
	var t := 0.0
	for s in w.segments:
		t += s.duration
	return t


static func _attributes(p: XMLParser) -> Dictionary:
	var d := {}
	for i in p.get_attribute_count():
		d[p.get_attribute_name(i)] = p.get_attribute_value(i)
	return d


static func _num(a: Dictionary, key: String, default_value: float = 0.0) -> float:
	var v: String = a.get(key, "")
	return float(v) if v.is_valid_float() else default_value


static func _unescape(s: String) -> String:
	return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"") \
		.replace("&apos;", "'").replace("&#39;", "'").replace("&amp;", "&")
