class_name WheelDust
extends CPUParticles3D
## Puffs kicked up behind the rear wheel: dust on dirt, spray on snow. Sits at
## the rear contact patch; emits while the bike is rolling, harder when fast.

var _base_velocity := 1.2


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


## Colour by ground: snow spray is white, dirt dust takes the trail colour.
func set_ground(snow: bool) -> void:
	var c := Palette.SNOW_BRIGHT if snow else Palette.TRAIL.lightened(0.18)
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 0.55 if snow else 0.65))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	color_ramp = g


func update(speed_mps: float) -> void:
	var rolling := speed_mps > 1.5
	if emitting != rolling:
		emitting = rolling
	var k := clampf(speed_mps / 8.0, 0.3, 1.6)
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
