class_name RiderBody
extends Node3D
## A rigged character posed on the bike by inverse kinematics every frame:
## hips on the saddle, spine leaned to the bars, feet following the pedals,
## hands on the grips. Works in the parent Rider's local space (+Z forward,
## Y up, rig-left on +X). The model is Quaternius's Universal Base Character
## (Superhero male, CC0); logical bone names map to its Unreal-style rig below.

const SCENE_PATH := "res://assets/character/Superhero_Male_FullBody.gltf"
## Logical name -> rig bone. Sides: "Left" -> "_l", "Right" -> "_r".
const BONES := {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03", "Neck": "neck_01", "Head": "Head",
	"Shoulder": "clavicle", "Arm": "upperarm", "ForeArm": "lowerarm", "Hand": "hand",
	"UpLeg": "thigh", "Leg": "calf", "Foot": "foot", "ToeBase": "ball",
}
const FINGERS := ["index", "middle", "ring", "pinky"]

var skeleton: Skeleton3D
var _bones: Dictionary = {}          # short name -> index
var _child_dir: Dictionary = {}      # bone index -> unit vector to its child in bone-local rest space
var _len: Dictionary = {}            # "thigh_l", "shin_l", "upper_arm_l", "forearm_l", ... in metres
var _hip_offset_l: Vector3           # hip joint relative to the Hips bone origin, skeleton rest space
var _hip_offset_r: Vector3
var _ready_ok := false
var lean_sign := 1.0   # positive rotation about X tilts the spine toward +Z (forward)
## Finger curl in radians per joint (knuckle, middle, tip) and the local axis to curl around.
var finger_curl := Vector3(1.35, 1.3, 0.9)
var finger_axis := Vector3.BACK      # this rig's finger bones curl about their local Z
var sway_phase := 0.0                ## crank angle while pedalling; 0 when still (drives the body rock)
var sway_amount := 1.0
var _fingers: Array[int] = []       # finger joint bones, thumbs excluded
var _thumbs: Array[int] = []


static func available() -> bool:
	return ResourceLoader.exists(SCENE_PATH)


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		return
	var character := packed.instantiate()
	add_child(character)
	skeleton = _find_skeleton(character)
	if skeleton == null:
		return
	var ap := character.get_node_or_null("AnimationPlayer")
	if ap:
		ap.queue_free()        # we pose the rig ourselves
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]:
		_bones[n] = skeleton.find_bone(BONES[n])
	for side in ["Left", "Right"]:
		var suffix := "_l" if side == "Left" else "_r"
		for n in ["Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase"]:
			_bones[side + n] = skeleton.find_bone(BONES[n] + suffix)
	for k in _bones:
		if _bones[k] < 0:
			push_warning("RiderBody: bone missing for %s" % k)
	for pair in [["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["LeftFoot", "LeftToeBase"],
			["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"], ["RightFoot", "RightToeBase"],
			["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"],
			["Spine", "Spine1"], ["Spine1", "Spine2"], ["Spine2", "Neck"], ["Neck", "Head"]]:
		var b: int = _bones[pair[0]]
		var c: int = _bones[pair[1]]
		_child_dir[b] = skeleton.get_bone_rest(c).origin.normalized()
	for suffix in ["_l", "_r"]:
		for finger in FINGERS:
			for j in range(1, 4):
				var idx := skeleton.find_bone("%s_%02d%s" % [finger, j, suffix])
				if idx >= 0:
					_fingers.append(idx)
		for j in range(1, 4):
			var idx := skeleton.find_bone("thumb_%02d%s" % [j, suffix])
			if idx >= 0:
				_thumbs.append(idx)
	var rest := func(n: String) -> Vector3: return skeleton.get_bone_global_rest(_bones[n]).origin
	_len["thigh"] = rest.call("LeftUpLeg").distance_to(rest.call("LeftLeg"))
	_len["shin"] = rest.call("LeftLeg").distance_to(rest.call("LeftFoot"))
	_len["upper_arm"] = rest.call("LeftArm").distance_to(rest.call("LeftForeArm"))
	_len["forearm"] = rest.call("LeftForeArm").distance_to(rest.call("LeftHand"))
	_hip_offset_l = rest.call("LeftUpLeg") - rest.call("Hips")
	_hip_offset_r = rest.call("RightUpLeg") - rest.call("Hips")
	_restyle(character)
	_ready_ok = true


func is_ready() -> bool:
	return _ready_ok


## Pose for this frame. All points in the Rider's local space.
## saddle: where the hips sit; lean_pitch: forward lean of the torso in radians;
## pedal_l/pedal_r and bar_l/bar_r are for the rig's Left/Right limbs, which in
## Mixamo's rest pose sit on +X and -X respectively (the character faces +Z).
func pose(saddle: Vector3, lean_pitch: float, pedal_l: Vector3, pedal_r: Vector3, bar_l: Vector3, bar_r: Vector3) -> void:
	if not _ready_ok:
		return
	var parent := get_parent() as Node3D
	var to_skel: Transform3D = skeleton.global_transform.affine_inverse() * parent.global_transform
	# Pedalling sway: the pelvis rocks toward the leg that is pushing down and
	# shifts a little that way; the spine counter-rolls so the shoulders stay
	# quieter; the elbows flex in rhythm (see the arm hints below).
	var s := sin(sway_phase) * sway_amount
	var bob := absf(cos(sway_phase)) * sway_amount
	var hips_pos: Vector3 = to_skel * (saddle + Vector3(0.014 * s, -0.005 * bob, 0.0))
	# Every frame starts from the rest pose; all rotations below are absolute.
	skeleton.reset_bone_poses()
	# Hips: rest orientation pitched forward, seated, rolled with the stroke.
	var hips_rest := skeleton.get_bone_global_rest(_bones["Hips"])
	# lean_pitch is the total forward lean of the torso; a quarter goes to the
	# hips and a quarter to each of the three spine bones (they inherit, so the
	# rotations add up along the chain). The neck brings the head back up.
	var pitch := Basis(Vector3.RIGHT, lean_sign * lean_pitch * 0.25)
	var roll := Basis(Vector3.BACK, 0.05 * s)
	skeleton.set_bone_global_pose(_bones["Hips"], Transform3D(roll * pitch * hips_rest.basis, hips_pos))
	for n in ["Spine", "Spine1", "Spine2"]:
		var b: int = _bones[n]
		var cur := skeleton.get_bone_global_pose(b)
		var counter := Basis(Vector3.BACK, -0.012 * s)
		skeleton.set_bone_global_pose(b, Transform3D(counter * Basis(Vector3.RIGHT, lean_sign * lean_pitch * 0.25) * cur.basis, cur.origin))
	var neck := skeleton.get_bone_global_pose(_bones["Neck"])
	skeleton.set_bone_global_pose(_bones["Neck"], Transform3D(Basis(Vector3.RIGHT, -lean_sign * lean_pitch * 0.7) * neck.basis, neck.origin))

	# Legs: ankle sits just behind and above the pedal spindle; knees bend forward.
	_leg("Left", to_skel * (pedal_l + Vector3(0.0, 0.07, -0.06)), to_skel * (pedal_l + Vector3(0.0, 0.0, 0.12)))
	_leg("Right", to_skel * (pedal_r + Vector3(0.0, 0.07, -0.06)), to_skel * (pedal_r + Vector3(0.0, 0.0, 0.12)))
	# Arms: elbows drop outward and down.
	# Elbows out and slightly forward, like a rider covering the brakes.
	_arm("Left", to_skel * bar_l, Vector3(1.4, -0.35 - 0.12 * s, 0.25 + 0.08 * s))
	_arm("Right", to_skel * bar_r, Vector3(-1.4, -0.35 + 0.12 * s, 0.25 - 0.08 * s))
	_grip()


## Hands wrap the grips: each hand pitches down over the bar and the fingers curl.
func _grip() -> void:
	for side in ["Left", "Right"]:
		var hand: int = _bones[side + "Hand"]
		var pos := skeleton.get_bone_global_pose(hand).origin
		_aim(hand, pos, pos + Vector3(0.0, -0.55, 0.8))   # knuckles forward, fingers drop over the bar
	for i in _fingers.size():
		var joint := i % 3   # 0 knuckle, 1 middle, 2 tip
		var b := _fingers[i]
		var rest_rot := skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(b, rest_rot * Quaternion(finger_axis, finger_curl[joint]))
	for b in _thumbs:
		var rest_rot := skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(b, rest_rot * Quaternion(finger_axis, 0.35))


func _leg(side: String, ankle: Vector3, toe: Vector3) -> void:
	var up_leg: int = _bones[side + "UpLeg"]
	var leg: int = _bones[side + "Leg"]
	var foot: int = _bones[side + "Foot"]
	var hip := skeleton.get_bone_global_pose(up_leg).origin
	var knee := _two_bone(hip, ankle, _len["thigh"], _len["shin"], Vector3(0.0, 0.15, 1.0))
	_aim(up_leg, hip, knee)
	var knee_now := skeleton.get_bone_global_pose(leg).origin
	_aim(leg, knee_now, ankle)
	var ankle_now := skeleton.get_bone_global_pose(foot).origin
	_aim(foot, ankle_now, toe)


func _arm(side: String, hand: Vector3, elbow_hint: Vector3) -> void:
	var arm: int = _bones[side + "Arm"]
	var fore: int = _bones[side + "ForeArm"]
	var shoulder := skeleton.get_bone_global_pose(arm).origin
	var elbow := _two_bone(shoulder, hand, _len["upper_arm"], _len["forearm"], elbow_hint)
	_aim(arm, shoulder, elbow)
	var elbow_now := skeleton.get_bone_global_pose(fore).origin
	_aim(fore, elbow_now, hand)


## Middle joint of a two-bone chain from a to c, bending toward `hint`.
static func _two_bone(a: Vector3, c: Vector3, l1: float, l2: float, hint: Vector3) -> Vector3:
	var to := c - a
	var d := clampf(to.length(), 0.02, l1 + l2 - 0.005)
	var dir := to / maxf(to.length(), 0.0001)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang := acos(cos_a)
	# Bend plane: the hint projected perpendicular to the chain.
	var side := (hint - dir * hint.dot(dir))
	if side.length() < 0.001:
		side = Vector3.FORWARD
	side = side.normalized()
	var bent := (dir * cos(ang) + side * sin(ang)).normalized()
	return a + bent * l1


## Rotate a bone so its child direction points from `from` to `to`.
func _aim(bone: int, from: Vector3, to: Vector3) -> void:
	var cur := skeleton.get_bone_global_pose(bone)
	var local_dir: Vector3 = _child_dir.get(bone, Vector3.UP)
	var current_dir := (cur.basis * local_dir).normalized()
	var desired := (to - from).normalized()
	if desired.length() < 0.001:
		return
	var axis := current_dir.cross(desired)
	var dot := clampf(current_dir.dot(desired), -1.0, 1.0)
	var basis := cur.basis
	if axis.length() > 0.0005:
		basis = Basis(axis.normalized(), acos(dot)) * cur.basis
	elif dot < 0.0:
		basis = Basis(Vector3.UP, PI) * cur.basis
	skeleton.set_bone_global_pose(bone, Transform3D(basis, from))


## Palette shades per material so the character matches the reference rider:
## skin with painted sleeves and pants, dark hair, natural eyes.
func _restyle(character: Node) -> void:
	for mi in _meshes(character):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var mat_name := (src.resource_name if src else "").to_lower()
			var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
			var is_hair := "hair" in mat_name or "brow" in mi.name.to_lower()
			var is_eyes := "eye" in mat_name or "eye" in mi.name.to_lower()
			var shades: Array[Color] = []
			if is_hair:
				shades.assign([Color("15151c"), Color("2a2634")])
			else:
				shades.assign([Color("a87856"), Palette.RIDER_SKIN])
			var m := MeshLib.cel_material(false, shades[1], 2.0)
			if tex:
				m.set_shader_parameter("use_texture", true)
				m.set_shader_parameter("albedo_tex", tex)
				m.set_shader_parameter("colorize", not is_eyes)
				m.set_shader_parameter("shade_dark", Vector3(shades[0].r, shades[0].g, shades[0].b))
				m.set_shader_parameter("shade_light", Vector3(shades[1].r, shades[1].g, shades[1].b))
			if not is_hair and not is_eyes:
				# Long sleeves and pants: skin regions take the jersey and shorts colours.
				m.set_shader_parameter("body_zones", true)
				m.set_shader_parameter("sleeve_dark", Vector3(0.56, 0.13, 0.16))
				m.set_shader_parameter("sleeve_light", Vector3(Palette.RIDER_RED.r, Palette.RIDER_RED.g, Palette.RIDER_RED.b))
				m.set_shader_parameter("pants_dark", Vector3(0.11, 0.2, 0.44))
				m.set_shader_parameter("pants_light", Vector3(Palette.RIDER_BLUE.r, Palette.RIDER_BLUE.g, Palette.RIDER_BLUE.b))
			mi.set_surface_override_material(i, m)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null
