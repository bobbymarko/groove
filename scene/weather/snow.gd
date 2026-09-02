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
