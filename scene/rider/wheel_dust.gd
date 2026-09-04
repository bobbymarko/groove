class_name WheelDust
extends CPUParticles3D
## Puffs kicked up behind the rear wheel: dust on dirt, spray on snow. Sits at
## the rear contact patch; emits while the bike is rolling, harder when fast.

var _snow := false


func _init() -> void:
	emitting = false
	amount = 48
	lifetime = 1.1
	local_coords = false                      # puffs stay where they were kicked up
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.06
	direction = Vector3(0.0, 0.7, -1.0)       # up and back
	spread = 28.0
	gravity = Vector3(0.0, 0.25, 0.0)         # drifts up a little as it thins
	initial_velocity_min = 0.6
	initial_velocity_max = 1.4
	damping_min = 0.6
	damping_max = 1.0
	scale_amount_min = 0.5
	scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	scale_amount_curve = grow
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_disc()
	material_override = m
	amount = 30
	emission_sphere_radius = 0.1
	spread = 40.0


## Ground type: dirt hangs as a drifting dust cloud; snow is thrown up as small
## clumps that arc back and fall straight down.
## `dark`: ash and soot hang darker than the ground (Apocalypse) instead of lighter.
func set_ground(snow: bool, dark := false) -> void:
	var c := Palette.SNOW_BRIGHT if snow else (Palette.TRAIL_DARK.darkened(0.35) if dark else Palette.TRAIL.lightened(0.18))
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 0.9 if snow else 0.65))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0 if not snow else 0.6))
	color_ramp = g
	_snow = snow
	var grow := Curve.new()
	if snow:
		amount = 44
		lifetime = 0.55
		direction = Vector3(0.0, 0.9, -0.8)
		spread = 22.0
		gravity = Vector3(0.0, -6.0, 0.0)
		damping_min = 0.0
		damping_max = 0.2
		scale_amount_min = 0.18
		scale_amount_max = 0.42
		grow.add_point(Vector2(0.0, 1.0))
		grow.add_point(Vector2(1.0, 0.8))
	else:
		amount = 30
		lifetime = 1.1
		direction = Vector3(0.0, 0.7, -1.0)
		spread = 40.0
		gravity = Vector3(0.0, 0.25, 0.0)
		damping_min = 0.6
		damping_max = 1.0
		scale_amount_min = 0.5
		scale_amount_max = 1.0
		grow.add_point(Vector2(0.0, 0.4))
		grow.add_point(Vector2(1.0, 1.6))
	scale_amount_curve = grow


## `wet` is the rain intensity 0..1: damp ground gives less dust, a real
## shower none. Snow spray is unaffected.
func update(speed_mps: float, wet := 0.0) -> void:
	var damp := 1.0 if _snow else clampf(1.0 - wet / 0.45, 0.0, 1.0)   # gone by a moderate shower
	var rolling := speed_mps > 1.5 and damp > 0.05
	if emitting != rolling:
		emitting = rolling
	color = Color(1.0, 1.0, 1.0, damp)   # fewer visible puffs as the ground gets wet
	var k := clampf(speed_mps / 8.0, 0.3, 1.6)
	if _snow:
		initial_velocity_min = 1.6 * k
		initial_velocity_max = 3.0 * k
	else:
		initial_velocity_min = 0.6 * k
		initial_velocity_max = 1.4 * k


## A blurry white disc so puffs have no edges.
static func _soft_disc() -> Texture2D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
