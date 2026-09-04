class_name Lightbox
extends Control
## Full-screen viewer for ride screenshots: ink scrim, the image fitted to the
## window, arrows to step through, click anywhere or Esc to close.

var _paths: Array[String] = []
var _index := 0
var _image: TextureRect
var _caption: Label


## Open on top of everything in the current scene.
static func open(paths: Array[String], index: int) -> void:
	var root := Engine.get_main_loop().root as Window
	var host: Node = root.get_child(root.get_child_count() - 1)
	var lb := Lightbox.new()
	lb._paths = paths
	lb._index = clampi(index, 0, paths.size() - 1)
	host.add_child(lb)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Color(HudStyle.INK, 0.92)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)
	_image = TextureRect.new()
	_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_image)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	v.add_child(bar)
	HudStyle.icon_button(bar, "chevron-left", func() -> void: _step(-1), 22)
	_caption = HudStyle.label(bar, "", 14, 500, HudStyle.TEXT_DIM)
	_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	HudStyle.icon_button(bar, "chevron-right", func() -> void: _step(1), 22)
	var close := HudStyle.icon_button(self, "close", queue_free, 22)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -60.0
	close.offset_right = -16.0
	close.offset_top = 16.0
	close.offset_bottom = 60.0
	_show()
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			queue_free())


func _step(d: int) -> void:
	_index = wrapi(_index + d, 0, _paths.size())
	_show()


func _show() -> void:
	if _paths.is_empty():
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(_paths[_index]))
	if img:
		_image.texture = ImageTexture.create_from_image(img)
	_caption.text = "%s   ·   %d / %d" % [_paths[_index].get_file(), _index + 1, _paths.size()]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ESCAPE, KEY_SPACE: queue_free()
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
	get_viewport().set_input_as_handled()
