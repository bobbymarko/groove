class_name CoachDialog
extends PanelContainer
## Coach notes as a centred dialog box with a portrait on the left, the way
## characters talk in Star Fox: text types in, holds, then fades. Uses
## res://assets/coach.png as the portrait when present, else a drawn placeholder.

const PORTRAIT_PATH := "res://assets/coach.png"
const CHARS_PER_SECOND := 45.0
const HOLD_SECONDS := 6.0
const FADE_SECONDS := 0.6

var label: Label
var _portrait: Control
var _time := 0.0
var _hold_until := 0.0
var _hold_forever := false
var _full_text := ""


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11, 0.78)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.border_width_bottom = 3
	sb.border_width_top = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_color = Color(0.93, 0.93, 0.96, 0.85)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(880, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	add_child(h)
	if ResourceLoader.exists(PORTRAIT_PATH):
		var tr := TextureRect.new()
		tr.texture = load(PORTRAIT_PATH)
		tr.custom_minimum_size = Vector2(150, 150)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait = tr
	else:
		_portrait = CoachPortrait.new()
		_portrait.custom_minimum_size = Vector2(150, 150)
	h.add_child(_portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var who := HudStyle.label(v, "COACH", 16, 900, Color(1.0, 0.85, 0.3))
	who.add_theme_constant_override("outline_size", 0)
	label = HudStyle.label(v, "", 30, 700)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	modulate.a = 0.0
	visible = false


## Show a note. hold_seconds <= 0 keeps it on screen.
func say(text: String, hold_seconds: float = HOLD_SECONDS) -> void:
	_full_text = text
	label.text = text
	label.visible_characters = 0
	_time = 0.0
	_hold_forever = hold_seconds <= 0.0
	_hold_until = text.length() / CHARS_PER_SECOND + hold_seconds
	visible = true
	modulate.a = 1.0


func dismiss() -> void:
	_hold_forever = false
	_hold_until = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	label.visible_characters = mini(int(_time * CHARS_PER_SECOND), _full_text.length())
	if _hold_forever or _time < _hold_until:
		return
	modulate.a = move_toward(modulate.a, 0.0, delta / FADE_SECONDS)
	if modulate.a <= 0.001:
		visible = false


## Placeholder portrait drawn from shapes: helmet, face, goggles. Replace by
## dropping a square PNG at res://assets/coach.png.
class CoachPortrait:
	extends Control

	func _draw() -> void:
		var s := size
		var c := s * 0.5
		var r := minf(s.x, s.y) * 0.5
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.12, 0.14, 0.2, 0.9))
		# Face
		draw_circle(c + Vector2(0, r * 0.12), r * 0.62, Palette.RIDER_SKIN)
		# Helmet: dome plus a brim
		draw_circle(c - Vector2(0, r * 0.22), r * 0.68, Palette.RIDER_RED)
		draw_rect(Rect2(c.x - r * 0.72, c.y - r * 0.02, r * 1.44, r * 0.16), Palette.RIDER_RED)
		draw_rect(Rect2(c.x - r * 0.72, c.y + r * 0.08, r * 1.44, r * 0.09), Color(0.55, 0.13, 0.16))
		# Goggles
		draw_rect(Rect2(c.x - r * 0.62, c.y + r * 0.2, r * 1.24, r * 0.34), Color(0.1, 0.11, 0.16))
		draw_rect(Rect2(c.x - r * 0.55, c.y + r * 0.25, r * 0.5, r * 0.22), Color(0.45, 0.75, 0.95))
		draw_rect(Rect2(c.x + r * 0.05, c.y + r * 0.25, r * 0.5, r * 0.22), Color(0.45, 0.75, 0.95))
		# Mouth
		draw_rect(Rect2(c.x - r * 0.18, c.y + r * 0.72, r * 0.36, r * 0.07), Color(0.45, 0.25, 0.22))
