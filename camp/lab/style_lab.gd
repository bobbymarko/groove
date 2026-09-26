class_name StyleLab
extends Node3D
## Camp's style lab: a dusk trail slice with monster riders, for judging the
## look. Modes: "hero" (one rider side-on on the power-profile trail),
## "lineup" (the starter riders side by side), "three_quarter" (camp angle).

var mode := "hero"
var time := 0.0
var riders: Array[MonsterRider] = []
var camera: Camera3D

const SKY_TOP := Color("3a3f96")
const SKY_MID := Color("9a6cc4")
const SKY_LOW := Color("ffa27a")


func _ready() -> void:
	_environment()
	_ground()
	_dressing()
	camera = Camera3D.new()
	add_child(camera)
	match mode:
		"lineup":
			var presets := MonsterPresets.all()
			for i in presets.size():
				var r := _rider(presets[i], Vector3(-6.0 + i * 2.25, 0, 0))
				r.crank_angle = i * 1.3
			camera.fov = 30
			camera.position = Vector3(-2.6, 2.1, 10.0)
			camera.look_at(Vector3(-2.6, 0.85, 0))
		"three_quarter":
			_rider(MonsterPresets.FUZZ, Vector3.ZERO)
			camera.fov = 30
			camera.position = Vector3(3.6, 2.2, 4.2)
			camera.look_at(Vector3(0.1, 0.75, 0))
		_:
			_rider(MonsterPresets.FUZZ, Vector3.ZERO)
			camera.fov = 30
			camera.position = Vector3(1.2, 2.0, 7.4)
			camera.look_at(Vector3(1.2, 1.0, 0))
	set_time(0.0)


const PROFILE := [Vector2(-14, 0.0), Vector2(2.4, 0.0), Vector2(3.4, 0.75), Vector2(9, 0.75),
	Vector2(9.8, 0.3), Vector2(16, 0.3)]


func _rider(recipe: Dictionary, at: Vector3) -> MonsterRider:
	var r := MonsterRider.new()
	r.recipe = recipe
	# Sit on the trail and tilt with it.
	var y0 := _height(PROFILE, at.x - 0.5)
	var y1 := _height(PROFILE, at.x + 0.58)
	r.position = Vector3(at.x, (y0 + y1) * 0.5, at.z)
	r.rotation.z = atan2(y1 - y0, 1.08)
	add_child(r)
	riders.append(r)
	return r


func set_time(t: float) -> void:
	var dt := t - time
	time = t
	for r in riders:
		r.advance(dt)


# ------------------------------------------------------------------ world

func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform vec3 top : source_color;
uniform vec3 mid : source_color;
uniform vec3 low : source_color;
void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(low, mid, smoothstep(0.0, 0.10, y));
	c = mix(c, top, smoothstep(0.10, 0.32, y));
	COLOR = c;
}
"""
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("top", SKY_TOP)
	sky_mat.set_shader_parameter("mid", SKY_MID)
	sky_mat.set_shader_parameter("low", SKY_LOW)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("b39ad8")
	env.fog_density = 0.8
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 140.0
	env.fog_depth_curve = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffd2a0")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_bias = 0.6
	sun.shadow_normal_bias = 6.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.rotation_degrees = Vector3(-38, -35, 0)
	add_child(sun)


## The trail: a side-scroller strip whose height follows a workout's power.
## Flat recovery, a ramp, then an interval plateau.
func _ground() -> void:
	var profile := [Vector2(-14, 0.0), Vector2(2.4, 0.0), Vector2(3.4, 0.75), Vector2(9, 0.75),
		Vector2(9.8, 0.3), Vector2(16, 0.3)]
	var strips := [
		[-3.5, -0.75, "grass", 0.05], [-0.75, 0.75, "dirt", 0.0], [0.75, 1.35, "grass", 0.03],
	]
	var xs: Array[float] = []
	var x := -14.0
	while x <= 16.0:
		xs.append(x)
		x += 0.5
	for p in profile:
		if not xs.has(p.x):
			xs.append(p.x)
	xs.sort()
	var meshes: Dictionary = {}
	for strip in strips:
		var role: String = strip[2]
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in xs.size() - 1:
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var y0 := _height(profile, x0)
			var y1 := _height(profile, x1)
			var z0: float = strip[0]
			var z1: float = strip[1]
			var j: float = strip[3]
			var a := Vector3(x0, y0 + _jit(x0, z0, j), z0)
			var b := Vector3(x1, y1 + _jit(x1, z0, j), z0)
			var c := Vector3(x1, y1 + _jit(x1, z1, j), z1)
			var d := Vector3(x0, y0 + _jit(x0, z1, j), z1)
			tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)
			tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(d)
		meshes[role + str(strip[0])] = [tool.commit(), role]
	# The cliff face toward the camera, in two strata.
	for layer in [[0.0, 0.35, "dirt"], [0.35, 3.0, "cliff"]]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in xs.size() - 1:
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var top_off: float = layer[0]
			var bot_off: float = layer[1]
			var t0 := _height(profile, x0) - top_off
			var t1 := _height(profile, x1) - top_off
			var b0 := _height(profile, x0) - bot_off if bot_off < 1.0 else -3.0
			var b1 := _height(profile, x1) - bot_off if bot_off < 1.0 else -3.0
			var a := Vector3(x0, t0, 1.35)
			var b := Vector3(x1, t1, 1.35)
			var c := Vector3(x1, b1, 1.35 + _jit(x1, 3.0, 0.05))
			var d := Vector3(x0, b0, 1.35 + _jit(x0, 3.0, 0.05))
			tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(b)
			tool.add_vertex(a); tool.add_vertex(d); tool.add_vertex(c)
		meshes["face" + str(layer[0])] = [tool.commit(), layer[2]]
	var colours := {"grass": Color("4a8440"), "dirt": Color("7e4e34"), "cliff": Color("4a2f2e")}
	for k in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k][0]
		mi.material_override = CampLook.limb_material(colours[meshes[k][1]])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # no self-shadow acne
		add_child(mi)
	# Back field, below the trail strip, so the horizon is not a hard edge.
	var field := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 120)
	field.mesh = pm
	field.position = Vector3(0, -0.02, -63.5)
	field.material_override = CampLook.material(Color("3a5f3c"))
	add_child(field)


func _height(profile: Array, x: float) -> float:
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))
	return 0.0


func _jit(x: float, z: float, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	return (fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) - 0.5) * 2.0 * amount


func _dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Near row, just behind the trail.
	for i in 9:
		var x := -12.0 + i * 3.1 + rng.randf_range(-0.8, 0.8)
		var kind: String = ["pine_a", "pine_b", "pine_c"][rng.randi() % 3]
		_prop(kind, Vector3(x, 0, rng.randf_range(-6.5, -8.5)), rng.randf_range(0.75, 1.0), rng.randf() * TAU)
	# Mid and far forest, fading into the haze.
	for i in 34:
		var x := -30.0 + i * 1.9 + rng.randf_range(-0.6, 0.6)
		var kind: String = ["pine_a", "pine_b", "pine_c"][rng.randi() % 3]
		_prop(kind, Vector3(x, 0, rng.randf_range(-16, -24)), rng.randf_range(1.0, 1.5), rng.randf() * TAU)
	for i in 50:
		var x := -60.0 + i * 2.6 + rng.randf_range(-0.8, 0.8)
		var kind: String = ["pine_a", "pine_b", "pine_c"][rng.randi() % 3]
		_prop(kind, Vector3(x, 0, rng.randf_range(-34, -44)), rng.randf_range(1.3, 1.9), rng.randf() * TAU)
	_prop("bush_berry", Vector3(4.6, 0.75, -1.2), 1.0, 0.3)
	_prop("bush_berry", Vector3(-2.8, 0.0, -1.3), 0.8, 1.3)
	_prop("rock_a", Vector3(-4.5, 0.0, -1.6), 0.9, 0.5)
	_prop("rock_c", Vector3(7.5, 0.75, -2.4), 1.0, 2.0)
	_prop("rock_b", Vector3(1.6, 0.0, 1.1), 0.5, 1.0)
	_prop("stump", Vector3(-1.2, 0.0, -1.5), 1.0, 0.2)
	for i in 30:
		var x := -10.0 + i * 0.7 + rng.randf_range(-0.2, 0.2)
		var y := _height([Vector2(-14, 0.0), Vector2(2.4, 0.0), Vector2(3.4, 0.75), Vector2(9, 0.75), Vector2(9.8, 0.3), Vector2(16, 0.3)], x)
		_prop("grass", Vector3(x, y, rng.randf_range(0.85, 1.3)), rng.randf_range(0.8, 1.3), rng.randf() * TAU)
		_prop("grass", Vector3(x + 0.3, y, rng.randf_range(-1.4, -0.9)), rng.randf_range(0.8, 1.3), rng.randf() * TAU)
	# Mountains and clouds far back.
	_prop("mountain_c", Vector3(-22, -1, -70), 3.4, 0.4)
	_prop("mountain_a", Vector3(4, -1, -80), 3.6, 1.2)
	_prop("mountain_b", Vector3(22, -1, -66), 3.0, 2.2)
	_prop("mountain_a", Vector3(38, -1, -78), 3.0, 0.9)
	_prop("cloud", Vector3(-12, 16, -60), 2.2, 0.0)
	_prop("cloud", Vector3(14, 22, -70), 2.8, 0.0)


func _prop(kind: String, at: Vector3, s: float, rot: float) -> void:
	var n := PartKit.prop("nature", kind)
	n.position = at
	n.scale = Vector3.ONE * s
	n.rotation.y = rot
	add_child(n)
	CampLook.paint(n, {})
