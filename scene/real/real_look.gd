class_name RealLook
extends Node
## The realistic look (look_mode "real"): Cloudscape's sky and clouds, a
## physically lit environment (soft sun shadows, ambient light from the sky,
## ambient occlusion, bloom, volumetric light shafts, filmic tone mapping) and
## the daylight cycle mapped onto it. RideScene owns the nodes; this sets them up
## and feeds the sky every frame.

const SUN_ENERGY := 1.15
const MOON_ENERGY := 0.22
const WIND_KMPS := 0.008          ## cloud drift, km per second

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var _wind := Vector3.ZERO
var _frame := 0
var _preset: Dictionary = {}

## Ground colour seen by the sky (light bounced up into clouds and ambient), per ground type.
const GROUND_ALBEDO := {
	"snow": Color(0.8, 0.82, 0.86),
	"grass": Color(0.16, 0.2, 0.1),
	"sand": Color(0.55, 0.45, 0.32),
}


func setup(e: Environment, s: DirectionalLight3D, viewport: SubViewport, preset: Dictionary) -> void:
	env = e
	sun = s
	_preset = preset
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://scene/real/real_sky.gdshader")
	sky_mat.set_shader_parameter("ground_albedo", ground_albedo())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.85
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.15
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.5
	sun.light_volumetric_fog_energy = 1.0
	# Rendered below native resolution and brought up by a temporal upscaler
	# (MetalFX on Macs, FSR 2 elsewhere), which also antialiases and settles the
	# sky's jittered clouds.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if OS.get_name() == "macOS" else Viewport.SCALING_3D_MODE_FSR2
	viewport.scaling_3d_scale = 0.6
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var noise := CloudNoise.new()
	noise.baked.connect(_on_noise)
	add_child(noise)


func ground_type() -> String:
	return str(_preset.get("real_ground", "snow" if bool(_preset.get("snow", true)) else "grass"))


func ground_albedo() -> Color:
	return GROUND_ALBEDO.get(ground_type(), Color(0.3, 0.3, 0.3))


func _on_noise() -> void:
	sky_mat.set_shader_parameter("shape_tex", CloudNoise.shape)
	sky_mat.set_shader_parameter("detail_tex", CloudNoise.detail)
	sky_mat.set_shader_parameter("weather_tex", CloudNoise.weather)
	sky_mat.set_shader_parameter("curl_tex", CloudNoise.curl)


## Sun or moon for this moment of the world day (Daylight.state), rain greying it over.
func apply_daylight(st: Dictionary, rain: float) -> void:
	var night := bool(st.is_night)
	var daylight := float(st.daylight)
	var dir := sun.global_transform.basis.z.normalized()   # toward the light
	sky_mat.set_shader_parameter("light_dir", dir)
	sky_mat.set_shader_parameter("sun_disk", 0.0 if night else 1.0)
	sky_mat.set_shader_parameter("stars", clampf(1.0 - daylight * 1.5, 0.0, 1.0) * (1.0 - rain))
	var illum := Vector3.ONE * (0.012 if night else 1.0)
	sky_mat.set_shader_parameter("light_illum", illum)
	sky_mat.set_shader_parameter("coverage", lerpf(float(_preset.get("real_clouds", 0.5)), 0.95, rain))
	sky_mat.set_shader_parameter("cloud_type", lerpf(1.0, 0.25, rain))
	sky_mat.set_shader_parameter("cloud_density", lerpf(0.19, 0.5, rain))
	sky_mat.set_shader_parameter("haze", 0.78 + 2.0 * rain)
	# The light's own colour comes from the air it crosses: warm and weak near the horizon.
	var elev := deg_to_rad(maxf(float(st.elev), 0.5))
	var air := clampf(sin(elev) * 3.0, 0.0, 1.0)
	var warm := Color(1.0, 0.55 + 0.4 * air, 0.3 + 0.62 * air)
	if night:
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = MOON_ENERGY * float(st.energy_mult) / 0.3
	else:
		sun.light_color = warm
		sun.light_energy = SUN_ENERGY * smoothstep(-0.02, 0.12, sin(elev)) * (1.0 - 0.75 * rain)
	env.ambient_light_energy = lerpf(0.6, 1.0, daylight)
	env.fog_density = 0.0005 + 0.006 * rain
	env.volumetric_fog_density = 0.0012 + 0.01 * rain


## Every frame: where the eye is, how far the clouds have drifted, the TAA jitter.
func update(cam_pos: Vector3, delta: float) -> void:
	_wind += Vector3(1.0, 0.0, 0.35).normalized() * WIND_KMPS * delta
	_frame = (_frame + 1) % 64
	sky_mat.set_shader_parameter("cam_km", Vector3(cam_pos.x / 1000.0, 0.25 + cam_pos.y / 1000.0, cam_pos.z / 1000.0))
	sky_mat.set_shader_parameter("wind", _wind)
	sky_mat.set_shader_parameter("frame", float(_frame))
