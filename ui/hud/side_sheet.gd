class_name SideSheet
extends Control
## A panel that slides in from the right over the current screen, with a scrim
## behind it that dismisses on click. Subclasses or callers put content in it
## with show_content().

signal closed

var width := 520.0
var _panel: PanelContainer
var _holder: Control         # plain Control: children cannot widen the sheet, overflow is clipped
var _scrim: ColorRect
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.45)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_scrim)
	_panel = HudStyle.panel(self, Color(0.11, 0.12, 0.17, 0.98), 0, 22)
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.custom_minimum_size.x = width
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_holder = Control.new()
	_holder.clip_contents = true
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_holder)
	visible = false


func is_open() -> bool:
	return visible


## Replace the sheet's content and slide it in.
func show_content(content: Control) -> void:
	_mount(content)
	visible = true
	_scrim.modulate.a = 0.0
	_panel.offset_left = 0.0
	_panel.offset_right = width
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_left", -width, 0.25)
	_tween.tween_property(_panel, "offset_right", 0.0, 0.25)
	_tween.tween_property(_scrim, "modulate:a", 1.0, 0.25)


func close() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_left", 0.0, 0.2)
	_tween.tween_property(_panel, "offset_right", width, 0.2)
	_tween.tween_property(_scrim, "modulate:a", 0.0, 0.2)
	_tween.chain().tween_callback(func() -> void: visible = false; closed.emit())


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()


## Swap the content without the slide-in (navigating within the sheet).
func replace_content(content: Control) -> void:
	_mount(content)
	visible = true


func _mount(content: Control) -> void:
	for c in _holder.get_children():
		c.queue_free()
	_holder.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Standard header row: optional back arrow, title and a close button.
func header(parent: Control, title: String, on_back := Callable()) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	parent.add_child(head)
	if on_back.is_valid():
		HudStyle.button(head, "←", 16, on_back).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := HudStyle.label(head, title, 24, 900)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.button(head, "✕", 16, close)
