class_name RouteSheet
extends SideSheet
## Side sheet for one imported route (R41): its profile and scenery, then how
## to ride it: a free ride (the trainer follows the real grade, scaled by the
## hill feel) or a workout on the route (ERG as usual; the route gives the hills
## and the scenery).

var route: Route
var path := ""
var _free := true
var _workout_files: Array[String] = []
var _workout_pick: OptionButton
var _workout_row: Control
var _ride: Button
var _devices_l: Label


func _ready() -> void:
	width = 940.0
	super._ready()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())
	App.route_scenery_ready.connect(func(p: String) -> void:
		if p == path and is_open():
			open(path))


func open(gpx_path: String) -> void:
	path = gpx_path
	route = RouteLibrary.load_route(gpx_path)
	if route == null:
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_build(v)
	if is_open():
		replace_content(v)
	else:
		show_content(v)
	_refresh_devices()


func _build(v: VBoxContainer) -> void:
	header(v, route.name)
	var prof := RouteProfile.new()
	prof.custom_minimum_size.y = 140
	prof.band_height = 10.0
	prof.set_route(route)
	v.add_child(prof)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	v.add_child(grid)
	_stat(grid, App.distance_text(route.length), App.distance_unit().to_lower())
	_stat(grid, "%d" % int(round(route.climb)), "m of climbing" if route.has_elevation else "m (the file has no heights: flat)")
	var steepest := 0.0
	var d := 0.0
	while d < route.length:
		steepest = maxf(steepest, route.grade_at(d))
		d += 50.0
	_stat(grid, "%d %%" % int(round(steepest)), "steepest")

	# What the land is like along the way.
	var scen := HudStyle.label(v, _scenery_text(), 15, 500, HudStyle.TEXT_DIM)
	scen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if route.estimated:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var why := HudStyle.label(h, "OpenStreetMap could not be reached, so the scenery is a guess from the climate.", 13, 500, HudStyle.ORANGE)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudStyle.button(h, "Look up again", 13, func() -> void:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RouteLibrary.sidecar_path(path)))
			App.look_up_route(path)
			open(path), "secondary")

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)

	HudStyle.segmented(v, ["Free ride", "With a workout"], 0 if _free else 1, func(i: int) -> void:
		_free = i == 0
		_workout_row.visible = not _free, 15)
	# Free ride: how much of the real grade the trainer applies.
	var hill := HBoxContainer.new()
	hill.add_theme_constant_override("separation", 12)
	v.add_child(hill)
	HudStyle.label(hill, "Hill feel", 14, 700)
	var s := HudStyle.slider(hill)
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 5.0
	s.value = App.route_difficulty * 100.0
	var val := HudStyle.label(hill, "%d %%" % int(s.value), 14, 700)
	val.custom_minimum_size.x = 56
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d %%" % int(x)
		App.route_difficulty = x / 100.0
		App.save_settings())
	var hill_note := HudStyle.label(v, "Free ride: the trainer gets harder up the real climbs. 100 % is the true grade; 50 % (like Zwift's default) halves it.", 12, 500, HudStyle.TEXT_DIM)
	hill_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# With a workout: pick one; ERG holds its targets while the route gives the hills and scenery.
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	v.add_child(wrow)
	_workout_row = wrow
	HudStyle.label(wrow, "Workout", 14, 700)
	_workout_pick = OptionButton.new()
	_workout_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workout_pick.add_theme_font_override("font", HudStyle.font(500, 16))
	_workout_pick.add_theme_font_size_override("font_size", 16)
	wrow.add_child(_workout_pick)
	_workout_files.clear()
	for f in App.list_workout_files():
		var w := WorkoutLoader.load_file(f, App.ftp)
		if w == null:
			continue
		_workout_files.append(f)
		_workout_pick.add_item("%s  ·  %s" % [w.name, WorkoutSummary.duration(w.total_duration())])
	wrow.visible = not _free

	_devices_l = HudStyle.label(v, "", 13, 500, HudStyle.TEXT_DIM)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	_ride = HudStyle.button(bar, "Ride", 18, _go.bind(false), "primary")
	_ride.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ride.custom_minimum_size.y = 44
	HudStyle.button(bar, "Simulator", 15, _go.bind(true), "secondary")
	HudStyle.label(v, "Scenery from map data © OpenStreetMap contributors", 11, 500, HudStyle.TEXT_DIM)


## "4.2 km of woods, 6.1 km of open fields, water near the trail in 2 places."
func _scenery_text() -> String:
	if App.is_looking_up(path):
		return App.route_lookup.status if App.route_lookup.status != "" else "Looking up the scenery along the route…"
	if route.biomes.is_empty():
		return "Scenery not looked up yet."
	var by := {}
	var waters := 0
	for b in route.biomes:
		var key := _describe(b)
		by[key] = float(by.get(key, 0.0)) + float(b.to) - float(b.from)
		if b.water:
			waters += 1
	var parts: Array[String] = []
	var keys := by.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return by[a] > by[b])
	for k in keys:
		parts.append("%s %s of %s" % [App.distance_text(by[k]), App.distance_unit().to_lower(), k])
	var text := ", ".join(parts)
	if waters > 0:
		text += "; a river or lake beside the trail in %d place%s" % [waters, "" if waters == 1 else "s"]
	return text[0].to_upper() + text.substr(1) + "."


static func _describe(b: Dictionary) -> String:
	var id := str(b.id)
	var trees := float(b.trees)
	if id == "winter":
		return "snow"
	if id == "desert":
		return "desert"
	var season: String = {"summer": "summer", "spring": "spring", "autumn": "autumn", "birchwood": "birch"}.get(id, id)
	if trees > 1.0:
		return "%s woods" % season
	if trees < 0.3:
		return "open fields"
	return "light woods and fields"


func _refresh_devices() -> void:
	if _ride == null or not is_instance_valid(_ride):
		return
	if Devices.real_trainer_ready():
		_ride.text = "RIDE"
		_ride.disabled = false
		_devices_l.text = "%s connected" % Devices.trainer.display_name()
	elif Devices.remembered.has("trainer"):
		_ride.text = "WAITING FOR TRAINER…"
		_ride.disabled = true
		_devices_l.text = "Looking for your trainer"
	else:
		_ride.text = "PAIR A TRAINER TO RIDE"
		_ride.disabled = true
		_devices_l.text = "No trainer paired"


func _go(simulator: bool) -> void:
	App.route = route
	App.route_free = _free
	if _free:
		App.workout = route.free_ride_workout()
	else:
		var i := _workout_pick.selected
		if i < 0 or i >= _workout_files.size():
			return
		App.workout = WorkoutLoader.load_file(_workout_files[i], App.ftp)
	if simulator:
		Devices.use_simulated_devices()
	App.go_to("res://ui/screens/ride_screen.tscn")


func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 22, 900)
	var u := HudStyle.label(h, unit, 13, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)
