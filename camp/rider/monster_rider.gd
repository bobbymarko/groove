class_name MonsterRider
extends Node3D
## A monster on a bike. Fitting works like a real bike fit: the saddle slides
## up the seat tube until the legs are nearly straight at the bottom of the
## stroke, and the body leans forward until the hands reach the grips.
## With no "body" in the recipe it is just a parked bike.
##
## Axes: +X is forward, +Y up, +Z is the camera side (the rider's right).

const CRANK := 0.17
const WHEEL_R := 0.34
## The body turns toward the camera so the face reads in a side view, the
## way side-scroller characters cheat.
const SIDE_VIEW_TURN := deg_to_rad(-42.0)

var recipe: Dictionary = {}
var cadence := 88.0          ## rpm
var speed := 5.5             ## m/s, for wheel spin
var face_turn := SIDE_VIEW_TURN

var crank_angle := 0.0
var rig: MonsterRig
var _distance := 0.0

var _wheels: Array[Node3D] = []
var _crank: Node3D
var _pedals: Array[Node3D] = []   # [right, left]
var _saddle: Node3D
var _post: Node3D
var _fs: Dictionary = {}          # frame sockets, rider space

var _saddle_s := 0.45
var _lean := 0.2


func _ready() -> void:
	if not recipe.is_empty():
		build()


func build() -> void:
	for c in get_children():
		c.free()
	_wheels.clear()
	_pedals.clear()
	_build_bike()
	rig = null
	if recipe.has("body"):
		rig = MonsterRig.new()
		rig.recipe = recipe
		rig.face_turn = face_turn
		add_child(rig)
		rig.build()
		_fit()
	pose(crank_angle)


func _build_bike() -> void:
	var bike_colours: Dictionary = recipe.get("bike", {})
	var f := PartKit.part("bike", "frame")
	add_child(f.node)
	for k in f.sockets:
		_fs[k] = (f.sockets[k] as Transform3D).origin
	var fork := PartKit.prop("bike", "fork")
	add_child(fork)
	for axle in ["axle_rear", "axle_front"]:
		var w := PartKit.prop("bike", "wheel")
		w.position = _fs[axle]
		add_child(w)
		_wheels.append(w)
	_crank = PartKit.prop("bike", "crank")
	_crank.position = _fs["bb"]
	add_child(_crank)
	for i in 2:
		var p := PartKit.prop("bike", "pedal")
		add_child(p)
		_pedals.append(p)
	_post = PartKit.prop("bike", "seatpost")
	add_child(_post)
	_saddle = PartKit.prop("bike", "saddle")
	add_child(_saddle)
	for n in [f.node, fork, _crank, _post, _saddle] + _wheels + _pedals:
		CampLook.paint(n, bike_colours)


func _f(k: String) -> Vector3:
	return _fs[k]


func _seat_dir() -> Vector3:
	return (_f("seat") - _f("bb")).normalized()


func _saddle_top(s: float) -> Vector3:
	return _f("bb") + _seat_dir() * s + Vector3(0, 0.06, 0)


func _wrist_for(side: int) -> Vector3:
	return _f("grip_r" if side == 0 else "grip_l") + Vector3(-0.055 * rig.size("hand"), 0, 0)


func _fit() -> void:
	var leg := rig.size("leg")
	var arm := rig.size("arm")
	var ankle := rig.ankle_for(_f("bb") + Vector3(0, -CRANK + 0.012, 0.13), 0.0)
	_lean = deg_to_rad(12.0)
	for _i in 3:
		# Saddle: legs 93 % extended at the bottom of the stroke.
		var best := 0.45
		var best_err := INF
		for k in 61:
			var s := lerpf(0.12, 0.90, k / 60.0)
			var err := absf(rig.hip(0, _saddle_top(s), _lean).distance_to(ankle) - leg * 0.93)
			if err < best_err:
				best_err = err
				best = s
		_saddle_s = best
		# Lean: hands reach the grips with a little bend left in the arm.
		_lean = deg_to_rad(34.0)      # past this, arms stretch instead
		for d in range(6, 35):
			var l := deg_to_rad(d)
			if rig.shoulder(0, _saddle_top(_saddle_s), l).distance_to(_wrist_for(0)) <= arm * 0.9:
				_lean = l
				break


## Advance the ride by dt seconds.
func advance(dt: float) -> void:
	crank_angle += dt * cadence / 60.0 * TAU
	_distance += dt * speed
	pose(crank_angle)


func pose(theta: float) -> void:
	for w in _wheels:
		w.rotation = Vector3(0, 0, -_distance / WHEEL_R)
	_crank.rotation = Vector3(0, 0, -theta)
	var top := _saddle_top(_saddle_s)
	_post.transform = Transform3D(Basis.looking_at(-_seat_dir().cross(Vector3.BACK), _seat_dir()), top - Vector3(0, 0.06, 0))
	_saddle.position = top - Vector3(0, 0.035, 0)
	var pedals: Array[Vector3] = []
	var pitches: Array[float] = []
	for side in 2:
		var a := theta + (0.0 if side == 0 else PI)
		var z := 1.0 if side == 0 else -1.0
		var pedal := _f("bb") + Vector3(0, -CRANK, 0).rotated(Vector3.BACK, -a) + Vector3(0, 0, 0.13 * z)
		_pedals[side].position = pedal
		pedals.append(pedal)
		pitches.append(-0.18 + 0.2 * cos(a + 0.6))
	if rig == null:
		return
	var bob := Vector3(0, sin(theta * 2.0) * 0.012, 0)
	var ankles: Array = []
	for side in 2:
		ankles.append(rig.ankle_for(pedals[side] + Vector3(0, 0.012, 0), pitches[side]))
	var wrists: Array = [_wrist_for(0), _wrist_for(1)]
	rig.pose(top + bob, _lean + sin(theta * 2.0) * deg_to_rad(1.0), sin(theta) * deg_to_rad(2.5),
		ankles, pitches, wrists)
