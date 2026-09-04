class_name RideScene
extends Control
## The procedurally generated trail scene, rendered at low resolution into a
## SubViewport and drawn to the screen through the pixel-art post-process.
## Sits behind the ride HUD. Fed by the ride screen with power, cadence, and
## the upcoming workout profile.

const INTERNAL_HEIGHT := 240
var _internal_height := INTERNAL_HEIGHT
var pixel_filter := true
var look_mode := "8bit"

var trail: Trail
var terrain: TerrainStreamer
var rider: Rider
var camera: HandheldCamera
var physics := RidePhysics.new()
var snow: Snow
var marks: TreadMarks
var preset_id := "winter"        ## ScenePreset in use (from App unless overridden)
var preset_override := ""        ## tooling: force a preset regardless of settings
var _preset: Dictionary = {}
var backdrop: Backdrop

var distance := 20.0          ## metres along the trail
var power := 0.0
var cadence := 0.0
var riding := false
var time_scale := 1.0        ## dev fast-forward; keeps the world in step with the workout
var avg_speed := 5.0         ## slow-moving average of speed, for predicting where the rider will be
## Called with a distance ahead (m) to fetch the target fraction of FTP there; set by the ride screen.
var target_fraction_ahead: Callable
## Debug: look straight down from above the rider, no post-process.
var debug_top_down := false
## Debug: close three-quarter view of the rider, no post-process.
var debug_closeup := false
## Debug: close view of the hands on the bars (with debug_closeup).
var debug_hands := false
## Debug material for terrain and props: "" normal, "nocull" cel without culling, "plain" unshaded vertex colours.
var debug_material := ""

var _viewport: SubViewport
var _sun: DirectionalLight3D
var _env: Environment
var _world: Node3D
var _screen: TextureRect
var _post: ShaderMaterial


func _ready() -> void:
	# The look: a preset recolours the palette before anything reads it.
	if preset_override != "":
		preset_id = preset_override
	else:
		var app0 := get_node_or_null("/root/App")
		if app0:
			preset_id = str(app0.scene_preset)
	Palette.apply(preset_id)
	_preset = ScenePreset.get_preset(preset_id)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(426, INTERNAL_HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)

	_world = Node3D.new()
	_viewport.add_child(_world)
	_world.add_child(_environment())
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-32.0, 40.0, 0.0)   # low winter sun from front-left
	sun.light_color = Color(1.0, 0.96, 0.92)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.shadow_blur = 0.0          # hard-edged shadows suit the pixel look
	# Low winter sun grazes the snow; generous biases keep the shadow map from
	# striping flat ground (acne) at small elevations.
	sun.shadow_bias = 0.35
	sun.shadow_normal_bias = 4.0
	sun.directional_shadow_max_distance = 120.0
	_world.add_child(sun)

	trail = Trail.new()
	trail.grade_provider = _grade_at
	terrain = TerrainStreamer.new(trail)
	_world.add_child(terrain)
	backdrop = Backdrop.new()
	_world.add_child(backdrop)
	marks = TreadMarks.new()
	_world.add_child(marks)
	rider = Rider.new()
	_world.add_child(rider)
	camera = HandheldCamera.new()
	camera.shake_level = "low"   # the ride screen applies the user's setting via set_shake()
	camera.ground_height = func(x: float, z: float) -> float: return terrain.height(x, z)
	_world.add_child(camera)
	camera.current = true
	snow = Snow.new()
	snow.emitting = bool(_preset.get("snow", true))
	_world.add_child(snow)

	_screen = TextureRect.new()
	_screen.texture = _viewport.get_texture()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # the render target must not dictate our minimum size
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_post = ShaderMaterial.new()
	_post.shader = load("res://scene/post/pixel_post.gdshader")
	var pal := Palette.list()
	_post.set_shader_parameter("palette", pal)
	_post.set_shader_parameter("palette_size", pal.size())
	_screen.material = _post
	add_child(_screen)
	resized.connect(_fit_viewport)
	_fit_viewport()
	var app := get_node_or_null("/root/App")
	if app:
		look_mode = app.look_mode
		apply_tuning(app.scene_tuning)
	set_look_mode(look_mode)
	_place_rider()
	terrain.update_around(distance)
	if debug_material != "":
		_apply_debug_material()


func _apply_debug_material() -> void:
	var m: Material
	if debug_material == "plain":
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = sm
	else:
		var sh := Shader.new()
		sh.code = load("res://scene/post/cel.gdshader").code.replace("cull_back", "cull_disabled")
		var shm := ShaderMaterial.new()
		shm.shader = sh
		shm.set_shader_parameter("use_vertex_color", true)
		m = shm
	terrain._material = m
	for key in terrain._chunks:
		for child in terrain._chunks[key].get_children():
			if child is GeometryInstance3D:
				child.material_override = m


func set_shake(level: String) -> void:
	camera.shake_level = level


## "8bit": low-res render snapped to the palette, 3 shading bands.
## "16bit": ~40 % more rows, colours posterized to 5 bits per channel, 6 bands,
## finer tonal steps on textures. "off": native resolution, no post-process.
func set_look_mode(mode: String) -> void:
	look_mode = mode
	pixel_filter = mode != "off"
	_screen.material = _post if pixel_filter else null
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_filter else CanvasItem.TEXTURE_FILTER_LINEAR
	_post.set_shader_parameter("mode", 1 if mode == "16bit" else 0)
	RenderingServer.global_shader_parameter_set("cel_bands", 6.0 if mode != "8bit" else 3.0)
	RenderingServer.global_shader_parameter_set("cel_colorize_steps", 8.0 if mode != "8bit" else 3.0)
	RenderingServer.global_shader_parameter_set("cel_texture_mix", 0.4 if mode != "8bit" else 0.0)
	RenderingServer.global_shader_parameter_set("cel_smooth_terrain", 1.0 if mode != "8bit" else 0.0)
	_fit_viewport()


## Kept for callers that only know the on/off toggle.
func set_pixel_filter(on: bool) -> void:
	set_look_mode(("16bit" if look_mode == "off" else look_mode) if on else "off")


## Apply the user's scene tuning (see App.TUNING_SPEC). Safe to call every change.
func apply_tuning(t: Dictionary) -> void:
	RenderingServer.global_shader_parameter_set("cel_shadow_band", 1.0 - float(t.get("shadow_strength", 0.55)))
	RenderingServer.global_shader_parameter_set("cel_shade_band", float(t.get("shade_band", 0.66)))
	RenderingServer.global_shader_parameter_set("cel_dark_band", float(t.get("shade_band", 0.66)) * 0.76)
	_sun.rotation_degrees = Vector3(-(float(t.get("sun_elevation", 32.0)) + float(_preset.get("sun_lift", 0.0))), float(t.get("sun_azimuth", 40.0)), 0.0)
	_sun.light_energy = float(t.get("sun_energy", 0.8))
	_env.ambient_light_energy = float(t.get("ambient_energy", 0.4))
	_env.fog_density = float(t.get("fog_density", 0.0028))
	_post.set_shader_parameter("dither_strength", float(t.get("dither", 0.0)))
	_post.set_shader_parameter("sharpen", float(t.get("sharpen", 0.4)))
	RenderingServer.global_shader_parameter_set("cel_speckle", float(t.get("speckle", 0.12)))
	RenderingServer.global_shader_parameter_set("cel_highlight", float(t.get("highlight", 0.15)))
	# 0 -> threshold 1.05 (bare), 1 -> 0.5 (buried).
	RenderingServer.global_shader_parameter_set("cel_prop_snow", (1.05 - 0.55 * float(t.get("tree_snow", 0.5))) if bool(_preset.get("prop_snow", true)) else 2.0)
	_post.set_shader_parameter("outline_darken", float(t.get("outline", 0.0)))
	camera.follow_distance = float(t.get("camera_distance", 7.8))
	camera.follow_height = float(t.get("camera_height", 2.7))
	var density := float(t.get("tree_density", 1.0))
	if not is_equal_approx(density, terrain.density_scale):
		terrain.density_scale = density
		terrain.rebuild()
		terrain.update_around(distance)
	var h := int(t.get("internal_height", 240.0))
	if h != _internal_height:
		_internal_height = h
		_fit_viewport()


func _fit_viewport() -> void:
	if not pixel_filter:
		var native := Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
		# Retina: render at the window's pixel size, not its logical size.
		var scale := DisplayServer.screen_get_scale() if DisplayServer.get_name() != "headless" else 1.0
		_viewport.size = Vector2i(int(native.x * scale), int(native.y * scale))
		return
	var aspect := size.x / maxf(size.y, 1.0)
	var rows := _internal_height if look_mode == "8bit" else int(_internal_height * 1.4)
	var w := int(round(rows * aspect))
	_viewport.size = Vector2i(maxi(w, 64), rows)
	_post.set_shader_parameter("texel", Vector2(1.0 / _viewport.size.x, 1.0 / rows))


func current_grade() -> float:
	return trail.grade_at(distance)


func _process(raw_delta: float) -> void:
	var delta := raw_delta * time_scale
	var grade := trail.grade_at(distance)
	var speed := physics.step(power, grade, delta, riding)
	if riding:
		distance += speed * delta
		avg_speed = lerpf(avg_speed, speed, clampf(delta / 15.0, 0.0, 1.0))
	# Trainers without a cadence sensor report 0 rpm while power flows; keep the
	# legs turning at a plausible rate so the rider never coasts under load.
	var anim_cadence := cadence
	if riding and cadence < 1.0 and power > 15.0:
		anim_cadence = clampf(60.0 + power * 0.12, 60.0, 95.0)
	rider.animate(anim_cadence if riding else 0.0, speed if riding else 0.0, raw_delta)
	_place_rider()
	if riding and speed > 0.05:
		marks.add(rider.to_global(Vector3(0.0, 0.0, -0.55)), rider.global_transform.basis.x, terrain.height)
	terrain.update_around(distance)
	var anchor := trail.position_at(maxf(distance - camera.follow_distance, 0.0))
	var ground := terrain.height(anchor.x, anchor.z)
	if debug_top_down:
		_screen.material = null
		camera.global_position = rider.global_position + Vector3(0.0, 40.0, -10.0)
		camera.look_at(rider.global_position, Vector3.FORWARD)
	elif debug_closeup:
		_screen.material = null
		_internal_height = 720
		_fit_viewport()
		if debug_hands:
			camera.global_position = rider.to_global(Vector3(0.9, 1.5, 1.4))
			camera.look_at(rider.to_global(Vector3(0.0, 1.05, 0.5)), Vector3.UP)
		else:
			camera.global_position = rider.global_position + Vector3(2.4, 1.3, -2.6)
			camera.look_at(rider.global_position + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	else:
		camera.update_follow(rider.global_position, trail.heading_at(distance), anchor, ground, speed, delta)
	snow.follow(camera.global_position)
	backdrop.follow(rider.global_position)


func _place_rider() -> void:
	var pos := trail.position_at(distance)
	pos.y = terrain.height(pos.x, pos.z)
	rider.global_position = pos
	var heading := trail.heading_at(distance)
	var flat := Vector3(heading.x, 0.0, heading.z).normalized()
	rider.rotation.y = atan2(flat.x, flat.z)
	rider.rotation.x = -asin(clampf(heading.y, -0.5, 0.5))
	# Lean into curves: proportional to curvature and speed squared.
	var k := trail.curvature_at(distance)
	rider.lean = clampf(atan(k * physics.speed * physics.speed / 9.81) * 0.8, -0.35, 0.35)


func _grade_at(z: float) -> float:
	if not target_fraction_ahead.is_valid():
		return trail._default_grade(z)
	var ahead := maxf(z - distance, 0.0)
	var f: Variant = target_fraction_ahead.call(ahead)
	if f == null:
		return trail._default_grade(z)
	return Trail.grade_for_target(float(f))


func _environment() -> WorldEnvironment:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Palette.SKY_TOP
	mat.sky_horizon_color = Palette.SKY_HORIZON
	mat.ground_horizon_color = Palette.SKY_HORIZON
	mat.ground_bottom_color = Palette.SNOW_SHADE
	mat.sun_angle_max = 0.0
	mat.sky_curve = 0.25
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.SNOW_SHADOW
	env.ambient_light_energy = 0.4
	env.fog_enabled = true
	env.fog_light_color = Palette.FOG
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	return we
