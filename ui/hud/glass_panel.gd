class_name GlassPanel
extends PanelContainer
## A HudStyle panel in glass mode: draws itself with glass.gdshader (children
## keep their own materials) and lays out its content with even padding.

const SHADER := preload("res://ui/hud/glass.gdshader")

var _mat := ShaderMaterial.new()


func _init(tint := Color(0.06, 0.09, 0.15, 0.38), radius := 22.0, pad := 16) -> void:
	_mat.shader = SHADER
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("radius", radius)
	material = _mat
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.75
	sb.content_margin_bottom = pad * 0.75
	add_theme_stylebox_override("panel", sb)
	resized.connect(_fit)


func set_tint(c: Color) -> void:
	_mat.set_shader_parameter("tint", c)


func _fit() -> void:
	_mat.set_shader_parameter("rect_size", size)
	queue_redraw()


func _draw() -> void:
	if material == _mat:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
