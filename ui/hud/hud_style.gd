class_name HudStyle
extends RefCounted
## Shared look for the ride HUD: the pixel font, translucent blocky panels,
## and chunky progress bars, in the spirit of the reference layout.

const FONT_PATH := "res://assets/fonts/PixelifySans.ttf"
const PANEL := Color(0.06, 0.07, 0.11, 0.62)
const PANEL_ROW := Color(0.10, 0.12, 0.17, 0.55)
const ACCENT := Color(0.86, 0.33, 0.30, 0.85)
const BAR_BG := Color(0.12, 0.13, 0.19, 0.9)
const BAR_FG := Color(0.93, 0.93, 0.96)
const TEXT := Color(0.97, 0.97, 0.99)
const TEXT_DIM := Color(0.97, 0.97, 0.99, 0.65)

static var _fonts: Dictionary = {}


static func font(weight: int = 500) -> Font:
	if not _fonts.has(weight):
		var base: FontFile = load(FONT_PATH)
		var v := FontVariation.new()
		v.base_font = base
		v.variation_opentype = {"wght": weight}
		_fonts[weight] = v
	return _fonts[weight]


static func label(parent: Control, text: String, size: int, weight: int = 500, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func panel(parent: Control, color := PANEL, radius := 8, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


static func bar(parent: Control, height := 12, radius := 6, fg := BAR_FG) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = 0.0
	b.show_percentage = false
	b.custom_minimum_size.y = height
	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG
	bg.set_corner_radius_all(radius)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fg
	fill.set_corner_radius_all(radius)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	parent.add_child(b)
	return b


static func button(parent: Control, text: String, size: int, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


## Human duration like the reference: "10min", "1min", "30s", "1:30".
static func duration(seconds: float) -> String:
	var s := int(round(seconds))
	if s % 60 == 0:
		return "%dmin" % (s / 60)
	if s < 60:
		return "%ds" % s
	return "%d:%02d" % [s / 60, s % 60]
