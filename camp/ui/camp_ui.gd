class_name CampUI
extends RefCounted
## Camp's interface style: a clean geometric sans on Groove's colour tokens.
## Groove keeps its pixel faces (HudStyle); Camp's text goes through here.
##
## The bundled font is Outfit, one variable file; weights are FontVariation
## axes. The system faces are only a fallback if the file goes missing.

const FONT_PATH := "res://assets/fonts/Outfit-Variable.ttf"
const FALLBACK_FACES := ["Avenir Next", "Futura", "Helvetica Neue"]

const BODY := 18
const SMALL := 15
const TITLE := 44
## Smooth, generous corners (Groove uses stepped pixel corners instead).
## PILL is clamped by Godot to half the height, so buttons become capsules.
const PILL := 999
const SOFT := 10

static var _base: Font
static var _weights: Dictionary = {}


static func font(weight := 500) -> Font:
	if _weights.has(weight):
		return _weights[weight]
	if _base == null:
		if ResourceLoader.exists(FONT_PATH):
			_base = load(FONT_PATH)
		else:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(FALLBACK_FACES)
			_base = sf
	var f: Font
	if _base is SystemFont:
		var sf := (_base as SystemFont).duplicate() as SystemFont
		sf.font_weight = weight
		f = sf
	else:
		var v := FontVariation.new()
		v.base_font = _base
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
		f = v
	_weights[weight] = f
	return f


## A smooth, anti-aliased rounded box.
static func box(color: Color, radius := PILL, pad_x := 16, pad_y := 8, border := Color(0, 0, 0, 0), border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 12
	sb.anti_aliasing = true
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	if border.a > 0.0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	return sb


## Pill buttons in Groove's three kinds: ghost, primary (filled), secondary (outlined).
static func style_button(b: Button, kind := "ghost") -> void:
	var c := HudStyle.CYAN
	var sets := {}
	var text := HudStyle.TEXT
	match kind:
		"primary":
			sets = {"normal": box(c), "hover": box(c.lightened(0.15)), "pressed": box(c.darkened(0.2)),
				"disabled": box(Color(c, 0.3))}
			text = HudStyle.INK_TEXT
		"secondary":
			sets = {"normal": box(Color(0, 0, 0, 0), PILL, 16, 8, c, 2), "hover": box(Color(c, 0.15), PILL, 16, 8, c, 2),
				"pressed": box(Color(c, 0.3), PILL, 16, 8, c, 2), "disabled": box(Color(0, 0, 0, 0), PILL, 16, 8, Color(c, 0.3), 2)}
			text = c
		_:
			sets = {"normal": box(HudStyle.BUTTON, PILL, 16, 8, HudStyle.BORDER),
				"hover": box(HudStyle.BUTTON_HOVER, PILL, 16, 8, Color(c, 0.6)),
				"pressed": box(HudStyle.BUTTON_PRESSED, PILL, 16, 8, c),
				"disabled": box(Color(HudStyle.BUTTON, 0.35), PILL, 16, 8, Color(HudStyle.BORDER, 0.2))}
	for k in sets:
		b.add_theme_stylebox_override(k, sets[k])
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, text)
	b.add_theme_color_override("font_disabled_color", Color(text, 0.4))


static func label(parent: Control, text: String, size := BODY, weight := 500, color := HudStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## Small caps-style group heading.
static func heading(parent: Control, text: String) -> Label:
	var l := label(parent, text.to_upper(), SMALL, 700, HudStyle.CYAN)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func button(parent: Control, text: String, on_pressed: Callable, kind := "ghost", size := BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(600))
	b.add_theme_font_size_override("font_size", size)
	style_button(b, kind)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


static func row(parent: Control, caption: String, caption_width := 120) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := label(h, caption, BODY, 500, HudStyle.TEXT_DIM)
	l.custom_minimum_size.x = caption_width
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return h


static func input(parent: Control, text: String, placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", font(500))
	e.add_theme_font_size_override("font_size", BODY)
	e.add_theme_color_override("font_color", HudStyle.TEXT)
	e.add_theme_color_override("font_placeholder_color", HudStyle.TEXT_DIM)
	e.add_theme_stylebox_override("normal", box(HudStyle.INPUT, PILL, 20, 9, HudStyle.BORDER))
	e.add_theme_stylebox_override("focus", box(HudStyle.INPUT, PILL, 20, 9, HudStyle.CYAN))
	parent.add_child(e)
	return e


## Two or more options in a pill; the chosen one is filled.
static func segmented(parent: Control, options: Array, selected: int, on_change: Callable) -> HBoxContainer:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", box(HudStyle.INPUT, PILL, 4, 4))
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(wrap)
	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 2)
	wrap.add_child(row_box)
	var on_sb := box(HudStyle.CYAN, PILL, 16, 7)
	var off_sb := box(Color(0, 0, 0, 0), PILL, 16, 7)
	var hover_sb := box(Color(HudStyle.CYAN, 0.12), PILL, 16, 7)
	var buttons: Array[Button] = []
	for opt in options:
		var b := Button.new()
		b.text = str(opt)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font(600))
		b.add_theme_font_size_override("font_size", BODY)
		row_box.add_child(b)
		buttons.append(b)
	var apply := func(sel: int) -> void:
		for i in buttons.size():
			var b := buttons[i]
			var on := i == sel
			b.add_theme_stylebox_override("normal", on_sb if on else off_sb)
			b.add_theme_stylebox_override("hover", on_sb if on else hover_sb)
			b.add_theme_stylebox_override("pressed", on_sb)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			for st in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(st, HudStyle.INK_TEXT if on else HudStyle.TEXT_DIM)
	for i in buttons.size():
		buttons[i].pressed.connect(func() -> void:
			apply.call(i)
			on_change.call(i))
	apply.call(selected)
	return row_box
