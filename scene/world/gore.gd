class_name Gore
extends CPUParticles3D
## A one-shot burst of green zombie blood at the point of impact. More and
## bigger drops for bigger weapons. Frees itself when the burst is spent.

const GREEN := Color("6fd83a")
const DARK := Color("3f8a1f")


static func burst(parent: Node, at: Vector3, tier: int, away: Vector3) -> void:
	var g := Gore.new()
	g.one_shot = true
	g.explosiveness = 0.95
	g.amount = [14, 40, 80, 140][clampi(tier, 0, 3)]
	g.lifetime = 0.9
	g.local_coords = false
	g.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	g.emission_sphere_radius = 0.25
	g.direction = (away.normalized() + Vector3.UP * 0.8).normalized()
	g.spread = [45.0, 55.0, 65.0, 80.0][clampi(tier, 0, 3)]
	g.gravity = Vector3(0.0, -9.0, 0.0)
	g.initial_velocity_min = 2.0 + 1.2 * tier
	g.initial_velocity_max = 4.5 + 2.2 * tier
	g.scale_amount_min = 0.5 + 0.2 * tier
	g.scale_amount_max = 1.0 + 0.4 * tier
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	g.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	g.material_override = m
	var ramp := Gradient.new()
	ramp.set_color(0, GREEN)
	ramp.set_color(1, DARK)
	g.color_ramp = ramp
	parent.add_child(g)
	g.global_position = at
	g.emitting = true
	g.get_tree().create_timer(g.lifetime + 0.2).timeout.connect(g.queue_free)
