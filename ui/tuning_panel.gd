class_name TuningPanel
extends PanelContainer
## Sliders for App.TUNING_SPEC. Writes App.scene_tuning, saves, and applies to
## a RideScene when one is attached.

signal changed

var scene: RideScene
var _sliders: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "Scene tuning"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(_reset)
	head.add_child(reset)
	for row in App.TUNING_SPEC:
		var key: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		v.add_child(line)
		var l := Label.new()
		l.text = row[1]
		l.custom_minimum_size.x = 180
		l.add_theme_font_size_override("font_size", 13)
		line.add_child(l)
		var s := HSlider.new()
		s.min_value = row[2]
		s.max_value = row[3]
		s.step = row[4]
		s.value = App.scene_tuning[key]
		s.custom_minimum_size.x = 220
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(_on_value.bind(key))
		line.add_child(s)
		var val := Label.new()
		val.custom_minimum_size.x = 56
		val.add_theme_font_size_override("font_size", 13)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(val)
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


func _reset() -> void:
	App.reset_tuning()
	for key in _sliders:
		_sliders[key].set_value_no_signal(App.scene_tuning[key])
		_refresh_value(key)
	if scene:
		scene.apply_tuning(App.scene_tuning)
	changed.emit()
