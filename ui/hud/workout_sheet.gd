class_name WorkoutSheet
extends SideSheet
## Side sheet with one workout's details: plan graph, estimates, description,
## block list and the Ride buttons.

var workout: Workout
var _ride: Button
var _devices_l: Label


func _ready() -> void:
	width = 940.0
	super._ready()
	Devices.trainer_changed.connect(func(_t: Trainer) -> void: _refresh_devices())
	Devices.status.connect(func(_s: String) -> void: _refresh_devices())


func open(w: Workout) -> void:
	workout = w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_build_content(v)
	show_content(v)
	_refresh_devices()


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


func _start(simulator: bool) -> void:
	choose_scene(simulator)


## Step two: pick the world to ride in, then go.
func choose_scene(simulator: bool) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	header(v, "Choose a scene", func() -> void: open(workout))
	HudStyle.label(v, workout.name, 14, 500, HudStyle.TEXT_DIM)
	# The cards scroll; the Ride button stays pinned at the bottom of the sheet.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var cards: Dictionary = {}
	for id in ScenePreset.ORDER:
		var p := ScenePreset.get_preset(id)
		var card := HudStyle.panel(grid, HudStyle.CARD, 10, 10)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)
		var thumb_path := ScenePreset.thumbnail_path(id)
		if ResourceLoader.exists(thumb_path):
			var tr := TextureRect.new()
			tr.texture = load(thumb_path)
			tr.custom_minimum_size = Vector2(0, 150)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.clip_contents = true
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(tr)
		HudStyle.label(cv, str(p.name), 15, 700, HudStyle.CYAN).mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var go := HudStyle.button(v, "Ride", 18, func() -> void:
		App.workout = workout
		if simulator:
			Devices.use_simulated_devices()
		App.go_to("res://ui/screens/ride_screen.tscn"))
	go.custom_minimum_size.y = 44
	HudStyle.style_button(go, "primary")
	replace_content(v)


func _mark_scene_cards(cards: Dictionary) -> void:
	for id in cards:
		var card: PanelContainer = cards[id]
		var chosen: bool = id == App.scene_preset
		card.add_theme_stylebox_override("panel", HudStyle.flat(HudStyle.CARD, HudStyle.RADIUS, 10, 8,
			HudStyle.CYAN if chosen else HudStyle.BORDER))


func _build_content(v: VBoxContainer) -> void:
	var w := workout
	var ftp := App.ftp
	header(v, w.name)

	var graph := WorkoutGraph.new()
	graph.custom_minimum_size.y = 130
	graph.show_marker = false
	graph.set_workout(w)
	v.add_child(graph)

	var est := WorkoutSummary.estimates(w, ftp)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 0)
	v.add_child(grid)
	_stat(grid, WorkoutSummary.duration(w.total_duration()), "duration")
	_stat(grid, "%d" % int(round(est.kj)), "kJ at %d W FTP" % ftp)
	_stat(grid, "%d" % int(round(est.tss)), "TSS")
	_stat(grid, "%.2f" % float(est.intensity_factor), "intensity")
	var kcal := RideMetrics.kcal_from_kj(float(est.kj))
	_stat(grid, "%d" % int(round(kcal)), "kcal")
	_stat(grid, "%.1f" % RideMetrics.pizza_slices(kcal), "slices of pizza")

	var gap := Control.new()
	gap.custom_minimum_size.y = 10   # breathing room between the stats and the columns below
	v.add_child(gap)
	# Two columns: the coach's description (two thirds) beside the block list (one third).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	scroll.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	if w.description != "":
		_coach_note(left, w.description)
	if w.author != "":
		HudStyle.label(left, "by %s" % w.author, 13, 500, HudStyle.TEXT_DIM)
	# The block rows stand on their own: no title, no container.
	right.add_theme_constant_override("separation", 4)
	for r in WorkoutSummary.rows(w, ftp):
		HudStyle.block_row(right, r, 24, 16, Color(0.20, 0.23, 0.31, 0.9))

	_devices_l = HudStyle.label(v, "", 13, 500, HudStyle.TEXT_DIM)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	_ride = HudStyle.button(bar, "Ride", 18, _start.bind(false), "primary")
	_ride.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ride.clip_text = true
	_ride.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ride.custom_minimum_size.y = 44
	HudStyle.button(bar, "Simulator", 15, _start.bind(true), "secondary")


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
	var desc := HudStyle.label(bubble, text, 26, 500)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _stat(parent: Control, value: String, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var val := HudStyle.label(h, value, 22, 900)
	var u := HudStyle.label(h, unit, 13, 700, HudStyle.TEXT_DIM)
	HudStyle.share_baseline(h, val, u)
