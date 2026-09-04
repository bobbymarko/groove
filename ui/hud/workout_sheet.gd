class_name WorkoutSheet
extends SideSheet
## Side sheet with one workout's details: plan graph, estimates, description,
## block list and the Ride buttons.

var workout: Workout
var _ride: Button
var _devices_l: Label


func _ready() -> void:
	width = 500.0
	super._ready()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())


func open(w: Workout) -> void:
	workout = w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_build_content(v)
	show_content(v)
	_refresh_devices()


func _refresh_devices() -> void:
	if _ride == null or not is_instance_valid(_ride):
		return
	if Devices.real_trainer_ready():
		_ride.text = "Ride"
		_ride.disabled = false
		_devices_l.text = "%s connected" % Devices.trainer.display_name()
	elif Devices.remembered.has("trainer"):
		_ride.text = "Waiting for %s…" % Devices.remembered.trainer.name
		_ride.disabled = true
		_devices_l.text = "Looking for your trainer"
	else:
		_ride.text = "Pair a trainer to ride"
		_ride.disabled = true
		_devices_l.text = "No trainer paired"


func _start(simulator: bool) -> void:
	choose_scene(simulator)


## Step two: pick the world to ride in, then go.
func choose_scene(simulator: bool) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	header(v, "Choose a scene", func() -> void: open(workout))
	HudStyle.label(v, workout.name, 14, 500, HudStyle.TEXT_DIM)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var cards: Dictionary = {}
	for id in ScenePreset.ORDER:
		var p := ScenePreset.get_preset(id)
		var card := HudStyle.panel(grid, HudStyle.CARD, 10, 10)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var thumb_path := ScenePreset.thumbnail_path(id)
		if ResourceLoader.exists(thumb_path):
			var tr := TextureRect.new()
			tr.texture = load(thumb_path)
			tr.custom_minimum_size = Vector2(0, 120 if ScenePreset.ORDER.size() <= 4 else 88)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.clip_contents = true
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(tr)
		HudStyle.label(cv, str(p.name), 16, 700).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := HudStyle.label(cv, str(p.description), 12, 500, HudStyle.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards[id] = card
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				App.scene_preset = id
				App.save_settings()
				_mark_scene_cards(cards))
	_mark_scene_cards(cards)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var go := HudStyle.button(v, "Ride", 18, func() -> void:
		App.workout = workout
		if simulator:
			Devices.use_simulated_devices()
		App.go_to("res://ui/screens/ride_screen.tscn"))
	go.custom_minimum_size.y = 44
	replace_content(v)


func _mark_scene_cards(cards: Dictionary) -> void:
	for id in cards:
		var card: PanelContainer = cards[id]
		var chosen: bool = id == App.scene_preset
		card.add_theme_stylebox_override("panel", HudStyle.flat(HudStyle.CARD if not chosen else Color(0.22, 0.26, 0.36, 0.95), 10, 10, 8,
			Color(0.75, 0.8, 0.95, 0.9) if chosen else Color(0, 0, 0, 0)))


func _build_content(v: VBoxContainer) -> void:
	var w := workout
	var ftp := App.ftp
	header(v, w.name)

	var graph := WorkoutGraph.new()
	graph.custom_minimum_size.y = 130
	graph.set_workout(w)
	v.add_child(graph)

	var est := WorkoutSummary.estimates(w, ftp)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_stat(grid, WorkoutSummary.duration(w.total_duration()), "duration")
	_stat(grid, "%d" % int(round(est.kj)), "kJ at %d W FTP" % ftp)
	_stat(grid, "%d" % int(round(est.tss)), "TSS")
	_stat(grid, "%.2f" % float(est.intensity_factor), "intensity")
	var kcal := RideMetrics.kcal_from_kj(float(est.kj))
	_stat(grid, "%d" % int(round(kcal)), "kcal")
	_stat(grid, "%.1f" % RideMetrics.pizza_slices(kcal), "slices of pizza")

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	if w.description != "":
		_coach_note(body, w.description)
	HudStyle.label(body, "Blocks", 14, 700, HudStyle.TEXT_DIM)
	var blocks := HudStyle.panel(body, HudStyle.PANEL, 8, 8)
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 4)
	blocks.add_child(bl)
	for r in WorkoutSummary.rows(w, ftp):
		HudStyle.block_row(bl, r, 24, 16, Color(0.20, 0.23, 0.31, 0.9))
	if w.author != "":
		HudStyle.label(body, "by %s" % w.author, 13, 500, HudStyle.TEXT_DIM)

	_devices_l = HudStyle.label(v, "", 13, 500, HudStyle.TEXT_DIM)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	_ride = HudStyle.button(bar, "Ride", 18, _start.bind(false))
	_ride.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ride.custom_minimum_size.y = 44
	HudStyle.button(bar, "Simulator", 15, _start.bind(true))


## The workout description, presented as the coach's briefing: avatar on the
## left, speech bubble on the right.
func _coach_note(parent: Control, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var face := TextureRect.new()
	face.texture = load(CoachDialog.PORTRAIT_PATH)
	face.custom_minimum_size = Vector2(56, 56)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(face)
	var bubble := HudStyle.panel(h, HudStyle.CARD, 10, 14)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var desc := HudStyle.label(bubble, text, 15, 500)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 22, 900)
	var u := HudStyle.label(h, unit, 13, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)
