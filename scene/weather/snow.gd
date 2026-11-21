class_name Snow
extends CPUParticles3D
## Falling snow around the camera, unshaded flakes with a little wind.

func _init() -> void:
	amount = 700
	lifetime = 7.0
	preprocess = 7.0
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(22.0, 9.0, 22.0)
	direction = Vector3(0.35, -1.0, 0.15)
	spread = 12.0
	gravity = Vector3(0.0, -0.9, 0.0)
	initial_velocity_min = 0.6
	initial_velocity_max = 1.4
	scale_amount_min = 0.7
	scale_amount_max = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Palette.SNOW
	material_override = m


func follow(pos: Vector3) -> void:
	global_position = pos + Vector3(0.0, 6.0, 8.0)


func set_tint(c: Color) -> void:
	(material_override as StandardMaterial3D).albedo_color = Palette.SNOW * c


## The realistic look: small soft round flakes instead of square pixels.
func soften() -> void:
	(mesh as QuadMesh).size = Vector2(0.03, 0.03)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	var m := material_override as StandardMaterial3D
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amount = 1400

