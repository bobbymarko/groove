class_name RealRain
extends Node3D
## Rain for the realistic look. Streaks fall on the graphics card, stretched
## along their motion, and burst into droplets where they hit the ground (a
## height field of the scene around the camera). The world gets wet as a shower
## sets in and dries slowly after it: the `rain_wet` shader global darkens and
## glosses the ground and plants and fills puddles in the trail.

const DROPS := 14000
const WET_IN := 1.0 / 20.0      ## wetness per second as rain arrives
const DRY_OUT := 1.0 / 120.0    ## and as it dries

var _streaks: GPUParticles3D
var _splash: GPUParticles3D
var _field: GPUParticlesCollisionHeightField3D
var _drop_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _intensity := 0.0
var _wet := 0.0
var _light := 1.0


func _ready() -> void:
	var shader := load("res://scene/real/rain_drop.gdshader") as Shader
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = shader
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = shader
	_splash_mat.set_shader_parameter("opacity", 0.45)

	_splash = GPUParticles3D.new()
	_splash.amount = 4000
	_splash.lifetime = 0.3
	_splash.local_coords = false
	_splash.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_splash.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3.UP
	sp.spread = 55.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.6
	sp.gravity = Vector3(0.0, -9.8, 0.0)
	sp.scale_min = 0.5
	sp.scale_max = 1.2
	_splash.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.012, 0.05)
	sq.material = _splash_mat
	_splash.draw_pass_1 = sq
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)

	_streaks = GPUParticles3D.new()
	_streaks.amount = DROPS
	_streaks.lifetime = 1.4
	_streaks.preprocess = 1.4
	_streaks.local_coords = false
	_streaks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_streaks.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_streaks.collision_base_size = 0.02
	_streaks.amount_ratio = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 1.5, 16.0)
	pm.direction = Vector3(0.08, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 8.5
	pm.initial_velocity_max = 10.5
	pm.gravity = Vector3(0.0, -2.0, 0.0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 3
	_streaks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.7)
	q.material = _drop_mat
	_streaks.draw_pass_1 = q
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_streaks)
	_streaks.sub_emitter = _streaks.get_path_to(_splash)

	_field = GPUParticlesCollisionHeightField3D.new()
	_field.size = Vector3(44.0, 40.0, 44.0)
	_field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	_field.follow_camera_enabled = true
	add_child(_field)
	set_intensity(0.0)


## 0..1: how hard it rains.
func set_intensity(k: float) -> void:
	_intensity = clampf(k, 0.0, 1.0)
	if _streaks:
		_streaks.emitting = _intensity > 0.02
		_streaks.amount_ratio = _intensity


## How bright the light is (1 by day, low at night), so drops never glow in the dark.
func set_light(k: float) -> void:
	_light = k
	var c := Color(0.72, 0.77, 0.85) * lerpf(0.12, 1.0, clampf(k, 0.0, 1.0))
	_drop_mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	_splash_mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))


## Every frame: keep the rain around and ahead of the eye, wet or dry the world.
func follow(cam: Camera3D, delta: float) -> void:
	var ahead := -cam.global_transform.basis.z
	ahead.y = 0.0
	_streaks.global_position = cam.global_position + ahead.normalized() * 8.0 + Vector3.UP * 11.0
	_wet = move_toward(_wet, _intensity, delta * (WET_IN if _intensity > _wet else DRY_OUT))
	RenderingServer.global_shader_parameter_set("rain_wet", _wet)


func wetness() -> float:
	return _wet


## Tooling: start already soaked.
func soak(k: float) -> void:
	_wet = k

