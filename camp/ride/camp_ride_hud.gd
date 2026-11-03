class_name CampRideHud
extends CanvasLayer
## The Camp ride HUD: workout strip, basket, live numbers, the band pill,
## coach notes, and the start and finish cards. All text in CampUI.

signal action(id: String)        ## "start", "again", "summary", "camp"

const FIND_COLOURS := {"berry": Color("c0184a"), "flower": Color("f0709a"),
	"critter": Color("9c7a5c"), "honey": Color("ffb21e")}
const FIND_NAMES := {"berry": "Berries", "flower": "Flowers", "critter": "Critters", "honey": "Honey"}

var graph: WorkoutGraph
var _counts: Dictionary = {}
var _value: Label
var _watts: Label
var _target: Label
var _cadence: Label
var _hr: Label
var _clock: Label
var _pill: PanelContainer
var _pill_label: Label
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_until := 0.0
var _card: Control
var _hint: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Workout strip across the top.
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", CampUI.box(Color(HudStyle.INK, 0.55), CampUI.SOFT, 14, 10))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 18
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	graph = WorkoutGraph.new()
	graph.custom_minimum_size.y = 74
	graph.show_background = false
	top.add_child(graph)
	# Basket, top left under the strip.
	var basket_card := PanelContainer.new()
	basket_card.add_theme_stylebox_override("panel", CampUI.box(Color(HudStyle.INK, 0.6), 18, 18, 14))
	basket_card.position = Vector2(24, 124)
	root.add_child(basket_card)
	var basket := VBoxContainer.new()
	basket.add_theme_constant_override("separation", 4)
	basket_card.add_child(basket)
	for k in ["berry", "flower", "critter", "honey"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		basket.add_child(row)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", CampUI.box(FIND_COLOURS[k], CampUI.PILL, 0, 0))
		row.add_child(dot)
		_counts[k] = CampUI.label(row, "0", 26, 700)
		CampUI.label(row, FIND_NAMES[k], CampUI.BODY, 500, HudStyle.TEXT_DIM)
	_value = CampUI.label(basket, "Worth 0 coins", CampUI.BODY, 600, HudStyle.YELLOW)
	# Live numbers, top right.
	var nums_card := PanelContainer.new()
	nums_card.add_theme_stylebox_override("panel", CampUI.box(Color(HudStyle.INK, 0.6), 18, 20, 12))
	nums_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nums_card.offset_left = -300
	nums_card.offset_right = -24
	nums_card.offset_top = 124
	nums_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(nums_card)
	var nums := VBoxContainer.new()
	nums.add_theme_constant_override("separation", 0)
	nums_card.add_child(nums)
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_END
	wrow.add_theme_constant_override("separation", 8)
	nums.add_child(wrow)
	_watts = CampUI.label(wrow, "0", 56, 700)
	_target = CampUI.label(wrow, "/ 0 W", 22, 600, HudStyle.TEXT_DIM)
	_target.size_flags_vertical = Control.SIZE_SHRINK_END
	for l in [_watts, _target]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cadence = _right(nums, "— rpm")
	_hr = _right(nums, "— bpm")
	_clock = _right(nums, "")
	# Band pill, centred under the strip.
	_pill = PanelContainer.new()
	_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pill.offset_left = -120
	_pill.offset_right = 120
	_pill.offset_top = 128
	root.add_child(_pill)
	_pill_label = CampUI.label(_pill, "", 22, 700, HudStyle.INK_TEXT)
	_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Coach bubble, bottom centre.
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", CampUI.box(Color(HudStyle.INK, 0.8), 22, 26, 14))
	_bubble.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bubble.offset_left = -380
	_bubble.offset_right = 380
	_bubble.offset_top = -150
	_bubble.offset_bottom = -64
	_bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bubble.visible = false
	root.add_child(_bubble)
	_bubble_label = CampUI.label(_bubble, "", 24, 500)
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Key hint, bottom left.
	_hint = CampUI.label(root, "", CampUI.SMALL, 500, Color(1, 1, 1, 0.55))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 30
	_hint.offset_top = -44


func _right(parent: Control, t: String) -> Label:
	var l := CampUI.label(parent, t, 22, 600)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _process(_dt: float) -> void:
	if _bubble.visible and Time.get_ticks_msec() / 1000.0 > _bubble_until:
		_bubble.visible = false


func set_hint(t: String) -> void:
	_hint.text = t


func set_numbers(watts: float, target: float, cadence: int, bpm: int, segment_left: float) -> void:
	_watts.text = "%d" % int(round(watts))
	_target.text = "/ %d W" % int(round(target)) if target > 0 else "free ride"
	_cadence.text = "%d rpm" % cadence if cadence > 0 else "— rpm"
	_hr.text = "%d bpm" % bpm if bpm > 0 else "— bpm"
	_clock.text = "%s left in block" % WorkoutSummary.duration(maxf(segment_left, 0.0))


func set_band(state: String) -> void:
	_pill.visible = state != "done"
	var c: Color
	var t: String
	match state:
		"in":
			c = HudStyle.GREEN
			t = "In the zone"
		"high":
			c = HudStyle.YELLOW
			t = "Over target"
		"low":
			c = HudStyle.ORANGE
			t = "Push a little"
		"paused":
			c = HudStyle.ICE
			t = "Paused"
		_:
			c = HudStyle.ICE
			t = "Ready"
	_pill.add_theme_stylebox_override("panel", CampUI.box(c, CampUI.PILL, 18, 7))
	_pill_label.text = t


func set_basket(basket: Dictionary, value: int) -> void:
	for k in _counts:
		(_counts[k] as Label).text = str(int(basket.get(k, 0)))
	_value.text = "Worth %d coin%s" % [value, "" if value == 1 else "s"]


func say(message: String) -> void:
	_bubble_label.text = message
	_bubble.visible = true
	_bubble_until = Time.get_ticks_msec() / 1000.0 + 8.0


# ------------------------------------------------------------------ cards

func show_start(workout_name: String, detail: String) -> void:
	_card = _make_card()
	var v: VBoxContainer = _card.get_child(0)
	CampUI.label(v, workout_name, 36, 700)
	var d := CampUI.label(v, detail, CampUI.BODY, 500, HudStyle.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var go := CampUI.button(v, "Head out", func() -> void: action.emit("start"), "primary", 22)
	go.custom_minimum_size.y = 52
	CampUI.label(v, "or press Space", CampUI.SMALL, 500, HudStyle.TEXT_DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func hide_card() -> void:
	if _card:
		_card.queue_free()
		_card = null


func show_tally(basket: Dictionary, haul: int, tss: float, coins: int, recorded: bool) -> void:
	hide_card()
	_card = _make_card()
	var v: VBoxContainer = _card.get_child(0)
	CampUI.label(v, "Back to camp", 36, 700)
	CampUI.label(v, "The trader weighs your basket.", CampUI.BODY, 500, HudStyle.TEXT_DIM)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for k in ["berry", "flower", "critter", "honey"]:
		var name_l := CampUI.label(grid, FIND_NAMES[k], CampUI.BODY, 500)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		CampUI.label(grid, "%d" % int(basket.get(k, 0)), CampUI.BODY, 600).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	CampUI.label(grid, "Basket value, ripeness and bias included", CampUI.BODY, 500, HudStyle.TEXT_DIM)
	CampUI.label(grid, "%d" % haul, CampUI.BODY, 600).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	CampUI.label(grid, "Training load, %d TSS" % int(round(tss)), CampUI.BODY, 500, HudStyle.TEXT_DIM)
	CampUI.label(grid, "%d" % (coins - haul), CampUI.BODY, 600).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var total := HBoxContainer.new()
	v.add_child(total)
	CampUI.label(total, "Paid", 28, 700).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CampUI.label(total, "%d coins" % coins, 28, 700, HudStyle.YELLOW)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	if recorded:
		CampUI.button(bar, "Ride summary", func() -> void: action.emit("summary"), "secondary")
	CampUI.button(bar, "Ride again", func() -> void: action.emit("again"), "ghost")
	var cb := CampUI.button(bar, "Back to camp", func() -> void: action.emit("camp"), "primary")
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _make_card() -> Control:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", CampUI.box(Color(HudStyle.NAVY, 0.94), 24, 32, 28))
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -290
	c.offset_right = 290
	c.offset_top = -230
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	c.add_child(v)
	add_child(c)
	return c
