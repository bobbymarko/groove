class_name Rain
extends CPUParticles3D
## Rain streaks around the camera. Intensity 0..1 sets how much falls.

func _init() -> void:
	emitting = false
	amount = 900
	lifetime = 1.1
	preprocess = 1.1
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(18.0, 8.0, 18.0)
	direction = Vector3(0.12, -1.0, 0.05)
	spread = 3.0
	gravity = Vector3.ZERO
	initial_velocity_min = 13.0
	initial_velocity_max = 17.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.42)
	mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	material_override = m
	color = Color(0.78, 0.84, 0.95, 0.0)


func set_intensity(k: float) -> void:
	var on := k > 0.02
	if emitting != on:
		emitting = on
	color = Color(0.78, 0.84, 0.95, 0.5 * clampf(k, 0.0, 1.0))


func follow(pos: Vector3) -> void:
	global_position = pos + Vector3(0.0, 7.0, 6.0)
