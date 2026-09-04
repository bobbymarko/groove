class_name RidesPanel
extends VBoxContainer
## Recent rides for a side sheet: one row per ride, click to open the summary.

var _entries: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_entries = App.list_rides()
	if _entries.is_empty():
		HudStyle.label(self, "No rides yet.", 15, 500, HudStyle.TEXT_DIM)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for r in _entries:
		var row := HudStyle.panel(list, HudStyle.PANEL_ROW, 6, 10)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var when := Time.get_datetime_string_from_unix_time(int(r.meta.get("started_at", 0)), true).replace("T", "  ")
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(left)
		HudStyle.label(left, str(r.meta.get("workout", "Ride")), 16, 700)
		HudStyle.label(left, when.left(18) + ("" if r.finished else "   ·   unfinished"), 12, 500, HudStyle.TEXT_DIM)
		HudStyle.label(h, "%d min" % (int(r.samples) / 60), 18, 900).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var journal: String = r.journal
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				App.last_ride_journal = journal
				App.go_to("res://ui/screens/summary_screen.tscn"))
		row.mouse_entered.connect(func() -> void: row.modulate = Color(1.15, 1.15, 1.2))
		row.mouse_exited.connect(func() -> void: row.modulate = Color.WHITE)
	HudStyle.button(self, "Open rides folder", 14, func() -> void: OS.shell_open(RideRecorder.rides_dir_abs())).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
