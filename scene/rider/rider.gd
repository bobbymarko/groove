class_name Rider
extends Node3D
## A blocky rider on a bike, built from primitives. Wheels and cranks turn with
## cadence, legs follow the pedals with two-bone IK, the whole thing leans in
## turns. Forward is +Z in local space.

const WHEEL_R := 0.36
const SPOKES := 8                       # each spoke crosses the hub, so 16 visible
const SPOKE := Color("2c2c36")
const CRANK_R := 0.17
const BB := Vector3(0.0, 0.34, 0.0)          # bottom bracket
const HIP := Vector3(0.0, 1.06, -0.18)
const SHOULDER := Vector3(0.0, 1.42, 0.22)
const BAR := Vector3(0.0, 1.05, 0.50)
const THIGH := 0.46
const SHIN := 0.46

var crank_angle := 0.0
var lean := 0.0              # radians, positive leans right

var _front_wheel: MeshInstance3D
var _rear_wheel: MeshInstance3D
var _crank_l: MeshInstance3D
var _crank_r: MeshInstance3D
var _pedal_l: MeshInstance3D
var _pedal_r: MeshInstance3D
var _thigh_l: MeshInstance3D
var _thigh_r: MeshInstance3D
var _shin_l: MeshInstance3D
var _shin_r: MeshInstance3D
var _body: Node3D
var _mixamo: RiderBody
var _stopped := 0.0          # 0 = feet on the pedals, 1 = one foot down on the ground
var _kick := 0.0             # 1 right after a zombie hits; the rig-Left leg lashes out and returns
const KICK_POS := Vector3(0.62, 0.55, 0.5)
var _swing := 0.0            # 1 right after a hit with a weapon; the rig-Right arm winds up and strikes
const SWING_HIGH := Vector3(-0.45, 1.65, 0.25)
const SWING_STRIKE := Vector3(-0.8, 0.95, 0.95)
var weapon_tier := 0
var _weapon: Node3D
var _headlight: SpotLight3D
const FOOT_DOWN := Vector3(0.36, 0.0, -0.02)   # rig-Left (+X) foot planted beside the bike
var _helmet: Node3D
var lean_amount := 0.75   # torso lean in radians (debug-tunable)


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	# Bike
	_rear_wheel = _wheel(Vector3(0.0, WHEEL_R, -0.55))
	# Bar light: a spot from the stem, forward and a little down. Off by day.
	_headlight = SpotLight3D.new()
	_headlight.position = Vector3(0.0, 1.03, 0.56)
	_headlight.rotation_degrees = Vector3(-9.0, 0.0, 0.0)   # -Z is forward for a light; aim slightly down
	_headlight.rotate_y(PI)                                  # the bike faces +Z
	_headlight.spot_range = 28.0
	_headlight.spot_angle = 22.0
	_headlight.spot_attenuation = 1.6
	_headlight.light_color = Color(1.0, 0.95, 0.85)
	_headlight.light_energy = 0.0
	_headlight.shadow_enabled = false
	add_child(_headlight)
	_front_wheel = _wheel(Vector3(0.0, WHEEL_R, 0.62))
	_bar(Vector3(0.0, WHEEL_R, -0.55), BB, 0.05, Palette.BIKE)                 # chainstay
	_bar(BB, Vector3(0.0, 0.95, -0.12), 0.06, Palette.BIKE)                     # seat tube
	_bar(Vector3(0.0, 0.95, -0.12), Vector3(0.0, 1.0, 0.5), 0.06, Palette.BIKE) # top tube
	_bar(BB, Vector3(0.0, 1.0, 0.5), 0.06, Palette.BIKE)                        # down tube
	_bar(Vector3(0.0, 1.0, 0.5), Vector3(0.0, WHEEL_R, 0.62), 0.05, Palette.BIKE) # fork
	_bar(Vector3(0.0, 1.0, 0.5), BAR, 0.05, Palette.BIKE)                       # stem
	_box(Vector3(0.0, 1.05, 0.56), Vector3(0.62, 0.04, 0.04), Palette.HELMET)   # handlebar
	_box(Vector3(0.0, 1.0, -0.12), Vector3(0.14, 0.05, 0.26), Palette.HELMET)   # saddle
	_crank_l = _box(BB, Vector3(0.03, CRANK_R, 0.05), Palette.HELMET)
	_crank_r = _box(BB, Vector3(0.03, CRANK_R, 0.05), Palette.HELMET)
	_pedal_l = _box(BB, Vector3(0.12, 0.03, 0.1), Palette.HELMET)
	_pedal_r = _box(BB, Vector3(0.12, 0.03, 0.1), Palette.HELMET)
	if RiderBody.available():
		_build_mixamo_body()
		return
	# Block rider fallback: torso leans forward from hips to shoulders, arms bend
	# at the elbow, round head under a domed helmet, a red pack on the back.
	_segment(HIP + Vector3(0.0, 0.02, 0.0), SHOULDER, 0.3, Palette.RIDER_RED, _body)             # torso
	_box(Vector3(0.0, 1.02, -0.14), Vector3(0.32, 0.16, 0.24), Palette.RIDER_BLUE, _body)       # hips / shorts
	_box(Vector3(0.0, 1.3, -0.1), Vector3(0.26, 0.3, 0.14), Palette.BERRY, _body)                # backpack
	var head := _sphere(SHOULDER + Vector3(0.0, 0.17, 0.06), 0.11, Palette.RIDER_SKIN, _body)  # head
	var helmet := _sphere(SHOULDER + Vector3(0.0, 0.22, 0.05), 0.13, Palette.HELMET, _body)    # helmet dome
	helmet.scale = Vector3(1.0, 0.75, 1.1)
	head.scale = Vector3(0.95, 1.0, 0.95)
	for side in [-1.0, 1.0]:
		var sh := SHOULDER + Vector3(side * 0.19, -0.02, 0.0)
		var elbow := Vector3(side * 0.24, 1.22, 0.3)
		var hand := BAR + Vector3(side * 0.26, 0.0, -0.02)
		_segment(sh, elbow, 0.09, Palette.RIDER_RED, _body)        # upper arm
		_segment(elbow, hand, 0.08, Palette.RIDER_RED, _body)      # forearm
		_box(hand, Vector3(0.09, 0.08, 0.1), Palette.HELMET, _body) # glove
	_thigh_l = _segment(HIP, HIP, 0.13, Palette.RIDER_BLUE, _body)
	_thigh_r = _segment(HIP, HIP, 0.13, Palette.RIDER_BLUE, _body)
	_shin_l = _segment(HIP, HIP, 0.1, Palette.RIDER_BLUE, _body)
	_shin_r = _segment(HIP, HIP, 0.1, Palette.RIDER_BLUE, _body)
	_update_legs()


## Rigged character on the bike, posed by IK each frame (see RiderBody).
func _build_mixamo_body() -> void:
	_mixamo = RiderBody.new()
	_mixamo.name = "RiderBody"
	_body.add_child(_mixamo)
	# Helmet intentionally omitted until a proper model exists (Bob, 2026-09-03).
	_helmet = null


func _pose_mixamo() -> void:
	if _mixamo == null or not _mixamo.is_ready():
		return
	# Rig "Left" is +X, so it takes the +X pedal and grip. When stopped that
	# foot comes off the pedal and rests on the ground.
	var pedal_px := BB + _pedal_offset(crank_angle + PI, 0.16)
	var pedal_nx := BB + _pedal_offset(crank_angle, -0.16)
	if _stopped > 0.0:
		pedal_px = pedal_px.lerp(FOOT_DOWN, smoothstep(0.0, 1.0, _stopped))
	if _kick > 0.0:
		pedal_px = pedal_px.lerp(KICK_POS, sin(PI * _kick))   # out and back
	# Palms rest on top of and slightly behind the bar so the fingers curl over the front.
	var grip_off := Vector3(0.0, 0.045, -0.035)
	var grip_nx := BAR + Vector3(-0.27, 0.0, 0.0) + grip_off
	if _swing > 0.0:
		# First half winds up high, second half sweeps down and forward, then back to the bar.
		var wind := sin(PI * clampf((_swing - 0.5) * 2.0, 0.0, 1.0))
		var strike := sin(PI * clampf(_swing * 2.0, 0.0, 1.0)) * (1.0 if _swing < 0.5 else 0.0)
		grip_nx = grip_nx.lerp(SWING_HIGH, wind).lerp(SWING_STRIKE, strike)
	_mixamo.pose(Vector3(0.0, 1.0, -0.14), lean_amount, pedal_px, pedal_nx, BAR + Vector3(0.27, 0.0, 0.0) + grip_off, grip_nx)
	if _helmet:
		var head_idx: int = _mixamo._bones.get("Head", -1)
		if head_idx >= 0:
			var head := _mixamo.skeleton.global_transform * _mixamo.skeleton.get_bone_global_pose(head_idx)
			_helmet.global_transform = Transform3D(head.basis, head.origin + head.basis.y * 0.06)


## Advance the animation: cadence in rpm, forward speed in m/s.
func animate(cadence_rpm: float, speed_mps: float, delta: float) -> void:
	crank_angle = fmod(crank_angle + cadence_rpm / 60.0 * TAU * delta, TAU)
	_kick = move_toward(_kick, 0.0, delta * 2.4)
	if _mixamo:
		_mixamo.sway_phase = crank_angle
		# Sway fades out as the pedalling stops rather than freezing mid-rock.
		_mixamo.sway_amount = move_toward(_mixamo.sway_amount, 1.0 if cadence_rpm > 5.0 else 0.0, delta * 2.0)
	_swing = move_toward(_swing, 0.0, delta * 2.0)
	var standing := cadence_rpm < 5.0 and speed_mps < 0.3
	_stopped = move_toward(_stopped, 1.0 if standing else 0.0, delta * 2.5)
	var wheel_delta := speed_mps / WHEEL_R * delta
	_front_wheel.rotate_x(-wheel_delta)
	_rear_wheel.rotate_x(-wheel_delta)
	if _mixamo:
		_update_cranks()
		_pose_mixamo()
	else:
		_update_legs()
	# Rider and bike lean together so hands stay on the grips through turns.
	rotation.z = lerpf(rotation.z, -lean, clampf(delta * 3.0, 0.0, 1.0))


## Pedal position relative to the bottom bracket: angle 0 is top dead centre and
## the pedal moves forward (+Z) then down as the angle grows, i.e. forward pedalling.
static func _pedal_offset(a: float, side_x: float) -> Vector3:
	return Vector3(side_x, cos(a) * CRANK_R, sin(a) * CRANK_R)


func _update_cranks() -> void:
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var a := crank_angle + (0.0 if side_i == 0 else PI)
		var pedal := BB + _pedal_offset(a, side * 0.16)
		var crank := _crank_l if side_i == 0 else _crank_r
		crank.position = BB + _pedal_offset(a, side * 0.1) * 0.5 + Vector3(side * 0.05, 0.0, 0.0)
		crank.rotation = Vector3(a, 0.0, 0.0)   # box Y axis follows (cos a, sin a) in the Y-Z plane
		var pedal_mesh := _pedal_l if side_i == 0 else _pedal_r
		pedal_mesh.position = pedal


func _update_legs() -> void:
	_update_cranks()
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var a := crank_angle + (0.0 if side_i == 0 else PI)
		var pedal := BB + _pedal_offset(a, side * 0.16)
		var hip := HIP + Vector3(side * 0.14, 0.0, 0.0)
		var knee := _knee(hip, pedal)
		_place(_thigh_l if side_i == 0 else _thigh_r, hip, knee)
		_place(_shin_l if side_i == 0 else _shin_r, knee, pedal)


## Two-bone IK in the sagittal plane; the knee bends forward (+Z).
func _knee(hip: Vector3, foot: Vector3) -> Vector3:
	var to := foot - hip
	var d := clampf(to.length(), 0.05, THIGH + SHIN - 0.01)
	var dir := to.normalized()
	var cos_a := clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0)
	var ang := acos(cos_a)
	var side_axis := Vector3.RIGHT if hip.x < 0.0 else Vector3.LEFT
	var bent := dir.rotated(side_axis, -ang) if dir.rotated(side_axis, -ang).z > dir.rotated(side_axis, ang).z else dir.rotated(side_axis, ang)
	return hip + bent * THIGH


func _place(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var len := maxf(a.distance_to(b), 0.01)
	seg.position = mid
	seg.scale = Vector3(1.0, len, 1.0)
	var up := (b - a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var fwd := right.cross(up).normalized()
	seg.basis = Basis(right, up, fwd) * Basis().scaled(Vector3(1.0, len, 1.0))


func _wheel(pos: Vector3) -> MeshInstance3D:
	# Fat-bike tyre: a torus about 12 cm wide (4.7 in) on a 26-inch rim.
	var mi := MeshInstance3D.new()
	var tyre := TorusMesh.new()
	tyre.inner_radius = WHEEL_R - 0.115
	tyre.outer_radius = WHEEL_R
	tyre.rings = 20
	tyre.ring_segments = 10
	mi.mesh = tyre
	mi.material_override = MeshLib.cel_material(false, Palette.TIRE)
	mi.position = pos
	mi.rotation = Vector3(0.0, 0.0, PI * 0.5)   # torus axis (Y) becomes the axle (X)
	# Hub and spokes so rotation reads. Always dark, whatever the scene palette.
	var dark := MeshLib.cel_material(false, SPOKE)
	var hub := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.045
	cyl.height = 0.1
	cyl.radial_segments = 8
	hub.mesh = cyl
	hub.material_override = dark
	mi.add_child(hub)
	var spoke := BoxMesh.new()
	spoke.size = Vector3((WHEEL_R - 0.09) * 2.0, 0.012, 0.012)
	for i in SPOKES:
		var s := MeshInstance3D.new()
		s.mesh = spoke
		s.material_override = dark
		s.rotation = Vector3(0.0, PI * float(i) / SPOKES, 0.0)   # spokes lie in the wheel plane (local XZ)
		mi.add_child(s)
	add_child(mi)
	return mi


func _bar(a: Vector3, b: Vector3, thickness: float, col: Color) -> MeshInstance3D:
	return _segment(a, b, thickness, col, self)


func _segment(a: Vector3, b: Vector3, thickness: float, col: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, 1.0, thickness)
	mi.mesh = box
	mi.material_override = MeshLib.cel_material(false, col)
	parent.add_child(mi)
	_place(mi, a, b)
	return mi


func _sphere(center: Vector3, radius: float, col: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = radius
	sp.height = radius * 2.0
	sp.radial_segments = 8
	sp.rings = 5
	mi.mesh = sp
	mi.material_override = MeshLib.cel_material(false, col)
	mi.position = center
	parent.add_child(mi)
	return mi


func _box(center: Vector3, size: Vector3, col: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = MeshLib.cel_material(false, col)
	mi.position = center
	parent.add_child(mi)
	return mi


## 0 = off (daylight), 1 = full beam (night).
func set_headlight(k: float) -> void:
	_headlight.light_energy = 1.1 * clampf(k, 0.0, 1.0)
	_headlight.visible = k > 0.01


## A zombie just made contact: boot it, or swing whatever is in hand.
func attack() -> void:
	if weapon_tier > 0:
		_swing = 1.0
	else:
		_kick = 1.0


func kick() -> void:
	_kick = 1.0


## Put a weapon in the rig-Right hand (the -X grip). Tier 0 clears it.
func set_weapon(tier: int) -> void:
	weapon_tier = tier
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	if tier <= 0 or _mixamo == null or not _mixamo.is_ready():
		return
	var hand: int = _mixamo._bones.get("RightHand", -1)
	if hand < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = _mixamo.skeleton.get_bone_name(hand)
	_mixamo.skeleton.add_child(att)
	var w := Weapon.build(tier)
	w.position = Vector3(0.0, 0.05, 0.0)      # handle in the palm; the business end runs out past the fingers
	w.rotation_degrees = Vector3(0.0, 0.0, 0.0)  # bone +Y is the finger direction
	att.add_child(w)
	_weapon = att
