class_name MonsterRider
extends Node3D
## A monster on a bike, assembled from a recipe of parts, sizes and colours.
##
## Fitting works like a real bike fit: the saddle slides up the seat tube
## until the legs are nearly straight at the bottom of the stroke, and the
## body leans forward until the hands reach the grips. Limbs are Noodles
## rebuilt each frame, so any leg or arm length still pedals and steers.
##
## Axes: +X is forward, +Y up, +Z is the camera side (the rider's right).

const CRANK := 0.17
const WHEEL_R := 0.34
## How far hats sit up and grow on each host, so one hat fits every head.
const HAT_FIT := {
	"body_round": 1.55, "body_square": 1.25, "body_bean": 1.15,
	"head_screen": 1.1, "head_skull": 1.0,
}

## The body turns toward the camera so the face reads in a side view, the
## way side-scroller characters cheat. Legs and arms still reach the bike.
const FACE_TURN := deg_to_rad(-42.0)

var recipe: Dictionary = {}
var cadence := 88.0          ## rpm
var speed := 5.5             ## m/s, for wheel spin

var crank_angle := 0.0
var _distance := 0.0

# Bike pieces.
var _frame: Node3D
var _wheels: Array[Node3D] = []
var _crank: Node3D
var _pedals: Array[Node3D] = []   # [right, left]
var _saddle: Node3D
var _post: Node3D
var _fs: Dictionary = {}          # frame sockets, rider space

# Monster pieces.
var _pivot: Node3D                # uniform transform: saddle position + lean
var _body_scale := Vector3.ONE
var _body_sockets: Dictionary = {}
var _legs: Array[Noodle] = []
var _arms: Array[Noodle] = []
var _hands: Array[Node3D] = []
var _feet: Array[Node3D] = []

# Fit results.
var _saddle_s := 0.45
var _lean := 0.2


func _ready() -> void:
	if not recipe.is_empty():
		build()


func size(key: String) -> float:
	return float(recipe.get("size", {}).get(key, MonsterPresets.SIZE_DEFAULTS[key]))


func colours() -> Dictionary:
	return recipe.get("colours", {})


# ------------------------------------------------------------------ build

func build() -> void:
	for c in get_children():
		c.queue_free()
	_wheels.clear()
	_pedals.clear()
	_legs.clear()
	_arms.clear()
	_hands.clear()
	_feet.clear()
	_build_bike()
	_build_monster()
	_fit()
	pose(crank_angle)


func _build_bike() -> void:
	var bike_colours: Dictionary = recipe.get("bike", {})
	var f := PartKit.part("bike", "frame")
	_frame = f.node
	add_child(_frame)
	for k in f.sockets:
		_fs[k] = (f.sockets[k] as Transform3D).origin
	var fork := PartKit.prop("bike", "fork")
	add_child(fork)
	for axle in ["axle_rear", "axle_front"]:
		var w := PartKit.prop("bike", "wheel")
		w.position = _fs[axle]
		add_child(w)
		_wheels.append(w)
	var c := PartKit.part("bike", "crank")
	_crank = c.node
	_crank.position = _f("bb")
	add_child(_crank)
	for i in 2:
		var p := PartKit.prop("bike", "pedal")
		add_child(p)
		_pedals.append(p)
	_post = PartKit.prop("bike", "seatpost")
	add_child(_post)
	_saddle = PartKit.prop("bike", "saddle")
	add_child(_saddle)
	for n in [_frame, fork, _crank, _post, _saddle] + _wheels + _pedals:
		CampLook.paint(n, bike_colours)


func _build_monster() -> void:
	var col := colours()
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var body_id := "body_%s%s" % [recipe.get("body", "round"), "_fur" if recipe.get("fur", false) else ""]
	var body := PartKit.part("monster", body_id)
	_body_scale = Vector3(size("girth"), size("height"), size("girth"))
	body.node.scale = _body_scale
	_pivot.add_child(body.node)
	CampLook.paint(body.node, col)
	_body_sockets = {}
	for k in body.sockets:
		var t: Transform3D = body.sockets[k]
		_body_sockets[k] = Transform3D(t.basis, t.origin * _body_scale)
	var body_host := "body_" + str(recipe.get("body", "round"))

	# Head, or the body is the head.
	var face_sockets := _body_sockets
	var face_parent: Node3D = _pivot
	var hat_host := body_host
	var head_id := str(recipe.get("head", ""))
	if head_id != "":
		var head := PartKit.part("monster", "head_" + head_id)
		var hs := size("head")
		head.node.transform = Transform3D(Basis().scaled(Vector3.ONE * hs), _b("top"))
		_pivot.add_child(head.node)
		CampLook.paint(head.node, col)
		face_sockets = {}
		for k in head.sockets:
			var t: Transform3D = head.sockets[k]
			face_sockets[k] = Transform3D(t.basis, head.node.transform * t.origin)
		hat_host = "head_" + head_id
		# Nudge the body sockets that belong to the head.
		for k in ["top", "horn_l", "horn_r"]:
			_body_sockets[k] = face_sockets.get(k, _body_sockets[k])

	var eye_scale := size("eye") * (size("head") if head_id != "" else 1.0)
	if recipe.get("eyes", "") != "":
		_attach("eyes_" + str(recipe.eyes), face_parent, face_sockets["face"], eye_scale, col)
	if recipe.get("mouth", "") != "":
		_attach("mouth_" + str(recipe.mouth), face_parent, face_sockets["mouth"], eye_scale, col)
	var hat_scale: float = HAT_FIT.get(hat_host, 1.2) * (size("head") if head_id != "" else 1.0)
	for extra in recipe.get("extras", []):
		match str(extra):
			"horns":
				var hsz := size("horn") * (size("head") if head_id != "" else 1.0)
				_attach("horn_l", face_parent, _body_sockets["horn_l"], hsz, col)
				_attach("horn_r", face_parent, _body_sockets["horn_r"], hsz, col)
			"cap_back", "beanie":
				_attach(str(extra), face_parent, _body_sockets["top"], hat_scale, col)
			"antenna":
				_attach("antenna", face_parent, _body_sockets["top"], 1.0, col)
			"spikes":
				_attach("spikes", face_parent, _body_sockets["top"], size("girth"), col)
			"backpack":
				_attach("backpack", face_parent, _body_sockets["back"], 1.0, col)

	# Limbs.
	var limb_col: Color = col.get("limb", col.get("primary", CampLook.ROLES.primary))
	for i in 2:
		var leg := Noodle.new()
		leg.colour_material = CampLook.limb_material(limb_col)
		add_child(leg)
		_legs.append(leg)
		var arm := Noodle.new()
		arm.colour_material = CampLook.limb_material(limb_col)
		add_child(arm)
		_arms.append(arm)
		var hand := PartKit.prop("monster", "hand_" + str(recipe.get("hands", "mitt")))
		hand.scale = Vector3.ONE * size("hand")
		add_child(hand)
		CampLook.paint(hand, col)
		_hands.append(hand)
		var foot := PartKit.prop("monster", str(recipe.get("feet", "shoe")))
		foot.scale = Vector3.ONE * size("foot")
		add_child(foot)
		CampLook.paint(foot, col)
		_feet.append(foot)


func _attach(part_id: String, parent: Node3D, socket: Transform3D, s: float, col: Dictionary) -> void:
	var p := PartKit.prop("monster", part_id)
	p.transform = Transform3D(socket.basis.orthonormalized().scaled(Vector3.ONE * s), socket.origin)
	parent.add_child(p)
	CampLook.paint(p, col)


# ------------------------------------------------------------------ fit

func _f(k: String) -> Vector3:
	return _fs[k]


func _b(k: String) -> Vector3:
	return (_body_sockets[k] as Transform3D).origin


func _seat_dir() -> Vector3:
	return (_f("seat") - _f("bb")).normalized()


func _saddle_top(s: float) -> Vector3:
	return _f("bb") + _seat_dir() * s + Vector3(0, 0.06, 0)


func _pivot_xf(s: float, lean: float, turn := FACE_TURN) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, -lean) * Basis(Vector3.UP, turn), _saddle_top(s))


## Hips stay square to the bike; only the upper body turns to the camera.
func _hip(side: int, s: float, lean: float) -> Vector3:
	return _pivot_xf(s, lean, 0.0) * _b("hip_r" if side == 0 else "hip_l")


func _shoulder(side: int, s: float, lean: float) -> Vector3:
	return _pivot_xf(s, lean, FACE_TURN * 0.35) * _b("shoulder_r" if side == 0 else "shoulder_l")


func _ankle_for(pedal: Vector3, foot_pitch: float) -> Vector3:
	var fs := size("foot")
	return pedal + Vector3(0, 0.012, 0) - Vector3(0.085, -0.10, 0).rotated(Vector3.BACK, foot_pitch) * fs


func _wrist_for(side: int) -> Vector3:
	var g: Vector3 = _f("grip_r" if side == 0 else "grip_l")
	return g + Vector3(-0.055 * size("hand"), 0, 0)


func _fit() -> void:
	var leg := size("leg")
	var arm := size("arm")
	var bottom := _f("bb") + Vector3(0, -CRANK, 0.13)
	var ankle := _ankle_for(bottom, 0.0)
	_lean = deg_to_rad(12.0)
	for _i in 3:
		# Saddle: legs 93 % extended at the bottom of the stroke.
		var best := 0.45
		var best_err := INF
		for k in 61:
			var s := lerpf(0.12, 0.90, k / 60.0)
			var err := absf(_hip(0, s, _lean).distance_to(ankle) - leg * 0.93)
			if err < best_err:
				best_err = err
				best = s
		_saddle_s = best
		# Lean: hands reach the grips with a little bend left in the arm.
		_lean = deg_to_rad(34.0)      # past this, arms stretch instead
		for d in range(6, 35):
			var l := deg_to_rad(d)
			if _shoulder(0, _saddle_s, l).distance_to(_wrist_for(0)) <= arm * 0.9:
				_lean = l
				break


# ------------------------------------------------------------------ pose

## Advance the ride by dt seconds.
func advance(dt: float) -> void:
	crank_angle += dt * cadence / 60.0 * TAU
	_distance += dt * speed
	pose(crank_angle)


func pose(theta: float) -> void:
	for w in _wheels:
		w.rotation = Vector3(0, 0, -_distance / WHEEL_R)
	_crank.rotation = Vector3(0, 0, -theta)
	var bob := sin(theta * 2.0) * 0.012
	var sway := sin(theta) * deg_to_rad(2.5)
	var s := _saddle_s
	_post.transform = Transform3D(Basis.looking_at(-_seat_dir().cross(Vector3.BACK), _seat_dir()), _saddle_top(s) - Vector3(0, 0.06, 0))
	_saddle.position = _saddle_top(s) - Vector3(0, 0.035, 0)
	var px := _pivot_xf(s, _lean + sin(theta * 2.0) * deg_to_rad(1.0))
	px.basis = px.basis * Basis(Vector3.RIGHT, sway)
	px.origin.y += bob
	_pivot.transform = px

	var limb_r := size("limb")
	for side in 2:
		var a := theta + (0.0 if side == 0 else PI)
		var zsign := 1.0 if side == 0 else -1.0
		var pedal := _f("bb") + Vector3(0, -CRANK, 0).rotated(Vector3.BACK, -a) + Vector3(0, 0, 0.13 * zsign)
		_pedals[side].position = pedal
		var pitch := -0.18 + 0.2 * cos(a + 0.6)
		var ankle := _ankle_for(pedal, pitch)
		var hip := _hip(side, s, _lean) + Vector3(0, bob, 0)
		var leg := size("leg")
		var knee := _joint(hip, ankle, leg * 0.5, leg * 0.5, Vector3(1, 0.25, 0.1 * zsign))
		_legs[side].build([hip, knee, ankle] as Array[Vector3], [limb_r * 1.15, limb_r, limb_r * 0.85] as Array[float])
		_feet[side].transform = Transform3D(Basis(Vector3.BACK, pitch).scaled(Vector3.ONE * size("foot")), ankle)

		var shoulder := _shoulder(side, s, _lean) + Vector3(0, bob, 0)
		var wrist := _wrist_for(side)
		var arm := size("arm")
		var elbow := _joint(shoulder, wrist, arm * 0.5, arm * 0.5, Vector3(-0.5, -1.0, 0.7 * zsign))
		_arms[side].build([shoulder, elbow, wrist] as Array[Vector3], [limb_r * 1.05, limb_r, limb_r * 0.8] as Array[float])
		var fwd := (wrist - elbow).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var up := right.cross(fwd)
		_hands[side].transform = Transform3D(Basis(fwd, up, fwd.cross(up)).scaled(Vector3.ONE * size("hand")), wrist)
	# Fur and gear on the far side sit behind the near limbs automatically.


## Two-bone reach: the joint position for a limb from root to target.
static func _joint(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var d := target - root
	var dist := clampf(d.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var dir := d.normalized()
	var along := (a * a + dist * dist - b * b) / (2.0 * dist)
	var h := sqrt(maxf(a * a - along * along, 0.0))
	var perp := (pole - dir * pole.dot(dir)).normalized()
	return root + dir * along + perp * h
