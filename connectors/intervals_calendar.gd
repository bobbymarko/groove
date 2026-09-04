class_name IntervalsCalendar
extends Node
## Planned workouts from the intervals.icu calendar. Fetches the next two weeks
## of WORKOUT events as .zwo files (one request, files come base64-encoded in
## the event list), caches them under user://intervals/, and hands them to the
## home screen grouped by day. Only rides are shown; runs, notes and races are
## skipped.

signal updated

const CACHE_DIR := "user://intervals"
const INDEX_PATH := "user://intervals/events.json"
const DAYS_AHEAD := 14
const STALE_AFTER_S := 300

const DAY_NAMES := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTH_NAMES := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var connector: IntervalsConnector     ## set by Sync; supplies the API key
var entries: Array[Dictionary] = []   ## {id, date, name, type, path}, soonest first
var status := ""                       ## what the home screen should say while fetching or after an error
var busy := false
var preview := false                   ## tooling: entries were injected, never fetch or write
var last_refresh := 0
var last_summary := ""                 ## diagnostics: one line per event, no secrets

var _http: HTTPRequest


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.request_completed.connect(_on_completed)
	add_child(_http)
	_load_cache()


static func today() -> String:
	return Time.get_date_string_from_system(false)


static func date_offset(date: String, days: int) -> String:
	var t := Time.get_unix_time_from_datetime_string(date + "T12:00:00") + days * 86400
	return Time.get_date_string_from_unix_time(t)


## "Today", "Tomorrow", then "Thursday, Sep 10".
static func day_label(date: String, today_str: String) -> String:
	if date == today_str:
		return "Today"
	if date == date_offset(today_str, 1):
		return "Tomorrow"
	var dt := Time.get_datetime_dict_from_datetime_string(date + "T00:00:00", true)
	return "%s, %s %d" % [DAY_NAMES[int(dt.weekday)], MONTH_NAMES[int(dt.month) - 1], int(dt.day)]


## Event list from the API -> [{id, date, name, type, zwo}], soonest first.
## Past days, non-ride events and events without a workout file are dropped.
static func parse_events(json: Variant, today_str: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (json is Array):
		return out
	for e in json:
		if not (e is Dictionary):
			continue
		if str(e.get("category", "WORKOUT")) != "WORKOUT":
			continue
		var type := str(e.get("type", ""))
		if type not in ["Ride", "VirtualRide"]:
			continue
		var b64 := str(e.get("workout_file_base64", ""))
		if b64 == "":
			continue
		var date := str(e.get("start_date_local", "")).left(10)
		if date.length() != 10 or date < today_str:
			continue
		var id_v: Variant = e.get("id", "")
		var id := str(int(id_v)) if id_v is float else str(id_v)
		out.append({
			"id": id, "date": date, "type": type,
			"name": str(e.get("name", "Workout")),
			"zwo": Marshalls.base64_to_utf8(b64),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.date < b.date if a.date != b.date else a.id < b.id)
	return out


## "date type category file?" per event, for diagnostics.
static func summarize(json: Variant) -> String:
	if not (json is Array):
		return "not a list: %s" % str(json).left(120)
	var lines: PackedStringArray = []
	for e in json:
		if e is Dictionary:
			lines.append("%s %s %s %s" % [str(e.get("start_date_local", "")).left(10), str(e.get("type", "")),
				str(e.get("category", "")), "file" if str(e.get("workout_file_base64", "")) != "" else "nofile"])
	return "%d events\n%s" % [json.size(), "\n".join(lines)]


## Entries grouped by day: [{date, label, entries}], soonest first.
func by_day() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := today()
	for e in entries:
		if out.is_empty() or out[-1].date != e.date:
			out.append({"date": e.date, "label": day_label(e.date, t), "entries": []})
		out[-1].entries.append(e)
	return out


func refresh_if_stale() -> void:
	if Time.get_unix_time_from_system() - last_refresh >= STALE_AFTER_S:
		refresh()


func refresh() -> void:
	if preview:
		return
	var icu := connector
	if icu == null or not icu.is_configured():
		entries = []
		status = ""
		updated.emit()
		return
	if busy:
		return
	busy = true
	status = "Fetching your intervals.icu calendar…"
	updated.emit()
	var t := today()
	var url := "%s/athlete/0/events?oldest=%s&newest=%s&category=WORKOUT&ext=zwo" % [
		IntervalsConnector.BASE_URL, t, date_offset(t, DAYS_AHEAD)]
	var err := _http.request(url, PackedStringArray([icu.auth_header()]))
	if err != OK:
		busy = false
		status = "Calendar request failed: %s" % error_string(err)
		updated.emit()


## Tooling: show these entries without touching the network or the cache.
func set_preview(rows: Array[Dictionary]) -> void:
	preview = true
	entries = rows
	status = ""
	updated.emit()


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	last_refresh = int(Time.get_unix_time_from_system())
	if preview:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		status = "Calendar: network error, showing cached workouts"
	elif code == 401 or code == 403:
		status = "Calendar: intervals.icu rejected the API key"
	elif code < 200 or code >= 300:
		status = "Calendar: intervals.icu returned %d" % code
	else:
		status = ""
		var json: Variant = JSON.parse_string(body.get_string_from_utf8())
		last_summary = summarize(json)
		_store(parse_events(json, today()))
	updated.emit()


## Replace the cache with the fresh list: one .zwo per event plus an index.
func _store(parsed: Array[Dictionary]) -> void:
	var d := DirAccess.open(CACHE_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".zwo"):
				d.remove(f)
	entries = []
	for p in parsed:
		var path := CACHE_DIR.path_join("%s.zwo" % p.id)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(str(p.zwo))
		f.close()
		entries.append({"id": p.id, "date": p.date, "name": p.name, "type": p.type, "path": path})
	var idx := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if idx:
		idx.store_string(JSON.stringify(entries))
		idx.close()


func _load_cache() -> void:
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if not (json is Array):
		return
	var t := today()
	for r in json:
		if r is Dictionary and str(r.get("date", "")) >= t and FileAccess.file_exists(str(r.get("path", ""))):
			entries.append(r)
