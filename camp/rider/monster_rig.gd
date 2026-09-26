class_name MonsterRig
extends Node3D
## One monster assembled from a recipe: body, face, extras, and generated
## limbs. It knows nothing about bikes or chairs; callers place the pelvis
## and give targets for the ankles and wrists, and pose() bends the limbs.
##
## Axes: +X is where the monster faces, +Y up, +Z its right side.

var recipe: Dictionary = {}
## Upper-body turn toward a side-view camera (0 = face forward).
var face_turn := 0.0

var pivot: Node3D
var _body_scale := Vector3.ONE
var _sockets: Dictionary = {}     # body sockets, scaled, pivot space
var _legs: Array[Noodle] = []
var _arms: Array[Noodle] = []
var _hands: Array[Node3D] = []
var _feet: Array[Node3D] = []

## How far hats grow on each host, so one hat fits every head.
const HAT_FIT := {
	"body_round": 1.55, "body_square": 1.25, "body_bean": 1.15,
	"head_screen": 1.1, "head_skull": 1.0,
}


func size(key: String) -> float:
	return float(recipe.get("size", {}).get(key, MonsterPresets.SIZE_DEFAULTS[key]))


func socket(k: String) -> Vector3:
	return (_sockets[k] as Transform3D).origin


# ------------------------------------------------------------------ build

func build() -> void:
	for c in get_children():
		c.free()
	_legs.clear()
	_arms.clear()
	_hands.clear()
	_feet.clear()
	var col: Dictionary = recipe.get("colours", {})
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	var body_id := "body_%s%s" % [recipe.get("body", "round"), "_fur" if recipe.get("fur", false) else ""]
	var body := PartKit.part("monster", body_id)
	_body_scale = Vector3(size("girth"), size("height"), size("girth"))
	body.node.scale = _body_scale
	pivot.add_child(body.node)
	CampLook.paint(body.node, col)
	_sockets = {}
	for k in body.sockets:
		var t: Transform3D = body.sockets[k]
		_sockets[k] = Transform3D(t.basis, t.origin * _body_scale)

	var face := _sockets.duplicate()
	var hat_host := "body_" + str(recipe.get("body", "round"))
	var head_id := str(recipe.get("head", ""))
	var head_k := 1.0
	if head_id != "":
		head_k = size("head")
		var head := PartKit.part("monster", "head_" + head_id)
		head.node.transform = Transform3D(Basis().scaled(Vector3.ONE * head_k), socket("top"))
		pivot.add_child(head.node)
		CampLook.paint(head.node, col)
		for k in head.sockets:
			var t: Transform3D = head.sockets[k]
			face[k] = Transform3D(t.basis, head.node.transform * t.origin)
		hat_host = "head_" + head_id

	var face_k := size("eye") * head_k
	if str(recipe.get("eyes", "")) != "":
		_attach("eyes_" + str(recipe.eyes), face["face"], face_k, col)
	if str(recipe.get("mouth", "")) != "":
		_attach("mouth_" + str(recipe.mouth), face["mouth"], face_k, col)
	var hat_k: float = HAT_FIT.get(hat_host, 1.2) * head_k * size("hat")
	for extra in recipe.get("extras", []):
		match str(extra):
			"horns":
				_attach("horn_l", face["horn_l"], size("horn") * head_k, col)
				_attach("horn_r", face["horn_r"], size("horn") * head_k, col)
			"cap_back", "beanie", "hat_pioneer":
				_attach(str(extra), face["top"], hat_k, col)
			"antenna":
				_attach("antenna", face["top"], head_k, col)
			"spikes":
				_attach("spikes", face["top"], size("girth"), col)
			"backpack":
				_attach("backpack", _sockets["back"], 1.0, col)
			"beard":
				_attach("beard", face["mouth"], face_k * size("girth"), col)
			"pipe":
				_attach("pipe", face["mouth"], face_k, col)

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
		add_child(hand)
		CampLook.paint(hand, col)
		_hands.append(hand)
		var foot := PartKit.prop("monster", str(recipe.get("feet", "shoe")))
		add_child(foot)
		CampLook.paint(foot, col)
		_feet.append(foot)


func _attach(part_id: String, sock: Transform3D, s: float, col: Dictionary) -> void:
	var p := PartKit.prop("monster", part_id)
	p.transform = Transform3D(sock.basis.orthonormalized().scaled(Vector3.ONE * s), sock.origin)
	pivot.add_child(p)
	CampLook.paint(p, col)


# ------------------------------------------------------------------ pose

## The pelvis frame: seat point, forward lean, upper-body turn.
func frame(origin: Vector3, lean: float, turn: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, -lean) * Basis(Vector3.UP, turn), origin)


## Hips stay square to the pelvis; only the upper body turns to the camera.
func hip(side: int, origin: Vector3, lean: float) -> Vector3:
	return frame(origin, lean, 0.0) * socket("hip_r" if side == 0 else "hip_l")


func shoulder(side: int, origin: Vector3, lean: float) -> Vector3:
	return frame(origin, lean, face_turn * 0.35) * socket("shoulder_r" if side == 0 else "shoulder_l")


## Where the ankle goes for a sole resting at `sole` (ball of the foot).
func ankle_for(sole: Vector3, pitch: float) -> Vector3:
	return sole - Vector3(0.085, -0.10, 0).rotated(Vector3.BACK, pitch) * size("foot")


## Pose everything. ankles: [Vector3 right, left]; pitches: foot angles;
## wrists: [right, left]; poles bend knees and elbows.
func pose(origin: Vector3, lean: float, sway: float, ankles: Array, pitches: Array,
		wrists: Array, knee_pole := Vector3(1, 0.25, 0), elbow_pole := Vector3(-0.5, -1.0, 0.7)) -> void:
	var px := frame(origin, lean, face_turn)
	px.basis = px.basis * Basis(Vector3.RIGHT, sway)
	pivot.transform = px
	var r := size("limb")
	var leg := size("leg")
	var arm := size("arm")
	for side in 2:
		var z := 1.0 if side == 0 else -1.0
		var h := hip(side, origin, lean)
		var ankle: Vector3 = ankles[side]
		var knee := joint(h, ankle, leg * 0.5, leg * 0.5, Vector3(knee_pole.x, knee_pole.y, knee_pole.z + 0.1 * z))
		_legs[side].build([h, knee, ankle] as Array[Vector3], [r * 1.15, r, r * 0.85] as Array[float])
		_feet[side].transform = Transform3D(Basis(Vector3.BACK, float(pitches[side])).scaled(Vector3.ONE * size("foot")), ankle)
		var s := shoulder(side, origin, lean)
		var w: Vector3 = wrists[side]
		var elbow := joint(s, w, arm * 0.5, arm * 0.5, Vector3(elbow_pole.x, elbow_pole.y, elbow_pole.z * z))
		_arms[side].build([s, elbow, w] as Array[Vector3], [r * 1.05, r, r * 0.8] as Array[float])
		var fwd := (w - elbow).normalized()
		var up := (Vector3.UP - fwd * fwd.y).normalized()
		if up.length() < 0.1:
			up = Vector3.BACK
		_hands[side].transform = Transform3D(Basis(fwd, up, fwd.cross(up)).scaled(Vector3.ONE * size("hand")), w)


## Two-bone reach: the joint position for a limb from root to target.
static func joint(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var d := target - root
	var dist := clampf(d.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var dir := d.normalized()
	var along := (a * a + dist * dist - b * b) / (2.0 * dist)
	var h := sqrt(maxf(a * a - along * along, 0.0))
	var perp := (pole - dir * pole.dot(dir)).normalized()
	return root + dir * along + perp * h
