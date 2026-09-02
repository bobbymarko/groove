class_name RideScene
extends Control
## The procedurally generated trail scene, rendered at low resolution into a
## SubViewport and drawn to the screen through the pixel-art post-process.
## Sits behind the ride HUD. Fed by the ride screen with power, cadence, and
## the upcoming workout profile.

const INTERNAL_HEIGHT := 240

var trail: Trail
var terrain: TerrainStreamer
var rider: Rider
var camera: HandheldCamera
var physics := RidePhysics.new()
var snow: Snow
var backdrop: Backdrop

var distance := 20.0          ## metres along the trail
var power := 0.0
var cadence := 0.0
var riding := false
## Called with a distance ahead (m) to fetch the target fraction of FTP there; set by the ride screen.
var target_fraction_ahead: Callable
## Debug: look straight down from above the rider, no post-process.
var debug_top_down := false
## Debug material for terrain and props: "" normal, "nocull" cel without culling, "plain" unshaded vertex colours.
var debug_material := ""

var _viewport: SubViewport
var _world: Node3D
var _screen: TextureRect
var _post: ShaderMaterial


func _ready() -> void:
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
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.92)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	_world.add_child(sun)

	trail = Trail.new()
	trail.grade_provider = _grade_at
	terrain = TerrainStreamer.new(trail)
	_world.add_child(terrain)
	backdrop = Backdrop.new()
	_world.add_child(backdrop)
	rider = Rider.new()
	_world.add_child(rider)
	camera = HandheldCamera.new()
	camera.shake_level = "low"   # the ride screen applies the user's setting via set_shake()
	_world.add_child(camera)
	camera.current = true
	snow = Snow.new()
	_world.add_child(snow)

	_screen = TextureRect.new()
	_screen.texture = _viewport.get_texture()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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


func _fit_viewport() -> void:
	var aspect := size.x / maxf(size.y, 1.0)
	var w := int(round(INTERNAL_HEIGHT * aspect))
	_viewport.size = Vector2i(maxi(w, 64), INTERNAL_HEIGHT)
	_post.set_shader_parameter("texel", Vector2(1.0 / _viewport.size.x, 1.0 / INTERNAL_HEIGHT))


func _process(delta: float) -> void:
	var grade := trail.grade_at(distance)
	var speed := physics.step(power, grade, delta, riding)
	if riding:
		distance += speed * delta
	rider.animate(cadence if riding else 0.0, speed if riding else 0.0, delta)
	_place_rider()
	terrain.update_around(distance)
	var anchor := trail.position_at(maxf(distance - camera.follow_distance, 0.0))
	var ground := terrain.height(anchor.x, anchor.z)
	if debug_top_down:
		_screen.material = null
		camera.global_position = rider.global_position + Vector3(0.0, 40.0, -10.0)
		camera.look_at(rider.global_position, Vector3.FORWARD)
	else:
		camera.update_follow(rider.global_position, trail.heading_at(distance), anchor, ground, speed, delta)
	snow.follow(camera.global_position)
	backdrop.follow(rider.global_position)


func _place_rider() -> void:
	var pos := trail.position_at(distance)
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
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Palette.FOG
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	return we
