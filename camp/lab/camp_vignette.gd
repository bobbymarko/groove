class_name CampVignette
extends Node3D
## The camp between rides: your van, a fire, a chair, the events signpost,
## the trading post, and your friends' vans parked nearby.

const SIGN_FONT := preload("res://assets/fonts/PixelOperator-Bold.ttf")

## Van paints: yours and two friends'.
const PAINTS := [
	{"paint": Color("5d8a62"), "paint2": Color("efe6cf")},
	{"paint": Color("2f8f9a"), "paint2": Color("f2eadb")},
	{"paint": Color("d69a2a"), "paint2": Color("f4ecdc")},
]
const EVENTS := ["GRAVEL 200  JUN", "HILL CLIMB  AUG", "CX SEASON  OCT"]

var _flames: Array[Node3D] = []
var _fire_light: OmniLight3D
var _people: Array[MonsterStand] = []
var _t := 0.0


func _ready() -> void:
	_ground()
	# Your van, door open to the fire.
	_van(Vector3(-0.8, 0, -2.3), 0.0, PAINTS[0], true)
	# Friends parked nearby.
	_van(Vector3(-8.2, 0, -6.2), deg_to_rad(28), PAINTS[1], false)
	_van(Vector3(2.8, 0, -9.0), deg_to_rad(-12), PAINTS[2], false)
	_fire(Vector3(0.3, 0, 1.9))
	# You, by the fire, mug in hand.
	var chair_at := Vector3(-2.1, 0, 1.0)
	var yaw := _yaw_to(chair_at, Vector3(0.3, 0, 1.9))
	_prop("camp", "camp_chair", chair_at, yaw)
	var me := _sitter(MonsterPresets.FUZZ, chair_at, yaw)
	me.hold = Vector3(0.36, 0.78, 0.0)
	var mug := PartKit.prop("camp", "mug")
	mug.position = me.hold + Vector3(0.0, -0.04, 0.0)
	me.add_child(mug)
	CampLook.paint(mug, {})
	var empty_at := Vector3(2.4, 0, 1.3)
	_prop("camp", "camp_chair", empty_at, _yaw_to(empty_at, Vector3(0.3, 0, 1.9)))
	_prop("camp", "lantern", Vector3(-2.75, 0, 0.55), 0.3)
	_light(Vector3(-2.75, 0.4, 0.55), Color("ffc070"), 0.8, 2.2)
	_prop("nature", "stump", Vector3(1.2, 0, 3.6), 0.4)
	# Parked bike, leaning on the van.
	var bike := MonsterRider.new()
	bike.recipe = {"bike": MonsterPresets.FUZZ.bike}
	bike.position = Vector3(-3.0, 0, -1.12)
	bike.rotation = Vector3(-0.10, 0, 0)
	add_child(bike)
	# What you're training for.
	var post := PartKit.part("camp", "signpost")
	post.node.position = Vector3(2.1, 0, -1.0)
	add_child(post.node)
	CampLook.paint(post.node, {})
	for i in 3:
		var t: Transform3D = post.sockets["board_%d" % i]
		_text(post.node, EVENTS[i], t.origin + Vector3(0, 0, 0.005), 0.0019, Color("3a2418"))
	_trading_post(Vector3(6.2, 0, -1.6), deg_to_rad(-22))
	_prop("camp", "crate_berries", Vector3(4.6, 0, -0.4), 0.3)
	_prop("camp", "crate_berries", Vector3(4.9, 0, 0.2), -0.2)
	_dressing()


func advance(dt: float) -> void:
	_t += dt
	for i in _flames.size():
		var f := _flames[i]
		var k := 1.0 + 0.16 * sin(_t * (9.0 + i * 2.3) + i) + 0.08 * sin(_t * 23.0 + i * 3.0)
		var b: float = f.get_meta("base", 1.0)
		f.scale = Vector3(1.0 - (k - 1.0) * 0.4, k, 1.0 - (k - 1.0) * 0.4) * b
		f.rotation.y = _t * (0.8 + i * 0.5)
	if _fire_light:
		_fire_light.light_energy = 2.4 + 0.35 * sin(_t * 11.0) + 0.2 * sin(_t * 27.0)
	for p in _people:
		p.advance(dt)


# ------------------------------------------------------------------ pieces

func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.z, d.x)


func _prop(file: String, part: String, at: Vector3, yaw: float, s := 1.0, colours := {}) -> Node3D:
	var n := PartKit.prop(file, part)
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	add_child(n)
	CampLook.paint(n, colours)
	return n


func _van(at: Vector3, yaw: float, paint: Dictionary, lamp: bool) -> void:
	var v := PartKit.part("camp", "van")
	v.node.position = at
	v.node.rotation.y = yaw
	add_child(v.node)
	CampLook.paint(v.node, paint)
	if lamp:
		var t: Transform3D = v.sockets["lamp"]
		_light(v.node.transform * t.origin, Color("ffb866"), 1.4, 3.0)


func _sitter(recipe: Dictionary, at: Vector3, yaw: float) -> MonsterStand:
	var m := MonsterStand.new()
	m.recipe = recipe
	m.stance = MonsterStand.Stance.SIT
	m.position = at
	m.rotation.y = yaw
	add_child(m)
	_people.append(m)
	return m


func _fire(at: Vector3) -> void:
	_prop("camp", "fire_ring", at, 0.0)
	# A cluster of tongues rather than one cone: a big one in the middle,
	# smaller ones leaning out, a bright core.
	var tongues := [["flame_outer", Vector3.ZERO, 0.85], ["flame_mid", Vector3(0.14, 0, 0.05), 0.9],
		["flame_mid", Vector3(-0.10, 0, 0.12), 0.75], ["flame_mid", Vector3(-0.04, 0, -0.14), 0.8],
		["flame_core", Vector3(0.02, 0, 0.0), 1.1]]
	for t in tongues:
		var f := _prop("camp", str(t[0]), at + t[1] + Vector3(0, 0.02, 0), 0.0, float(t[2]))
		f.rotation.z = (t[1] as Vector3).x * 1.5
		f.rotation.x = -(t[1] as Vector3).z * 1.5
		f.set_meta("base", float(t[2]))
		_flames.append(f)
	_fire_light = _light(at + Vector3(0, 0.9, 0), Color("ff8a3a"), 2.4, 7.0)


func _light(at: Vector3, c: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = c
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	add_child(l)
	return l


func _text(parent: Node3D, s: String, at: Vector3, px: float, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = SIGN_FONT
	l.font_size = 64
	l.outline_size = 0
	l.pixel_size = px
	l.modulate = c
	l.position = at
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	parent.add_child(l)
	return l


func _trading_post(at: Vector3, yaw: float) -> void:
	var tp := PartKit.part("camp", "trading_post")
	tp.node.position = at
	tp.node.rotation.y = yaw
	add_child(tp.node)
	CampLook.paint(tp.node, {})
	var sign_at: Vector3 = (tp.sockets["sign"] as Transform3D).origin
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.3, 0.05)
	board.mesh = bm
	board.position = sign_at + Vector3(0, 0.05, 0.02)
	board.material_override = CampLook.material(CampLook.ROLES.wood_dark)
	tp.node.add_child(board)
	_text(tp.node, "TRADING POST", sign_at + Vector3(0, 0.05, 0.05), 0.0032, Color("f4e6c4"))
	var trader := MonsterStand.new()
	trader.recipe = MonsterPresets.TRADER
	trader.stance = MonsterStand.Stance.COUNTER
	var counter: Vector3 = (tp.sockets["counter"] as Transform3D).origin
	var spot: Vector3 = (tp.sockets["trader"] as Transform3D).origin
	# The trader faces the customer side (+Z in the stall's frame).
	trader.position = spot
	trader.rotation.y = -PI / 2
	var local_counter := Vector3(spot.z - counter.z, counter.y, 0.0)
	trader.counter = local_counter
	tp.node.add_child(trader)
	_people.append(trader)


# ------------------------------------------------------------------ land

func _ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 56
	var cell := 1.25
	var h := func(x: float, z: float) -> float:
		var r := Vector2(x, z).length()
		var k := clampf((r - 6.0) / 6.0, 0.0, 1.0)
		return (sin(x * 1.7 + z * 0.9) * 0.5 + sin(x * 0.6 - z * 1.3) * 0.5) * 0.12 * k + k * k * 0.25
	for i in n:
		for j in n:
			var x0 := (i - n / 2) * cell
			var z0 := (j - n / 2) * cell
			var a := Vector3(x0, h.call(x0, z0), z0)
			var b := Vector3(x0 + cell, h.call(x0 + cell, z0), z0)
			var c := Vector3(x0 + cell, h.call(x0 + cell, z0 + cell), z0 + cell)
			var d := Vector3(x0, h.call(x0, z0 + cell), z0 + cell)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = CampLook.limb_material(Color("4c8442"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# The trodden clearing around the fire.
	var cl := SurfaceTool.new()
	cl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.0, 0.02, 0.6)
	var pts := 28
	var radius := func(k: int) -> float:
		var kk := k % pts
		return 4.0 + sin(kk * 2.7) * 0.45 + sin(kk * 1.3) * 0.35
	for k in pts:
		var a0 := TAU * k / pts
		var a1 := TAU * (k + 1) / pts
		var r0: float = radius.call(k)
		var r1: float = radius.call(k + 1)
		cl.add_vertex(centre)
		cl.add_vertex(centre + Vector3(cos(a1) * r1 * 1.25, 0, sin(a1) * r1 * 0.85))
		cl.add_vertex(centre + Vector3(cos(a0) * r0 * 1.25, 0, sin(a0) * r0 * 0.85))
	var cm := MeshInstance3D.new()
	cm.mesh = cl.commit()
	cm.material_override = CampLook.limb_material(Color("6e5440"))
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cm)


func _dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var placed := 0
	while placed < 90:
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, 34.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r * 0.9 - 4.0)
		if p.z > 5.0 and absf(p.x) < 14.0:
			continue          # keep the view to camp open
		var kind: String = ["pine_a", "pine_b", "pine_c"][rng.randi() % 3]
		_prop("nature", kind, p + Vector3(0, 0.2, 0), rng.randf() * TAU, rng.randf_range(1.0, 1.6))
		placed += 1
	for spot in [Vector3(-5.0, 0, 2.8), Vector3(4.2, 0, 4.2), Vector3(-6.4, 0, -1.5), Vector3(8.8, 0, 1.5)]:
		_prop("nature", "bush_berry", spot, rng.randf() * TAU, rng.randf_range(0.8, 1.1))
	for spot in [Vector3(-4.2, 0, 4.6), Vector3(6.5, 0, 3.5), Vector3(-9.0, 0, 0.5)]:
		_prop("nature", "rock_a", spot, rng.randf() * TAU, rng.randf_range(0.7, 1.2))
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.8, 11.0)
		_prop("nature", "grass", Vector3(cos(a) * r * 1.2, 0.02, sin(a) * r * 0.8 + 0.6), rng.randf() * TAU, rng.randf_range(0.9, 1.4))
	_prop("nature", "mountain_c", Vector3(-30, -1, -90), 0.0, 3.6)
	_prop("nature", "mountain_a", Vector3(10, -1, -100), 1.1, 4.0)
	_prop("nature", "mountain_b", Vector3(40, -1, -85), 2.0, 3.2)
	_prop("nature", "cloud", Vector3(-20, 22, -80), 0.0, 3.0)
	_prop("nature", "cloud", Vector3(25, 28, -90), 0.0, 3.4)
