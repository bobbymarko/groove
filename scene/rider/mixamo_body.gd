class_name MixamoBody
extends Node3D
## A Mixamo-rigged character posed on the bike by inverse kinematics every
## frame: hips on the saddle, spine leaned to the bars, feet following the
## pedals, hands on the grips. Works in the parent Rider's local space
## (+Z forward, Y up). Bone names follow Mixamo's rig after Godot import
## (colons become underscores).

const SCENE_PATH := "res://assets/mixamo/Ch42_nonPBR.fbx"

var skeleton: Skeleton3D
var _bones: Dictionary = {}          # short name -> index
var _child_dir: Dictionary = {}      # bone index -> unit vector to its child in bone-local rest space
var _len: Dictionary = {}            # "thigh_l", "shin_l", "upper_arm_l", "forearm_l", ... in metres
var _hip_offset_l: Vector3           # hip joint relative to the Hips bone origin, skeleton rest space
var _hip_offset_r: Vector3
var _ready_ok := false
var lean_sign := 1.0   # positive rotation about X tilts the spine toward +Z (forward)


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
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
			"RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
			"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
		var idx := skeleton.find_bone("mixamorig_" + n)
		if idx < 0:
			idx = skeleton.find_bone("mixamorig:" + n)
		_bones[n] = idx
	for pair in [["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["LeftFoot", "LeftToeBase"],
			["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"], ["RightFoot", "RightToeBase"],
			["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"],
			["Spine", "Spine1"], ["Spine1", "Spine2"], ["Spine2", "Neck"], ["Neck", "Head"]]:
		var b: int = _bones[pair[0]]
		var c: int = _bones[pair[1]]
		_child_dir[b] = skeleton.get_bone_rest(c).origin.normalized()
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
	var hips_pos: Vector3 = to_skel * saddle
	# Every frame starts from the rest pose; all rotations below are absolute.
	skeleton.reset_bone_poses()
	# Hips: rest orientation pitched forward, seated.
	var hips_rest := skeleton.get_bone_global_rest(_bones["Hips"])
	# lean_pitch is the total forward lean of the torso; a quarter goes to the
	# hips and a quarter to each of the three spine bones (they inherit, so the
	# rotations add up along the chain). The neck brings the head back up.
	var pitch := Basis(Vector3.RIGHT, lean_sign * lean_pitch * 0.25)
	skeleton.set_bone_global_pose(_bones["Hips"], Transform3D(pitch * hips_rest.basis, hips_pos))
	for n in ["Spine", "Spine1", "Spine2"]:
		var b: int = _bones[n]
		var cur := skeleton.get_bone_global_pose(b)
		skeleton.set_bone_global_pose(b, Transform3D(Basis(Vector3.RIGHT, lean_sign * lean_pitch * 0.25) * cur.basis, cur.origin))
	var neck := skeleton.get_bone_global_pose(_bones["Neck"])
	skeleton.set_bone_global_pose(_bones["Neck"], Transform3D(Basis(Vector3.RIGHT, -lean_sign * lean_pitch * 0.7) * neck.basis, neck.origin))

	# Legs: ankle sits just behind and above the pedal spindle; knees bend forward.
	_leg("Left", to_skel * (pedal_l + Vector3(0.0, 0.07, -0.06)), to_skel * (pedal_l + Vector3(0.0, 0.0, 0.12)))
	_leg("Right", to_skel * (pedal_r + Vector3(0.0, 0.07, -0.06)), to_skel * (pedal_r + Vector3(0.0, 0.0, 0.12)))
	# Arms: elbows drop outward and down.
	# Elbows out and slightly forward, like a rider covering the brakes.
	_arm("Left", to_skel * bar_l, Vector3(1.4, -0.35, 0.25))
	_arm("Right", to_skel * bar_r, Vector3(-1.4, -0.35, 0.25))


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


## Palette shades per mesh so the character matches the reference rider.
func _restyle(character: Node) -> void:
	for mi in _meshes(character):
		var n := mi.name.to_lower()
		var shades: Array[Color]
		var snow := 2.0
		if "shirt" in n:
			shades = [Color("8f2028"), Palette.RIDER_RED]
		elif "short" in n or "pant" in n:
			shades = [Color("1c3270"), Palette.RIDER_BLUE]
		elif "sneaker" in n or "shoe" in n or "boot" in n:
			shades = [Color("15151c"), Palette.HELMET]
		elif "hair" in n or "eyelash" in n:
			shades = [Color("15151c"), Color("2a2634")]
		else:
			shades = [Color("a87856"), Palette.RIDER_SKIN]
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
			var m := MeshLib.cel_material(false, shades[1], snow)
			if tex:
				m.set_shader_parameter("use_texture", true)
				m.set_shader_parameter("albedo_tex", tex)
				m.set_shader_parameter("colorize", true)
				m.set_shader_parameter("shade_dark", Vector3(shades[0].r, shades[0].g, shades[0].b))
				m.set_shader_parameter("shade_light", Vector3(shades[1].r, shades[1].g, shades[1].b))
			mi.set_surface_override_material(i, m)
		if "eyelash" in n:
			mi.visible = false


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
