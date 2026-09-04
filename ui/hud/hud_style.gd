class_name HudStyle
extends RefCounted
## Shared look for the ride HUD: Lato, translucent rounded panels, and chunky
## progress bars, in the spirit of the reference layout.

const FONT_REGULAR := "res://assets/fonts/Lato-Regular.ttf"
const FONT_BOLD := "res://assets/fonts/Lato-Bold.ttf"
const FONT_BLACK := "res://assets/fonts/Lato-Black.ttf"
const PANEL := Color(0.06, 0.07, 0.11, 0.62)
const PANEL_ROW := Color(0.10, 0.12, 0.17, 0.55)
const ACCENT := Color(0.86, 0.33, 0.30, 0.85)
const BAR_BG := Color(0.12, 0.13, 0.19, 0.9)
const BAR_FG := Color(0.93, 0.93, 0.96)
const TEXT := Color(0.97, 0.97, 0.99)
const TEXT_DIM := Color(0.97, 0.97, 0.99, 0.65)
const CARD := Color(0.13, 0.15, 0.21, 0.85)
const INPUT := Color(0.07, 0.08, 0.12, 0.9)
const BUTTON := Color(0.20, 0.22, 0.30, 0.95)
const BUTTON_HOVER := Color(0.28, 0.31, 0.41, 1.0)
const BUTTON_PRESSED := Color(0.15, 0.17, 0.23, 1.0)
const OK_GREEN := Color(0.55, 0.85, 0.6)
const WARN_RED := Color(1, 0.6, 0.6)

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
	b.add_theme_stylebox_override("normal", flat(BUTTON, 6, 12, 6))
	b.add_theme_stylebox_override("hover", flat(BUTTON_HOVER, 6, 12, 6))
	b.add_theme_stylebox_override("pressed", flat(BUTTON_PRESSED, 6, 12, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", flat(Color(BUTTON, 0.35), 6, 12, 6))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


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
	e.add_theme_stylebox_override("normal", flat(INPUT, 6, 10, 7))
	e.add_theme_stylebox_override("focus", flat(INPUT, 6, 10, 7, Color(0.55, 0.6, 0.78, 0.9)))
	e.add_theme_stylebox_override("read_only", flat(INPUT, 6, 10, 7))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	e.add_theme_color_override("caret_color", TEXT)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e


## Segmented control: one button per option, the selected one lit. Calls
## on_change(index) when the user picks another. Returns the button row.
static func segmented(parent: Control, options: Array, selected: int, on_change: Callable, size := 13) -> HBoxContainer:
	var wrap := panel(parent, INPUT, 7, 3)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	wrap.add_child(row)
	var on_sb := flat(BUTTON_HOVER, 5, 11, 4)
	var off_sb := flat(Color(0, 0, 0, 0), 5, 11, 4)
	var off_hover := flat(Color(1, 1, 1, 0.05), 5, 11, 4)
	var buttons: Array[Button] = []
	for opt in options:
		var b := Button.new()
		b.text = str(opt)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font(700))
		b.add_theme_font_size_override("font_size", size)
		b.add_theme_color_override("font_pressed_color", TEXT)
		b.add_theme_color_override("font_hover_pressed_color", TEXT)
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
			b.add_theme_color_override("font_color", TEXT if i == sel else TEXT_DIM)
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
	var fill := flat(Color(0.72, 0.75, 0.86), 3, 0, 3)
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
	style_block_row(row, bg)
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
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)


## Settings card: title, optional one-line help, optional action button on the
## title row. Returns the box to fill.
static func section(parent: Control, title: String, help := "", action_text := "", action := Callable()) -> VBoxContainer:
	var card := panel(parent, CARD, 10, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	label(head, title, 15, 700).size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
