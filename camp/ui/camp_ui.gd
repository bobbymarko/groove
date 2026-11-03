class_name CampUI
extends RefCounted
## Camp's interface style: a clean geometric sans on Groove's colour tokens.
## Groove keeps its pixel faces (HudStyle); Camp's text goes through here.
##
## The bundled font is one variable file; weights are FontVariation axes.
## Until it is in the repo, a system face stands in for local previews.

const FONT_PATH := "res://assets/fonts/Outfit[wght].ttf"
const FALLBACK_FACES := ["Avenir Next", "Futura", "Helvetica Neue"]

const BODY := 18
const SMALL := 15
const TITLE := 44

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
	HudStyle.style_button(b, kind, 14, 8)
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
	e.add_theme_stylebox_override("normal", HudStyle.flat(HudStyle.INPUT, HudStyle.RADIUS, 12, 9, HudStyle.BORDER))
	e.add_theme_stylebox_override("focus", HudStyle.flat(HudStyle.INPUT, HudStyle.RADIUS, 12, 9, HudStyle.CYAN))
	parent.add_child(e)
	return e


## Two or more options in a pill; the chosen one is filled.
static func segmented(parent: Control, options: Array, selected: int, on_change: Callable) -> HBoxContainer:
	var wrap := HudStyle.panel(parent, HudStyle.INPUT, HudStyle.RADIUS + 1, 3)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 2)
	wrap.add_child(row_box)
	var on_sb := HudStyle.flat(HudStyle.CYAN, HudStyle.RADIUS - 1, 14, 6)
	var off_sb := HudStyle.flat(Color(0, 0, 0, 0), HudStyle.RADIUS - 1, 14, 6)
	var hover_sb := HudStyle.flat(Color(HudStyle.CYAN, 0.12), HudStyle.RADIUS - 1, 14, 6)
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
