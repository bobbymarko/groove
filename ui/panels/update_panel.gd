class_name UpdatePanel
extends VBoxContainer
## Content of the Update sheet: what is new, and either the in-app install
## (macOS) or a link to the release page (R36).

var _status: Label
var _bar: ProgressBar
var _install: Button


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_build_ui()
	Updates.progress.connect(_on_progress)
	Updates.failed.connect(_on_failed)


func _build_ui() -> void:
	var l: Dictionary = Updates.latest
	if not Updates.update_available():
		var up := HudStyle.label(self, "You have the latest Groove, %s." % Updates.current_version, 18, 700)
		up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var head := HudStyle.label(self, "Groove %s is ready. You have %s." % [l.version, Updates.current_version], 18, 700)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var notes := HudStyle.section(self, "What's new")
	var body := HudStyle.label(notes, str(l.notes) if str(l.notes) != "" else "No notes for this release.", 13, 500, HudStyle.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var blocker := Updates.install_blocker()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	if blocker == "":
		_install = HudStyle.button(bar, "Download and install", 16, _start, "primary")
		_install.custom_minimum_size.y = 44
		HudStyle.button(bar, "Release page", 14, func() -> void: OS.shell_open(str(l.url)), "secondary")
	else:
		var why := HudStyle.label(self, blocker, 13, 500, HudStyle.TEXT_DIM)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		move_child(why, bar.get_index())
		var dl := HudStyle.button(bar, "Download from GitHub", 16, func() -> void: OS.shell_open(str(l.url)), "primary")
		dl.custom_minimum_size.y = 44
	var size_mb := float(l.asset_size) / 1048576.0
	HudStyle.label(bar, ("%s, %.0f MB" % [l.asset_name, size_mb]) if str(l.asset_name) != "" else "", 12, 500, HudStyle.TEXT_DIM) \
		.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status = HudStyle.label(self, "", 13, 700, HudStyle.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar = HudStyle.bar(self, 10, 5)
	_bar.max_value = 1.0
	_bar.visible = false


func _start() -> void:
	_install.disabled = true
	_install.text = "UPDATING…"
	_status.text = "Downloading…"
	_status.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	_bar.visible = true
	_bar.value = 0.0
	Updates.install()


func _on_progress(step: String, fraction: float) -> void:
	if _status == null:
		return
	if fraction >= 0.0:
		_bar.value = fraction
		_status.text = "%s… %d%%" % [step, int(fraction * 100.0)]
	else:
		_bar.value = 1.0
		_status.text = step + "…"
	if step == "Restarting":
		_status.text = "Restarting Groove…"


func _on_failed(message: String) -> void:
	if _status == null:
		return
	_status.text = message + ". You can still download it from the release page."
	_status.add_theme_color_override("font_color", HudStyle.WARN_RED)
	_bar.visible = false
	if _install:
		_install.disabled = false
		_install.text = "TRY AGAIN"
