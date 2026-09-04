class_name HudStyle
extends RefCounted
## Shared look for the ride HUD: Lato, translucent rounded panels, and chunky
## progress bars, in the spirit of the reference layout.

const FONT_REGULAR := "res://assets/fonts/Lato-Regular.ttf"
const FONT_BOLD := "res://assets/fonts/Lato-Bold.ttf"
const FONT_BLACK := "res://assets/fonts/Lato-Black.ttf"
# Groove tokens (Design.md). Change colours here, never per screen.
const INK := Color("000c18")
const NAVY := Color("012041")
const ICE := Color("f4f5f5")
const CYAN := Color("00b7f5")
const TEAL := Color("01b5cc")
const YELLOW := Color("feb801")
const ORANGE := Color("ef6a01")
const RED := Color("dc352d")
const GREEN := Color("3ccf6a")
const BORDER := Color(0.4, 0.52, 0.66, 0.35)
const INK_TEXT := Color("01040a")

const PANEL := Color(0.008, 0.055, 0.12, 0.82)
const PANEL_ROW := Color(0.043, 0.165, 0.32, 0.75)
const ACCENT := ORANGE
const BAR_BG := Color(0.024, 0.094, 0.18, 0.95)
const BAR_FG := CYAN
const TEXT := ICE
const TEXT_DIM := Color(0.957, 0.961, 0.961, 0.6)
const CARD := Color(0.024, 0.094, 0.18, 0.9)
const INPUT := Color(0.0, 0.047, 0.094, 0.92)
const BUTTON := Color(0.043, 0.165, 0.32, 0.9)
const BUTTON_HOVER := Color(0.086, 0.29, 0.525, 1.0)
const BUTTON_PRESSED := Color(0.024, 0.125, 0.25, 1.0)
const OK_GREEN := GREEN
const WARN_RED := RED
const RADIUS := 4

static var _fonts: Dictionary = {}


## Lato ships as separate weights: regular below 600, bold to 800, black above.
static func font(weight: int = 500) -> Font:
	var path := FONT_REGULAR if weight < 600 else (FONT_BOLD if weight < 800 else FONT_BLACK)
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


static func label(parent: Control, text: String, size: int, weight: int = 500, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## Put `small` on the same text baseline as `big`. Godot containers align
## boxes, not baselines; a label's box bottom sits one font descent below the
## baseline, so the smaller label is lifted by the difference in descents.
static func share_baseline(row: BoxContainer, big: Label, small: Label) -> void:
	row.alignment = row.alignment   # no-op; documents that children are bottom-aligned below
	big.size_flags_vertical = Control.SIZE_SHRINK_END
	var big_font := big.get_theme_font("font")
	var small_font := small.get_theme_font("font")
	var d_big := big_font.get_descent(big.get_theme_font_size("font_size"))
	var d_small := small_font.get_descent(small.get_theme_font_size("font_size"))
	var lift := maxf(d_big - d_small, 0.0)
	# Re-parent the small label into a margin box that raises it by `lift`.
	var idx := small.get_index()
	row.remove_child(small)
	var m := MarginContainer.new()
	m.size_flags_vertical = Control.SIZE_SHRINK_END
	m.add_theme_constant_override("margin_bottom", int(round(lift)))
	m.add_child(small)
	row.add_child(m)
	row.move_child(m, idx)


static func panel(parent: Control, color := PANEL, radius := RADIUS, pad := 12, border := true) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	if border:
		sb.set_border_width_all(1)
		sb.border_color = BORDER
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


## kind: "ghost" (row fill, ice text; HUD and toolbars), "primary" (cyan fill,
## ink text), "secondary" (cyan outline). Button text is uppercase per Design.md.
static func button(parent: Control, text: String, size: int, on_pressed: Callable, kind := "ghost") -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", size)
	style_button(b, kind)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


static func style_button(b: Button, kind := "ghost", pad_x := 14, pad_y := 7) -> void:
	match kind:
		"primary":
			b.add_theme_stylebox_override("normal", flat(CYAN, RADIUS, pad_x, pad_y))
			b.add_theme_stylebox_override("hover", flat(CYAN.lightened(0.15), RADIUS, pad_x, pad_y))
			b.add_theme_stylebox_override("pressed", flat(CYAN.darkened(0.2), RADIUS, pad_x, pad_y))
			b.add_theme_stylebox_override("disabled", flat(Color(CYAN, 0.3), RADIUS, pad_x, pad_y))
			for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(st, INK_TEXT)
			b.add_theme_color_override("font_disabled_color", Color(INK_TEXT, 0.5))
		"secondary":
			b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), RADIUS, pad_x, pad_y, CYAN))
			b.add_theme_stylebox_override("hover", flat(Color(CYAN, 0.15), RADIUS, pad_x, pad_y, CYAN))
			b.add_theme_stylebox_override("pressed", flat(Color(CYAN, 0.3), RADIUS, pad_x, pad_y, CYAN))
			b.add_theme_stylebox_override("disabled", flat(Color(0, 0, 0, 0), RADIUS, pad_x, pad_y, Color(CYAN, 0.3)))
			for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(st, CYAN)
			b.add_theme_color_override("font_disabled_color", Color(CYAN, 0.4))
		_:
			b.add_theme_stylebox_override("normal", flat(BUTTON, RADIUS, pad_x, pad_y, BORDER))
			b.add_theme_stylebox_override("hover", flat(BUTTON_HOVER, RADIUS, pad_x, pad_y, Color(CYAN, 0.6)))
			b.add_theme_stylebox_override("pressed", flat(BUTTON_PRESSED, RADIUS, pad_x, pad_y, CYAN))
			b.add_theme_stylebox_override("disabled", flat(Color(BUTTON, 0.35), RADIUS, pad_x, pad_y, Color(BORDER, 0.2)))
			for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(st, TEXT)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Icon-only button (24-unit SVG from assets/icons), tinted ice.
static func icon_button(parent: Control, icon_name: String, on_pressed: Callable, size := 16, kind := "ghost") -> Button:
	var b := Button.new()
	b.icon = load("res://assets/icons/%s.svg" % icon_name)
	b.expand_icon = true
	b.custom_minimum_size = Vector2(size + 16, size + 12)
	b.add_theme_constant_override("icon_max_width", size)
	style_button(b, kind, 6, 4)   # slim padding so the icon has room to draw
	var tint := INK_TEXT if kind == "primary" else (CYAN if kind == "secondary" else TEXT)
	for st in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(st, tint)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


## Tinted vector icon.
static func icon(parent: Control, icon_name: String, size := 16, color := TEXT) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/icons/%s.svg" % icon_name)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.modulate = color
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(t)
	return t


## Small uppercase section label in cyan.
static func section_label(parent: Control, text: String, size := 12, color := CYAN) -> Label:
	return label(parent, text.to_upper(), size, 700, color)


static func flat(color: Color, radius := 6, pad_x := 10, pad_y := 6, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	return sb


## Text field in the HUD style. Expands horizontally unless the caller says otherwise.
static func input(parent: Control, text: String, placeholder := "", secret := false, size := 14) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.secret = secret
	e.add_theme_font_override("font", font(500))
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_stylebox_override("normal", flat(INPUT, RADIUS, 10, 7, BORDER))
	e.add_theme_stylebox_override("focus", flat(INPUT, RADIUS, 10, 7, CYAN))
	e.add_theme_stylebox_override("read_only", flat(INPUT, RADIUS, 10, 7, BORDER))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	e.add_theme_color_override("caret_color", TEXT)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e


## Segmented control: one button per option, the selected one lit. Calls
## on_change(index) when the user picks another. Returns the button row.
static func segmented(parent: Control, options: Array, selected: int, on_change: Callable, size := 13) -> HBoxContainer:
	var wrap := panel(parent, INPUT, RADIUS + 1, 3)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	wrap.add_child(row)
	var on_sb := flat(CYAN, RADIUS - 1, 11, 4)
	var off_sb := flat(Color(0, 0, 0, 0), RADIUS - 1, 11, 4)
	var off_hover := flat(Color(CYAN, 0.12), RADIUS - 1, 11, 4)
	var buttons: Array[Button] = []
	for opt in options:
		var b := Button.new()
		b.text = str(opt)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font(700))
		b.add_theme_font_size_override("font_size", size)
		b.add_theme_color_override("font_pressed_color", INK_TEXT)
		b.add_theme_color_override("font_hover_pressed_color", INK_TEXT)
		b.add_theme_color_override("font_hover_color", TEXT)
		row.add_child(b)
		buttons.append(b)
	var apply := func(sel: int) -> void:
		for i in buttons.size():
			var b := buttons[i]
			b.set_pressed_no_signal(i == sel)
			b.add_theme_stylebox_override("normal", on_sb if i == sel else off_sb)
			b.add_theme_stylebox_override("hover", on_sb if i == sel else off_hover)
			b.add_theme_stylebox_override("pressed", on_sb)
			b.add_theme_stylebox_override("hover_pressed", on_sb)
			b.add_theme_color_override("font_color", INK_TEXT if i == sel else TEXT_DIM)
	for i in buttons.size():
		buttons[i].pressed.connect(func() -> void:
			apply.call(i)
			on_change.call(i))
	apply.call(selected)
	return row


## Horizontal slider with a thin track and a round grabber.
static func slider(parent: Control) -> HSlider:
	var s := HSlider.new()
	var track := flat(BAR_BG, 3, 0, 3)
	var fill := flat(CYAN, 3, 0, 3)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _grabber(Color(0.93, 0.93, 0.96)))
	s.add_theme_icon_override("grabber_highlight", _grabber(Color.WHITE))
	s.add_theme_icon_override("grabber_disabled", _grabber(Color(0.5, 0.5, 0.55)))
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	return s


static var _grabbers: Dictionary = {}

static func _grabber(color: Color) -> Texture2D:
	if _grabbers.has(color):
		return _grabbers[color]
	var n := 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	var tex := ImageTexture.create_from_image(img)
	_grabbers[color] = tex
	return tex


## One workout block as in the ride HUD: intervals show "6 x" with the on/off
## lines, other blocks a single right-aligned line. `g` is a WorkoutSummary row.
static func block_row(parent: Control, g: Dictionary, big := 26, small := 16, bg := PANEL_ROW) -> PanelContainer:
	var row := PanelContainer.new()
	var effort := WorkoutColors.for_fraction(float(g.get("peak", 0.0)), bool(g.get("has_target", true)))
	var tinted := WorkoutColors.row_background(bg, effort)
	row.set_meta("bg", tinted)   # the ride HUD restores this after the active highlight moves on
	style_block_row(row, tinted)
	row.set_meta("effort", effort)
	parent.add_child(row)
	if g.kind == "intervals":
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var count_l := label(h, "%d x" % int(g.count), big, 700)
		count_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lines := VBoxContainer.new()
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lines.add_theme_constant_override("separation", 0)
		h.add_child(lines)
		label(lines, "%s @ %dw" % [duration(g.on_dur), int(g.on_w)], small, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label(lines, "%s @ %dw" % [duration(g.off_dur), int(g.off_w)], small, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		label(row, g.text, small, 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


static func style_block_row(row: PanelContainer, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(RADIUS)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)


## Settings card: title, optional one-line help, optional action button on the
## title row. Returns the box to fill.
static func section(parent: Control, title: String, help := "", action_text := "", action := Callable()) -> VBoxContainer:
	var card := panel(parent, CARD, RADIUS, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	section_label(head, title, 12).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if action_text != "":
		button(head, action_text, 12, action)
	if help != "":
		var h := label(v, help, 12, 500, Color(1, 1, 1, 0.5))
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return v


## Labelled form row: a fixed-width caption, then whatever the caller adds.
static func row(parent: Control, caption: String, caption_width := 110) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var l := label(h, caption, 13, 500, TEXT_DIM)
	l.custom_minimum_size.x = caption_width
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return h


## Human duration like the reference: "10min", "1min", "30s", "1:30".
static func duration(seconds: float) -> String:
	var s := int(round(seconds))
	if s % 60 == 0:
		return "%dmin" % (s / 60)
	if s < 60:
		return "%ds" % s
	return "%d:%02d" % [s / 60, s % 60]
