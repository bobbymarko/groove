extends TestCase
## The intervals.icu calendar feed: event filtering, ordering and day labels.


func _event(id: int, date: String, type: String, name: String, with_file := true) -> Dictionary:
	var e := {"id": float(id), "start_date_local": date + "T00:00:00", "type": type, "category": "WORKOUT", "name": name}
	if with_file:
		e["workout_file_base64"] = Marshalls.utf8_to_base64("<workout_file><name>%s</name></workout_file>" % name)
	return e


func test_keeps_only_upcoming_rides_with_files() -> void:
	var rows := IntervalsCalendar.parse_events([
		_event(3, "2026-09-06", "Ride", "Sweet spot"),
		_event(1, "2026-09-02", "Ride", "Yesterday"),          # past
		_event(2, "2026-09-04", "Run", "Easy run"),            # not a ride
		_event(4, "2026-09-04", "Ride", "No file", false),     # note without a file
		_event(5, "2026-09-03", "VirtualRide", "Openers"),
		{"id": 9.0, "category": "NOTE", "start_date_local": "2026-09-03T00:00:00", "type": "Ride"},
	], "2026-09-03")
	assert_true(rows.size() == 2, "expected 2 rows, got %d" % rows.size())
	assert_true(rows[0].name == "Openers" and rows[0].date == "2026-09-03", "today's ride first")
	assert_true(rows[1].id == "3", "ids are plain integers, got %s" % rows[1].id)
	assert_true(str(rows[0].zwo).begins_with("<workout_file>"), "zwo decoded from base64")


func test_ignores_garbage_payloads() -> void:
	assert_true(IntervalsCalendar.parse_events(null, "2026-09-03").is_empty())
	assert_true(IntervalsCalendar.parse_events({"error": "nope"}, "2026-09-03").is_empty())
	assert_true(IntervalsCalendar.parse_events(["x", 3], "2026-09-03").is_empty())


func test_day_labels() -> void:
	assert_true(IntervalsCalendar.day_label("2026-09-03", "2026-09-03") == "Today")
	assert_true(IntervalsCalendar.day_label("2026-09-04", "2026-09-03") == "Tomorrow")
	var l := IntervalsCalendar.day_label("2026-09-10", "2026-09-03")
	assert_true(l == "Thursday, Sep 10", "got %s" % l)
	assert_true(IntervalsCalendar.date_offset("2026-08-31", 1) == "2026-09-01", "month rollover")
