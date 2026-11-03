class_name TrailWorld
extends Node3D
## Streams the side-scroller world around the rider: ground chunks built from
## the power profile, grass and rocks, forest rows behind, and a far backdrop
## of mountains and clouds that drifts with the camera.

const CHUNK := 40.0
const AHEAD := 2               ## chunks kept in front of the rider
const BEHIND := 1
const STEP := 0.5              ## metres between ground columns

var trail: PowerTrail
var _chunks: Dictionary = {}   # index -> Node3D
var _backdrop: Node3D
var _colours := {"grass": Color("4a8440"), "dirt": Color("7e4e34"), "cliff": Color("4a2f2e"),
	"cliff2": Color("3a2428")}


func setup(t: PowerTrail) -> void:
	trail = t
	_backdrop = Node3D.new()
	add_child(_backdrop)
	var far := [["mountain_c", Vector3(-30, -2, -95), 3.6], ["mountain_a", Vector3(8, -2, -110), 4.2],
		["mountain_b", Vector3(40, -2, -92), 3.2], ["mountain_a", Vector3(75, -2, -105), 3.8],
		["cloud", Vector3(-15, 22, -85), 3.0], ["cloud", Vector3(35, 28, -95), 3.6]]
	for f in far:
		var n := PartKit.prop("nature", f[0])
		n.position = f[1]
		n.scale = Vector3.ONE * float(f[2])
		_backdrop.add_child(n)
		CampLook.paint(n, {})
	var field := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 160)
	field.mesh = pm
	field.position = Vector3(0, -0.3, -82)
	field.material_override = CampLook.material(Color("3a5f3c"))
	_backdrop.add_child(field)


## Keep chunks around the rider and slide the backdrop for parallax.
func update(rider_x: float, camera_x: float) -> void:
	_backdrop.position.x = camera_x * 0.92
	var here := int(floor(rider_x / CHUNK))
	for i in range(here - BEHIND, here + AHEAD + 1):
		if i >= -1 and not _chunks.has(i) and i * CHUNK <= trail.length() + CHUNK:
			_chunks[i] = _build_chunk(i)
	for i in _chunks.keys():
		if i < here - BEHIND or i > here + AHEAD:
			(_chunks[i] as Node3D).queue_free()
			_chunks.erase(i)


func _build_chunk(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk%d" % i
	add_child(root)
	var x0 := i * CHUNK
	var xs: Array[float] = []
	var x := x0
	while x < x0 + CHUNK + 0.001:
		xs.append(x)
		x += STEP
	# Ground strips: back verge, the dirt trail, front verge.
	for strip in [[-3.6, -0.75, "grass", 0.05], [-0.75, 0.75, "dirt", 0.0], [0.75, 1.35, "grass", 0.03]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in xs.size() - 1:
			var a := xs[k]
			var b := xs[k + 1]
			var z0: float = strip[0]
			var z1: float = strip[1]
			var j: float = strip[3]
			var p0 := Vector3(a, trail.height_at(a) + _jit(a, z0, j), z0)
			var p1 := Vector3(b, trail.height_at(b) + _jit(b, z0, j), z0)
			var p2 := Vector3(b, trail.height_at(b) + _jit(b, z1, j), z1)
			var p3 := Vector3(a, trail.height_at(a) + _jit(a, z1, j), z1)
			st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
		_mesh(root, st.commit(), _colours[strip[2]])
	# The cliff face toward the camera, in two strata.
	for layer in [[0.0, 0.4, "cliff"], [0.4, 9.0, "cliff2"]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in xs.size() - 1:
			var a := xs[k]
			var b := xs[k + 1]
			var top_a := trail.height_at(a) - float(layer[0])
			var top_b := trail.height_at(b) - float(layer[0])
			var bot_a := trail.height_at(a) - float(layer[1]) if float(layer[1]) < 1.0 else -6.0
			var bot_b := trail.height_at(b) - float(layer[1]) if float(layer[1]) < 1.0 else -6.0
			var p0 := Vector3(a, top_a, 1.35)
			var p1 := Vector3(b, top_b, 1.35)
			var p2 := Vector3(b, bot_b, 1.35 + _jit(b, 3.0, 0.06))
			var p3 := Vector3(a, bot_a, 1.35 + _jit(a, 3.0, 0.06))
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p1)
			st.add_vertex(p0); st.add_vertex(p3); st.add_vertex(p2)
		_mesh(root, st.commit(), _colours[layer[2]])
	# Low plain behind the verge so plateaus read as raised ground.
	var plain := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(CHUNK, 40)
	plain.mesh = pm
	plain.position = Vector3(x0 + CHUNK * 0.5, -0.05, -23.6)
	plain.material_override = CampLook.material(Color("426f3e"))
	plain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plain)
	_dress(root, i, x0)
	return root


func _dress(root: Node3D, i: int, x0: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	for k in 26:
		var x := x0 + rng.randf() * CHUNK
		var z := rng.randf_range(0.85, 1.3) if k % 2 == 0 else rng.randf_range(-3.4, -1.2)
		_prop(root, "grass", Vector3(x, trail.height_at(x), z), rng.randf_range(0.8, 1.3), rng.randf() * TAU)
	for k in 2:
		var x := x0 + rng.randf() * CHUNK
		_prop(root, ["rock_a", "rock_b"][k], Vector3(x, trail.height_at(x), rng.randf_range(-3.2, -2.0)),
			rng.randf_range(0.5, 0.9), rng.randf() * TAU)
	# Forest: a near row behind the plateau, a far row in the haze.
	for k in 5:
		var x := x0 + (k + rng.randf()) * CHUNK / 5.0
		_prop(root, ["pine_a", "pine_b", "pine_c"][rng.randi() % 3], Vector3(x, 0, rng.randf_range(-6.5, -9.0)),
			rng.randf_range(0.8, 1.15), rng.randf() * TAU)
	for k in 9:
		var x := x0 + (k + rng.randf()) * CHUNK / 9.0
		_prop(root, ["pine_a", "pine_b", "pine_c"][rng.randi() % 3], Vector3(x, 0, rng.randf_range(-15.0, -26.0)),
			rng.randf_range(1.1, 1.7), rng.randf() * TAU)


func _prop(root: Node3D, kind: String, at: Vector3, s: float, rot: float) -> void:
	var n := PartKit.prop("nature", kind)
	n.position = at
	n.scale = Vector3.ONE * s
	n.rotation.y = rot
	root.add_child(n)
	CampLook.paint(n, {})


func _mesh(root: Node3D, m: Mesh, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = CampLook.limb_material(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _jit(x: float, z: float, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	return (fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) - 0.5) * 2.0 * amount
