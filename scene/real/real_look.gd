class_name RealLook
extends Node
## The realistic look (look_mode "real"): Cloudscape's sky and clouds, a
## physically lit environment (soft sun shadows, ambient light from the sky,
## ambient occlusion, bloom, volumetric light shafts, filmic tone mapping) and
## the daylight cycle mapped onto it. RideScene owns the nodes; this sets them up
## and feeds the sky every frame.

## Light balance (R43). Outdoors on a clear day the sun gives several times
## the light of the open sky, so shade reads clearly darker and bluer than lit
## ground. The sky's own light is turned down for the ambient term (it alone
## lights what is in shade) and the sun up; the exposure brings lit ground back
## to a natural brightness, with snow in full sun the case that must not clip.
const SUN_ENERGY := 3.2
const SKY_AMBIENT := 0.62          ## share of the sky's light that reaches the shade (ambient_light_sky_contribution)
const EXPOSURE := 0.6              ## tone map exposure before the camera's automatic adjustment
const MOON_ENERGY := 0.22
## The sun's path for this look: the biome's noon height scaled down, and the
## arc flattened (sin^shape) so more of the day has long raking shadows.
const NOON_SCALE := 0.8
const SUN_ARC_SHAPE := 1.15
## Automatic exposure (CameraAttributesPractical): the frame is scaled by
## AUTO_SCALE / (average scene luminance), the average clamped to luminance
## ISO / 800. A clear summer midday measures about 0.39, so it is left as set;
## the clamp lets darker scenes (woods, low sun, dusk) come up by at most
## 1.5 stops and bright ones (snow, desert sand) go down by at most half a
## stop. Slow (a time constant of about 4 s), so a passing tree never pumps it.
const AUTO_SCALE := 0.39
const AUTO_SPEED := 0.25
const AUTO_MIN_ISO := 112.0       ## luminance 0.14: the most it brightens
const AUTO_MAX_ISO := 440.0       ## luminance 0.55: the most it darkens
const WIND_KMPS := 0.008          ## cloud drift, km per second

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var _wind := Vector3.ZERO
var _frame := 0
var _preset: Dictionary = {}
var flora: RealFlora
## The first-person camera's exposure, gently automatic (see AUTO_SCALE).
var camera_attributes := CameraAttributesPractical.new()
var _mist := 0.0          ## valley mist 0..1 (mornings)
## The render-scale governor (RealQuality.next_scale): off for profiling
## (the `fixedscale` switch, or governor_enabled = false set by a tool).
var governor_enabled := true
## Which upscaler brings the picture up to the window (RealQuality.UPSCALERS);
## set before setup, or changed mid-ride with set_upscaler.
var upscaler := "temporal"
var _viewport: SubViewport
var _avg_ms := 0.0         ## frame cost, smoothed over about 2 s
var _age := 0.0            ## seconds since the ride began
var _gov: Dictionary = {}  ## RealQuality.govern's state
var _ssr_allowed := true
## Shade under the canopy, contact shade and cloud shadows on the land (R43 stage 5).
var shade: RealShade
## The sky's cloud settings its shadows must match (cloud_shape.gdshaderinc), copied to RealShade's cloud map.
const CLOUD_PARAMS := ["coverage", "cloud_type", "cloud_density", "cloud_bottom", "cloud_top", "wind", "wind_dir", "light_dir"]
## Preview tool (`clouds=<0..1>`): this much cloud cover whatever the biome says.
var _clouds_override := -1.0

## Ground colour seen by the sky (light bounced up into clouds and ambient), per ground type.
const GROUND_ALBEDO := {
	"snow": Color(0.8, 0.82, 0.86),
	"grass": Color(0.16, 0.2, 0.1),
	"sand": Color(0.5, 0.33, 0.2),
	"desert": Color(0.5, 0.39, 0.29),
}


func setup(e: Environment, s: DirectionalLight3D, viewport: SubViewport, preset_id: String) -> void:
	env = e
	sun = s
	shade = RealShade.new()
	add_child(shade)
	_preset = ScenePreset.get_preset(preset_id)
	flora = RealFlora.for_biome(preset_id)
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
	# With the sky as the source, the energy setting does nothing; the
	# contribution blends the sky's light with this (black) colour instead.
	env.ambient_light_sky_contribution = SKY_AMBIENT
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE
	env.tonemap_agx_contrast = 1.2
	# Bloom only from what is far brighter than lit ground: the sun, its rim on
	# clouds and glints on water; snow in the sun stays below the threshold.
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 3.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	# Aerial perspective: thin enough that the near and middle ground stay
	# crisp, so only far hills go blue. Below the mist floor the air thickens
	# (valley mist, mornings), set by apply_daylight.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00035
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.1
	env.fog_height_density = 0.0
	# Volumetric fog near the rider: light shafts where the low sun cuts
	# through trees, and morning haze that glows toward the sun.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.002
	env.volumetric_fog_albedo = Color(0.92, 0.95, 1.0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	# A gentle film grade: a touch more contrast and colour, warm highlights
	# over cool shadows (see _grade_lut).
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.08
	env.adjustment_color_correction = _grade_lut()
	camera_attributes.exposure_multiplier = 1.0
	camera_attributes.auto_exposure_enabled = true
	camera_attributes.auto_exposure_speed = AUTO_SPEED
	camera_attributes.auto_exposure_scale = AUTO_SCALE
	camera_attributes.auto_exposure_min_sensitivity = AUTO_MIN_ISO
	camera_attributes.auto_exposure_max_sensitivity = AUTO_MAX_ISO
	_apply_quality(viewport)
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.5
	sun.light_volumetric_fog_energy = 1.0
	# Rendered below native resolution and brought up by an upscaler: by default
	# a temporal one (MetalFX on Macs, FSR 2 elsewhere), which also antialiases
	# and settles the sky's jittered clouds.
	viewport.scaling_3d_scale = minf(0.5, RealQuality.scale_max())
	_viewport = viewport
	set_upscaler(upscaler)
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	# Profiling switches for the preview tool.
	var args := OS.get_cmdline_user_args()
	if args.has("noclouds"):
		sky_mat.set_shader_parameter("cloud_steps", 0)
	if args.has("noshadows"):
		sun.shadow_enabled = false
	if args.has("nossao"):
		env.ssao_enabled = false
	if args.has("novfog"):
		env.volumetric_fog_enabled = false
	if args.has("fixedscale"):
		governor_enabled = false
	if args.has("noauto"):
		camera_attributes.auto_exposure_enabled = false
	for arg in args:
		if arg.begins_with("clouds="):
			_clouds_override = float(arg.trim_prefix("clouds="))
	var noise := CloudNoise.new()
	noise.baked.connect(_on_noise)
	add_child(noise)


## The tier's settings (RealQuality): sun shadows, ambient occlusion, volumetric
## fog, wet reflections and cloud steps. The ranges of plants and grass are read
## by RealFlora and RealGrass themselves when the world is built.
func _apply_quality(viewport: SubViewport) -> void:
	var q: Dictionary = RealQuality.TABLE[RealQuality.tier]
	var splits := int(q.shadow_splits)
	sun.shadow_enabled = true
	# Godot has 1, 2 or 4 cascades (no 3).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if splits <= 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = float(q.shadow_dist)
	sun.directional_shadow_split_1 = float(q.split_1)
	sun.directional_shadow_split_2 = float(q.split_2)
	sun.directional_shadow_split_3 = float(q.split_3)
	RenderingServer.directional_shadow_atlas_set_size(int(q.shadow_atlas), true)
	env.ssao_enabled = bool(q.ssao)
	env.volumetric_fog_enabled = bool(q.vfog)
	_ssr_allowed = bool(q.ssr)
	sky_mat.set_shader_parameter("cloud_steps", int(q.cloud_steps))


## The first-person camera takes this look's exposure.
func attach_camera(cam: Camera3D) -> void:
	cam.attributes = camera_attributes


## The colour grade as a small 3D lookup (display-referred, 0..1 in and out):
## shadows lean a little cool, highlights a little warm, midtones untouched.
static func _grade_lut() -> ImageTexture3D:
	const N := 17
	var slices: Array[Image] = []
	for bi in N:
		var img := Image.create(N, N, false, Image.FORMAT_RGB8)
		for gi in N:
			for ri in N:
				var c := Vector3(ri, gi, bi) / float(N - 1)
				var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				var sh := 1.0 - smoothstep(0.0, 0.45, l)
				var hi := smoothstep(0.55, 1.0, l)
				c += Vector3(-0.012, 0.0, 0.022) * sh * (1.0 - sh) * 4.0 * 0.6 + Vector3(-0.006, 0.0, 0.012) * sh
				c += Vector3(0.018, 0.006, -0.02) * hi * (1.0 - hi) * 4.0 * 0.7
				img.set_pixel(ri, gi, Color(clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0)))
		slices.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, N, N, N, false, slices)
	return tex


## Route rides: the biome under the rider now (clouds, noon sun, ground glow).
func set_biome(id: String) -> void:
	flora = RealFlora.for_biome(id)
	if sky_mat:
		sky_mat.set_shader_parameter("ground_albedo", ground_albedo())


func ground_type() -> String:
	return flora.ground_type()


func ground_albedo() -> Color:
	return GROUND_ALBEDO.get(ground_type(), Color(0.3, 0.3, 0.3))


func _on_noise() -> void:
	sky_mat.set_shader_parameter("shape_tex", CloudNoise.shape)
	sky_mat.set_shader_parameter("detail_tex", CloudNoise.detail)
	sky_mat.set_shader_parameter("weather_tex", CloudNoise.weather)
	sky_mat.set_shader_parameter("curl_tex", CloudNoise.curl)
	shade.cloud_mat.set_shader_parameter("shape_tex", CloudNoise.shape)
	shade.cloud_mat.set_shader_parameter("weather_tex", CloudNoise.weather)
	shade.cloud_mat.set_shader_parameter("ready", true)


## Sun or moon for this moment of the world day (Daylight.state), rain greying it over.
func apply_daylight(st: Dictionary, rain: float) -> void:
	var night := bool(st.is_night)
	var daylight := float(st.daylight)
	var dir := sun.global_transform.basis.z.normalized()   # toward the light
	sky_mat.set_shader_parameter("light_dir", dir)
	RenderingServer.global_shader_parameter_set("sun_dir", dir)
	# What water reflects where its traced reflection leaves the screen: the sky's colour now.
	var sky := Color(0.5, 0.63, 0.82).lerp(Color(0.62, 0.64, 0.68), rain) * lerpf(0.04, 1.0, daylight)
	if float(st.elev) < 12.0 and not night:
		sky = sky.lerp(Color(0.85, 0.6, 0.45), 0.4 * (1.0 - float(st.elev) / 12.0))
	RenderingServer.global_shader_parameter_set("water_sky", Vector3(sky.r, sky.g, sky.b))
	sky_mat.set_shader_parameter("sun_disk", 0.0 if night else 1.0)
	sky_mat.set_shader_parameter("stars", clampf(1.0 - daylight * 1.5, 0.0, 1.0) * (1.0 - rain))
	var illum := Vector3.ONE * (0.012 if night else 1.0)
	sky_mat.set_shader_parameter("light_illum", illum)
	var clouds := float(flora.biome.get("clouds", 0.5)) if _clouds_override < 0.0 else _clouds_override
	sky_mat.set_shader_parameter("coverage", lerpf(clouds, 1.0, rain))
	sky_mat.set_shader_parameter("cloud_type", lerpf(1.0, 0.25, rain))
	sky_mat.set_shader_parameter("cloud_density", lerpf(0.19, 0.8, rain))
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
		# Low sun crosses more air: weaker as well as warmer (auto exposure lifts the frame back).
		sun.light_energy = SUN_ENERGY * smoothstep(-0.035, 0.07, sin(elev)) * lerpf(0.5, 1.0, air) * (1.0 - 0.75 * rain)
	# With the sun low, and under cloud, the sky is more of the light: its share
	# of the shade rises, so golden-hour shade and rain stay readable.
	env.ambient_light_sky_contribution = lerpf(lerpf(0.85, SKY_AMBIENT, air), 0.95, rain)
	# Mist: thickest just after sunrise, a little again at dusk, held in the
	# low ground (fog height, see set_mist_floor); rain thickens all of it.
	var hour := float(st.hour)
	var morning := clampf(1.0 - absf(hour - 7.0) / 2.5, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(hour - 19.0) / 2.0, 0.0, 1.0) * 0.4
	_mist = maxf(morning, dusk) * (1.0 - rain)
	env.fog_density = 0.00035 + 0.0004 * _mist + 0.006 * rain
	env.fog_height_density = 0.045 * _mist
	env.volumetric_fog_density = 0.0016 + 0.0035 * _mist + 0.01 * rain
	shade.set_light(rain, leaf_green(), sun.directional_shadow_max_distance)


## How green the light under this biome's trees is (leaves overhead; none under bare twigs).
func leaf_green() -> float:
	var b := flora.biome
	var g := clampf(float(b.get("broad", 0.0)) + 0.5 * float(b.get("spruce", 0.0)), 0.0, 1.0)
	if flora.biome_id == "autumn":
		g *= 0.4
	if ground_type() == "snow":
		g *= 0.5
	return g


## Switches the upscaler (RealQuality.UPSCALERS), mid-ride too. The automatic
## render scale starts its count again, since the two cost differently.
func set_upscaler(id: String) -> void:
	upscaler = RealQuality.normalize_upscaler(id)
	if _viewport == null:
		return
	var s := RealQuality.upscaler_setup(upscaler, OS.get_name() == "macOS")
	if not s[1]:
		_viewport.use_taa = false      # off before a temporal upscaler goes on (the two cannot run together)
	_viewport.scaling_3d_mode = s[0]
	_viewport.use_taa = s[1]
	_avg_ms = 0.0
	_age = 0.0
	_gov = {}


## The 3D render scale now, 0..1 (the automatic render scale moves it).
func render_scale() -> float:
	return _viewport.scaling_3d_scale if _viewport != null else 1.0


## Where the valley mist lies (world height); RideScene finds the low ground around the rider.
func set_mist_floor(y: float) -> void:
	env.fog_height = y


## Every frame: where the eye is, how far the clouds have drifted, the TAA jitter.
func update(cam_pos: Vector3, delta: float, wet := 0.0) -> void:
	# Puddles reflect: screen-space reflections only while the ground is wet.
	env.ssr_enabled = _ssr_allowed and wet > 0.08
	if governor_enabled and _viewport != null:
		_govern(delta)
	_wind += Vector3(1.0, 0.0, 0.35).normalized() * WIND_KMPS * delta
	_frame = (_frame + 1) % 64
	RenderingServer.global_shader_parameter_set("eye_pos", cam_pos)
	sky_mat.set_shader_parameter("cam_km", Vector3(cam_pos.x / 1000.0, 0.25 + cam_pos.y / 1000.0, cam_pos.z / 1000.0))
	sky_mat.set_shader_parameter("wind", _wind)
	sky_mat.set_shader_parameter("frame", float(_frame))
	for p: String in CLOUD_PARAMS:
		shade.cloud_mat.set_shader_parameter(p, sky_mat.get_shader_parameter(p))
	shade.update(cam_pos)


## Holds 60 fps by moving the 3D render scale (RealQuality.govern). The signal
## is the 2-second smoothed frame time: the viewport's own GPU timer reads 0
## under Metal, so frame time is all there is (see RealQuality for how it copes
## with vsync hiding headroom). A hitch (a chunk arriving) is not counted.
func _govern(delta: float) -> void:
	_age += delta
	if delta > 0.08:
		return                       # a stall (loading, a window move), not the scene's cost
	var cost := delta * 1000.0
	if _avg_ms <= 0.0:
		_avg_ms = cost
	_avg_ms = lerpf(_avg_ms, cost, 1.0 - exp(-delta / 2.0))
	if _age < RealQuality.WARMUP:
		return
	var now := _viewport.scaling_3d_scale
	if _gov.is_empty():
		_gov = RealQuality.new_state(now)
	_gov.scale = now
	_gov = RealQuality.govern(_gov, _avg_ms, delta, RealQuality.scale_max())
	var want := float(_gov.scale)
	if not is_equal_approx(want, now):
		_viewport.scaling_3d_scale = want
		if OS.get_cmdline_user_args().has("scalelog"):
			print("[scale] %.2f -> %.2f at avg %.1f ms%s" % [now, want, _avg_ms, " (probe)" if _gov.probing else ""])
