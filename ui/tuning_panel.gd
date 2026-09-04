class_name TuningPanel
extends PanelContainer
## Sliders for App.TUNING_SPEC. Writes App.scene_tuning, saves, and applies to
## a RideScene when one is attached.

signal changed

var scene: RideScene
var _sliders: Dictionary = {}
var _values: Dictionary = {}


## Set before adding to the tree: no margins, title or background, the host
## provides those (the Settings sheet puts it in a card with its own Reset).
var embedded := false


func _ready() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 0 if embedded else 10)
	add_child(m)
	if embedded:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	if not embedded:
		var head := HBoxContainer.new()
		v.add_child(head)
		HudStyle.label(head, "Scene tuning", 16, 700).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudStyle.button(head, "Reset", 12, reset)
	for row in App.TUNING_SPEC:
		var key: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		v.add_child(line)
		var l := HudStyle.label(line, row[1], 13, 500, HudStyle.TEXT_DIM)
		l.custom_minimum_size.x = 170
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var s := HudStyle.slider(line)
		s.min_value = row[2]
		s.max_value = row[3]
		s.step = row[4]
		s.value = App.scene_tuning[key]
		s.custom_minimum_size.x = 160
		s.value_changed.connect(_on_value.bind(key))
		var val := HudStyle.label(line, "", 13, 700)
		val.custom_minimum_size.x = 52
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_sliders[key] = s
		_values[key] = val
		_refresh_value(key)


func _on_value(v: float, key: String) -> void:
	App.scene_tuning[key] = v
	_refresh_value(key)
	App.save_settings()
	if scene:
		scene.apply_tuning(App.scene_tuning)
	changed.emit()


func _refresh_value(key: String) -> void:
	var v: float = App.scene_tuning[key]
	_values[key].text = ("%.4f" % v) if v < 0.05 and v != 0.0 else (("%d" % int(v)) if is_equal_approx(v, round(v)) and v >= 8.0 else "%.2f" % v)


func reset() -> void:
	App.reset_tuning()
	for key in _sliders:
		_sliders[key].set_value_no_signal(App.scene_tuning[key])
		_refresh_value(key)
	if scene:
		scene.apply_tuning(App.scene_tuning)
	changed.emit()
