extends Node
## Look around Camp's style lab. Keys: 1 trail, 2 lineup, 3 three-quarter,
## 4 camp, 5 trader, Esc to quit.

const MODES := ["hero", "lineup", "three_quarter", "camp", "trader"]

var _lab: StyleLab


func _ready() -> void:
	var start := "camp"
	for a in OS.get_cmdline_user_args():
		if a in MODES:
			start = a
	_show(start)


func _show(mode: String) -> void:
	if _lab:
		_lab.free()
	_lab = StyleLab.new()
	_lab.mode = mode
	_lab.live = true
	add_child(_lab)


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	var k := (e as InputEventKey).keycode
	if k == KEY_ESCAPE:
		get_tree().quit()
	elif k >= KEY_1 and k <= KEY_5:
		_show(MODES[k - KEY_1])
