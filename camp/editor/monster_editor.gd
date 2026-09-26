class_name MonsterEditor
extends Control
## Build your rider: swap parts, push proportions into caricature, pick
## colours. The monster spins on a turntable at dusk, on its bike or standing.

const PARTS := {
	"body": [["round", "Round"], ["square", "Square"], ["bean", "Bean"]],
	"head": [["", "None"], ["screen", "Screen"], ["skull", "Skull"]],
	"eyes": [["cyclops", "Cyclops"], ["squint", "Squint"], ["screen", "Screen"], ["shades", "Shades"], ["", "None"]],
	"mouth": [["teeth", "Teeth"], ["smirk", "Smirk"], ["grill", "Grill"], ["", "None"]],
	"hands": [["mitt", "Mitts"], ["claw", "Claws"]],
	"feet": [["shoe", "Kicks"], ["hoof", "Hooves"]],
}
const PART_TITLES := {"body": "Body", "head": "Head", "eyes": "Eyes", "mouth": "Mouth", "hands": "Hands", "feet": "Feet"}
const EXTRAS := [["horns", "Horns"], ["spikes", "Spikes"], ["antenna", "Antenna"], ["cap_back", "Cap"],
	["beanie", "Beanie"], ["hat_pioneer", "Hat"], ["backpack", "Pack"], ["beard", "Beard"], ["pipe", "Pipe"]]
const HATS := ["cap_back", "beanie", "hat_pioneer"]
const SLIDERS := [["girth", "Girth", 0.7, 1.5], ["height", "Height", 0.7, 1.6], ["head", "Head", 0.7, 1.5],
	["eye", "Eyes", 0.6, 1.6], ["horn", "Horns", 0.6, 2.2], ["arm", "Arms", 0.4, 0.95],
	["leg", "Legs", 0.45, 1.0], ["limb", "Thickness", 0.03, 0.11], ["hand", "Hands", 0.7, 1.6],
	["foot", "Feet", 0.7, 1.6]]
const COLOUR_ROLES := [["primary", "Fur"], ["secondary", "Belly"], ["limb", "Limbs"], ["accent", "Gear"],
	["cap", "Hat"], ["cloth", "Pack"], ["frame", "Bike"]]
const SWATCHES := ["7443c4", "d6442f", "2f8f9a", "3e8f4b", "d69a2a", "8795a6", "2b2e36", "8a5a3c",
	"e05a8a", "f2e8d8", "1d2f5a", "ef6a01"]
const PANEL_W := 620.0

var recipe: Dictionary
var _on_bike := true
var _subject: Node3D
var _stage: Node3D
var _turn := -0.95          # start on a three-quarter front view
var _dragging := false
var _panel_box: VBoxContainer
var _name: LineEdit
var _status: Label


func _ready() -> void:
	recipe = CampSave.load_rider()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = HudStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 0)
	add_child(h)
	_build_stage(h)
	_build_panel(h)
	_rebuild()


func _process(dt: float) -> void:
	if not _dragging:
		_turn += dt * 0.25
	if _subject:
		_subject.rotation.y = _turn
		if _subject is MonsterRider:
			(_subject as MonsterRider).advance(dt)
		elif _subject is MonsterStand:
			(_subject as MonsterStand).advance(dt)


# ------------------------------------------------------------------ stage

func _build_stage(parent: Control) -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(vp)
	_stage = Node3D.new()
	vp.add_child(_stage)
	CampWorld.dusk(_stage, false)
	var plinth := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.25
	cyl.bottom_radius = 1.35
	cyl.height = 0.2
	cyl.radial_segments = 10
	cyl.rings = 1
	plinth.mesh = cyl
	plinth.position.y = -0.1
	plinth.material_override = CampLook.material(Color("5a4a6e"))
	_stage.add_child(plinth)
	var cam := Camera3D.new()
	cam.fov = 30
	_stage.add_child(cam)
	cam.position = Vector3(0.0, 1.9, 6.4)
	cam.look_at(Vector3(0.0, 0.62, 0))
	# Drag to spin.
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
		elif e is InputEventMouseMotion and _dragging:
			_turn += e.relative.x * 0.01)
	# Title and view toggle over the stage.
	var over := VBoxContainer.new()
	over.position = Vector2(36, 28)
	over.add_theme_constant_override("separation", 10)
	box.add_child(over)
	HudStyle.label(over, "MONSTER BUILDER", 48, 700)
	HudStyle.label(over, "Same parts. Endless riders.", 22, 500, HudStyle.TEXT_DIM)
	HudStyle.segmented(over, ["On the bike", "Standing"], 0, func(i: int) -> void:
		_on_bike = i == 0
		_rebuild(), 22)


func _rebuild() -> void:
	if _subject:
		_subject.free()
	if _on_bike:
		var r := MonsterRider.new()
		r.recipe = recipe
		r.face_turn = 0.0
		r.position = Vector3(-0.05, 0, 0)
		_stage.add_child(r)
		_subject = r
	else:
		var s := MonsterStand.new()
		s.recipe = recipe
		_stage.add_child(s)
		_subject = s
	_subject.rotation.y = _turn


# ------------------------------------------------------------------ panel

func _build_panel(parent: Control) -> void:
	var side := PanelContainer.new()
	side.custom_minimum_size.x = PANEL_W
	side.add_theme_stylebox_override("panel", HudStyle.flat(HudStyle.NAVY, 0, 24, 20))
	parent.add_child(side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	side.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_box.add_theme_constant_override("separation", 18)
	scroll.add_child(_panel_box)
	_fill_panel()
	# Pinned footer: name, save.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	_name = HudStyle.input(foot, str(recipe.get("name", "")), "Name your rider", false, 22)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(t: String) -> void: recipe["name"] = t)
	var save := HudStyle.button(foot, "Save rider", 22, _save, "primary")
	save.custom_minimum_size.y = 48
	_status = HudStyle.label(v, "", 22, 500, HudStyle.TEXT_DIM)


func _fill_panel() -> void:
	for c in _panel_box.get_children():
		c.free()
	# Start points.
	var top := _group("Start from")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	top.add_child(chips)
	for preset in MonsterPresets.all():
		var p: Dictionary = preset
		HudStyle.button(chips, str(p.name), 22, func() -> void: _use(p))
	HudStyle.button(chips, "Surprise me", 22, _randomize, "secondary")
	for key in ["body", "head", "eyes", "mouth", "hands", "feet"]:
		var g := _group(PART_TITLES[key])
		var flow := _flow(g)
		for opt in PARTS[key]:
			var value: String = opt[0]
			var on: bool = str(recipe.get(key, "")) == value
			_chip(flow, opt[1], on, func() -> void: _set_part(key, value))
		if key == "body":
			_chip(flow, "Fur", bool(recipe.get("fur", false)), func() -> void:
				recipe["fur"] = not bool(recipe.get("fur", false))
				_changed(true))
	var ex := _group("Extras")
	var ef := _flow(ex)
	var extras: Array = recipe.get("extras", [])
	for opt in EXTRAS:
		var id: String = opt[0]
		_chip(ef, opt[1], extras.has(id), func() -> void: _toggle_extra(id))
	var sz := _group("Proportions")
	var sizes: Dictionary = recipe.get("size", {})
	for s in SLIDERS:
		var key: String = s[0]
		var row := HudStyle.row(sz, s[1], 150)
		var sl := HudStyle.slider(row)
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = 0.01
		sl.value = float(sizes.get(key, MonsterPresets.SIZE_DEFAULTS[key]))
		sl.value_changed.connect(func(x: float) -> void:
			var d: Dictionary = recipe.get("size", {})
			d[key] = x
			recipe["size"] = d
			_changed(false))
	var col := _group("Colours")
	for role in COLOUR_ROLES:
		var key: String = role[0]
		var row := HudStyle.row(col, role[1], 110)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(flow)
		var current := _colour(key)
		for hex in SWATCHES:
			var c := Color(hex)
			var sw := Button.new()
			sw.custom_minimum_size = Vector2(30, 30)
			sw.focus_mode = Control.FOCUS_NONE
			var chosen := current.is_equal_approx(c)
			var sb := HudStyle.flat(c, 3, 0, 0, HudStyle.ICE if chosen else Color(0, 0, 0, 0))
			if chosen:
				sb.set_border_width_all(3)
			sw.add_theme_stylebox_override("normal", sb)
			sw.add_theme_stylebox_override("hover", HudStyle.flat(c.lightened(0.15), 3, 0, 0, HudStyle.ICE))
			sw.add_theme_stylebox_override("pressed", sb)
			sw.pressed.connect(func() -> void: _set_colour(key, c))
			flow.add_child(sw)


func _group(title: String) -> VBoxContainer:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 8)
	_panel_box.add_child(g)
	HudStyle.section_label(g, title.to_upper(), 22)
	return g


func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	parent.add_child(f)
	return f


func _chip(parent: Control, text: String, on: bool, cb: Callable) -> Button:
	return HudStyle.button(parent, text, 22, cb, "primary" if on else "ghost")


# ------------------------------------------------------------------ edits

func _colour(key: String) -> Color:
	if key == "frame":
		return recipe.get("bike", {}).get("frame", CampLook.ROLES.frame)
	return recipe.get("colours", {}).get(key, CampLook.ROLES.get(key, Color.WHITE))


func _set_colour(key: String, c: Color) -> void:
	if key == "frame":
		var b: Dictionary = recipe.get("bike", {})
		b["frame"] = c
		recipe["bike"] = b
	else:
		var cs: Dictionary = recipe.get("colours", {})
		cs[key] = c
		recipe["colours"] = cs
	_changed(true)


func _set_part(key: String, value: String) -> void:
	recipe[key] = value
	# A skull has its own face; a screen head wants screen eyes.
	if key == "head" and value == "skull":
		recipe["eyes"] = ""
		recipe["mouth"] = ""
	elif key == "head" and value == "screen" and str(recipe.get("eyes", "")) in ["cyclops", "squint", ""]:
		recipe["eyes"] = "screen"
		recipe["mouth"] = "grill"
	_changed(true)


func _toggle_extra(id: String) -> void:
	var extras: Array = (recipe.get("extras", []) as Array).duplicate()
	if extras.has(id):
		extras.erase(id)
	else:
		if id in HATS:           # one hat at a time
			for h in HATS:
				extras.erase(h)
		extras.append(id)
	recipe["extras"] = extras
	_changed(true)


func _use(preset: Dictionary) -> void:
	recipe = preset.duplicate(true)
	if _name:
		_name.text = str(recipe.get("name", ""))
	_changed(true)


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pick := func(key: String) -> String:
		var opts: Array = PARTS[key]
		return str(opts[rng.randi() % opts.size()][0])
	var r := {"name": "", "body": pick.call("body"), "fur": rng.randf() < 0.45, "head": "",
		"hands": pick.call("hands"), "feet": "shoe" if rng.randf() < 0.8 else "hoof"}
	var head_roll := rng.randf()
	if head_roll < 0.15:
		r["head"] = "screen"
		r["eyes"] = "screen"
		r["mouth"] = "grill"
	elif head_roll < 0.27:
		r["head"] = "skull"
		r["eyes"] = ""
		r["mouth"] = ""
	else:
		r["eyes"] = ["cyclops", "squint", "squint", "shades"][rng.randi() % 4]
		r["mouth"] = ["teeth", "teeth", "smirk", ""][rng.randi() % 4]
	var extras := []
	if rng.randf() < 0.45:
		extras.append("horns")
	if rng.randf() < 0.25 and r.head == "":
		extras.append("spikes")
	if rng.randf() < 0.6:
		extras.append(HATS[rng.randi() % HATS.size()])
	if rng.randf() < 0.35:
		extras.append("backpack")
	r["extras"] = extras
	var sizes := {}
	for s in SLIDERS:
		var lo: float = s[2]
		var hi: float = s[3]
		# Lean toward the middle, with the odd extreme for caricature.
		var t := rng.randf()
		t = 0.5 + (t - 0.5) * (1.0 if rng.randf() < 0.25 else 0.55)
		sizes[s[0]] = snappedf(lerpf(lo, hi, t), 0.01)
	r["size"] = sizes
	var main := Color(SWATCHES[rng.randi() % SWATCHES.size()])
	var gear := Color(SWATCHES[rng.randi() % SWATCHES.size()])
	r["colours"] = {"primary": main, "secondary": main.darkened(0.3) if rng.randf() < 0.5 else main.lightened(0.25),
		"limb": main.darkened(0.08), "accent": gear, "cap": Color(SWATCHES[rng.randi() % SWATCHES.size()]),
		"cloth": Color("1d2f5a"), "dark": Color("222326")}
	r["bike"] = {"frame": Color(SWATCHES[rng.randi() % SWATCHES.size()]), "accent": Color("f4f5f5")}
	recipe = r
	if _name:
		_name.text = ""
	_changed(true)


## Parts and colours re-render the panel (chip states); sliders only rebuild
## the monster so dragging stays smooth.
func _changed(refresh_panel: bool) -> void:
	if _subject is MonsterRider:
		(_subject as MonsterRider).recipe = recipe
		(_subject as MonsterRider).build()
	elif _subject is MonsterStand:
		(_subject as MonsterStand).recipe = recipe
		(_subject as MonsterStand).rebuild()
	if refresh_panel:
		_fill_panel.call_deferred()
	if _status:
		_status.text = ""


func _save() -> void:
	var err := CampSave.save_rider(recipe)
	_status.text = "Saved." if err == OK else "Could not save: %s" % error_string(err)
