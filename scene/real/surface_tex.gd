class_name SurfaceTex
extends RefCounted
## The realistic look's surface materials (R43 stage 2): the photo-scanned
## texture sets in assets/textures (fetched by tools/fetch-textures.sh) and the
## rock detail texture baked here from code.
##  - ground(): the ground's sets as three texture arrays (colour, normal,
##    height), one layer per slot in GROUND, so one shader can pick any look's
##    field, trail and rock by index without a sampler per set;
##  - tex_set(): one set as separate textures (bark, bridge timber);
##  - rock_detail(): a tileable height field in the manner of Abyssal Garden
##    (MIT): warped fBm, ridges, two crack networks and pits, with the slope
##    of that same height beside it, so bumps, light and colour agree.
## Anything missing (a fresh clone before fetch-textures.sh, a headless test run
## with no renderer) comes back empty and the shaders fall back to their noise.

const DIR := "res://assets/textures/"
## Order is the layer index in the ground arrays (real_ground.gdshader's S_* constants).
const GROUND := ["grass_ground", "forest_floor", "trail_gravel", "trail_mud", "snow", "snow_trail",
		"sand", "desert_gravel", "rock_cliff", "rock_mossy"]
## Metres one repeat of each set covers on the ground (assets/textures/README.md;
## the ambientCG ones are estimates, checked against the scene).
const TILE := {"grass_ground": 2.5, "forest_floor": 1.5, "trail_gravel": 2.0, "trail_mud": 2.1, "snow": 2.4,
		"snow_trail": 2.0, "sand": 1.8, "desert_gravel": 2.5, "rock_cliff": 2.5, "rock_mossy": 2.5}
## Average albedo (linear luminance) each ground set is shown at: what the
## light was tuned for (grass 0.05-0.15, dry gravel 0.2-0.35, snow 0.8-0.9).
const ALBEDO := {"grass_ground": 0.085, "forest_floor": 0.1, "trail_gravel": 0.22, "trail_mud": 0.13, "snow": 0.84,
		"snow_trail": 0.62, "sand": 0.36, "desert_gravel": 0.3, "rock_cliff": 0.18, "rock_mossy": 0.12}
## Bark: metres round the trunk and along it that one repeat covers (bark_oak's picture is 1 : 2).
const BARK_TILE := {"bark_pine": Vector2(0.7, 0.7), "bark_oak": Vector2(0.45, 0.9), "bark_birch": Vector2(0.5, 0.5)}
const ROCK_PX := 1024

static var _ground: Dictionary = {}
static var _ground_tried := false
static var _sets: Dictionary = {}
static var _rock: Texture2D
static var _rock_tried := false


static func has_set(slot: String) -> bool:
	if _off():
		return false
	for f in ["albedo", "normal", "arm", "height"]:
		if not ResourceLoader.exists(DIR + slot + "/" + f + ".jpg"):
			return false
	return true


## One set's textures {albedo, normal, arm, height}, or {} when it is missing.
static func tex_set(slot: String) -> Dictionary:
	if _sets.has(slot):
		return _sets[slot]
	var out := {}
	if has_set(slot):
		for f in ["albedo", "normal", "arm", "height"]:
			out[f] = load(DIR + slot + "/" + f + ".jpg")
	_sets[slot] = out
	return out


## Give a real_bark material its scanned set (bark_pine, bark_oak, bark_birch);
## left on its noise when the set is missing.
static func bark(m: ShaderMaterial, slot: String) -> void:
	var t := tex_set(slot)
	if t.is_empty():
		return
	m.set_shader_parameter("bark_tex", true)
	m.set_shader_parameter("bark_albedo", t.albedo)
	m.set_shader_parameter("bark_normal", t.normal)
	m.set_shader_parameter("bark_arm", t.arm)
	m.set_shader_parameter("bark_height", t.height)
	m.set_shader_parameter("bark_tile", BARK_TILE[slot])


## Give the bridge timber (real_wood) the plank scan, brought to the timber's albedo.
static func wood(m: ShaderMaterial) -> void:
	var t := tex_set("wood_planks")
	if t.is_empty():
		return
	var img := (t.albedo as Texture2D).get_image()
	if img == null or img.is_empty():
		return
	m.set_shader_parameter("wood_tex", true)
	m.set_shader_parameter("wood_albedo", t.albedo)
	m.set_shader_parameter("wood_normal", t.normal)
	m.set_shader_parameter("wood_arm", t.arm)
	m.set_shader_parameter("wood_gain", 0.17 / maxf(_lum(_mean(img)), 1e-3))


## Give a material that includes rock.gdshaderinc the baked rock detail and
## the rock_cliff scan for its fine grain.
static func rock(m: ShaderMaterial) -> void:
	var t := rock_detail()
	if t != null:
		m.set_shader_parameter("rock_detail", t)
		m.set_shader_parameter("rock_baked", true)
	var sc := tex_set("rock_cliff")
	if sc.is_empty():
		return
	if not sc.has("mean"):
		var img := (sc.albedo as Texture2D).get_image()
		sc["mean"] = _mean(img) if img != null and not img.is_empty() else Vector3.ZERO
	if sc.mean == Vector3.ZERO:
		return
	m.set_shader_parameter("rock_scan", true)
	m.set_shader_parameter("scan_albedo", sc.albedo)
	m.set_shader_parameter("scan_normal", sc.normal)
	m.set_shader_parameter("scan_height", sc.height)
	m.set_shader_parameter("scan_mean", sc.mean)


## Set up a real_ground material: the texture arrays (or the noise fallback),
## and per ground look (TerrainStreamer.GROUND_IDS) the biome that colours it:
## looks is {look id: RealFlora biome id}; main_biome gives the rock.
static func ground_material(m: ShaderMaterial, looks: Dictionary, main_biome: String) -> void:
	var b: Dictionary = RealFlora.BIOMES.get(main_biome, RealFlora.BIOMES.summer)
	var rc: Color = b.get("rock", Color(0.4, 0.39, 0.37))
	m.set_shader_parameter("rock_tint", Vector3(rc.r, rc.g, rc.b) * 0.62)   # a bank in full sun reads lighter than a boulder
	m.set_shader_parameter("rock_moss", float(b.get("moss", 0.0)))
	m.set_shader_parameter("rock_snow", 1.0 if float(b.get("snow", 0.0)) > 0.0 else 0.0)
	rock(m)
	var tints := PackedVector3Array()
	var trail_tints := PackedVector3Array()
	var meadow := PackedVector3Array()
	var amount := PackedFloat32Array()
	for look in 4:
		var id: String = looks.get(look, main_biome)
		var bb: Dictionary = RealFlora.BIOMES.get(id, b)
		var gc: Color = bb.get("grass", Color(0.13, 0.24, 0.06))
		tints.append(field_tint(look, gc))
		trail_tints.append(trail_tint(look))
		meadow.append(Vector3(gc.r, gc.g, gc.b))
		amount.append(clampf(float(bb.get("grass_density", 0.0)), 0.0, 1.0) if look == 1 else 0.0)
	m.set_shader_parameter("field_tint", tints)
	m.set_shader_parameter("trail_tint", trail_tints)
	m.set_shader_parameter("meadow_color", meadow)
	m.set_shader_parameter("meadow_amount", amount)
	var g := ground()
	if g.is_empty():
		return
	m.set_shader_parameter("textured", true)
	m.set_shader_parameter("g_albedo", g.albedo)
	m.set_shader_parameter("g_normal", g.normal)
	m.set_shader_parameter("g_height", g.height)
	m.set_shader_parameter("slot_tile", g.tile)
	m.set_shader_parameter("slot_gain", g.gain)
	m.set_shader_parameter("slot_mean", g.scaled_mean)


## The field of ground look `look` turned toward its biome's colour: the grass
## look halfway to the biome's grass (autumn's and a burnt land's ground is
## browner), the desert's rusty scan to the tan of a Sonoran wash.
static func field_tint(look: int, grass: Color) -> Vector3:
	match look:
		1:
			return _hue("grass_ground", Vector3(grass.r, grass.g, grass.b), 0.5, 1.0)
		2:
			return _hue("sand", Vector3(0.58, 0.42, 0.25), 0.5, 1.0)
		3:
			return _hue("desert_gravel", Vector3(0.4, 0.29, 0.2), 0.75, 1.0)
	return Vector3.ONE


## The same for the trail: a desert trail is paler, finer, packed.
static func trail_tint(look: int) -> Vector3:
	if look == 3:
		return _hue("desert_gravel", Vector3(0.55, 0.45, 0.34), 0.8, 1.45)
	return Vector3.ONE


## Per-channel factor taking set `slot`'s average hue `strength` of the way to
## want's, then scaled by `bright`.
static func _hue(slot: String, want: Vector3, strength: float, bright: float) -> Vector3:
	var g := ground()
	if g.is_empty():
		return Vector3.ONE
	var m: Vector3 = g.mean[GROUND.find(slot)]
	var t := (want / maxf(_lum(want), 1e-3)) / (m / maxf(_lum(m), 1e-3))
	t = Vector3.ONE.lerp(t, strength).clamp(Vector3.ONE * 0.5, Vector3.ONE * 2.0)
	return t * (bright / maxf(_lum(t), 1e-3))


## The bare grass field's average colour under a biome with this grass (the
## colour the meadow's roots take), or null without the texture sets.
static func grass_field(grass: Color) -> Variant:
	var g := ground()
	if g.is_empty():
		return null
	var i := GROUND.find("grass_ground")
	return (g.scaled_mean[i] as Vector3) * field_tint(1, grass)


## "notex" on the command line: draw as a fresh clone without the sets would
## (the fallback), e.g. to measure what the materials cost.
static func _off() -> bool:
	return OS.get_cmdline_user_args().has("notex")


static func _lum(c: Vector3) -> float:
	return c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722


## The ground's sets as texture arrays: {albedo, normal, height: Texture2DArray,
## tile: PackedFloat32Array (metres a repeat), mean: PackedVector3Array (each
## set's average colour, linear)}, or {} when a set is missing or there is no
## renderer to read them back from.
static func ground() -> Dictionary:
	if _ground_tried:
		return _ground
	_ground_tried = true
	var t0 := Time.get_ticks_msec()
	var layers := {"albedo": [], "normal": [], "height": []}
	var tile := PackedFloat32Array()
	var mean := PackedVector3Array()
	for slot: String in GROUND:
		if not has_set(slot):
			return _ground
		for f: String in layers:
			var tex := load(DIR + slot + "/" + f + ".jpg") as Texture2D
			var img := tex.get_image() if tex != null else null
			if img == null or img.is_empty():
				return _ground
			(layers[f] as Array).append(img)
		tile.append(float(TILE[slot]))
		mean.append(_mean(layers.albedo[layers.albedo.size() - 1]))
	# Each scan brought to a true albedo: its average luminance to ALBEDO's.
	var gain := PackedFloat32Array()
	var scaled := PackedVector3Array()
	for i in GROUND.size():
		var k := float(ALBEDO[GROUND[i]]) / maxf(_lum(mean[i]), 1e-3)
		gain.append(k)
		scaled.append(mean[i] * k)
	var out := {"tile": tile, "mean": mean, "gain": gain, "scaled_mean": scaled}
	for f: String in layers:
		var arr := Texture2DArray.new()
		var imgs: Array[Image] = []
		imgs.assign(layers[f])
		if arr.create_from_images(imgs) != OK:
			push_warning("SurfaceTex: could not build the %s array" % f)
			return _ground
		out[f] = arr
	_ground = out
	if OS.is_debug_build():
		var means := []
		for i in GROUND.size():
			means.append("%s %.3f,%.3f,%.3f" % [GROUND[i], mean[i].x, mean[i].y, mean[i].z])
		print("[surface] ground arrays in %d ms; means %s" % [Time.get_ticks_msec() - t0, ", ".join(means)])
	return _ground


## Average colour of an sRGB picture, linear.
static func _mean(src: Image) -> Vector3:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > 16 and img.get_height() > 16:
		img.shrink_x2()
	var sum := Vector3.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y).srgb_to_linear()
			sum += Vector3(c.r, c.g, c.b)
	return sum / float(img.get_width() * img.get_height())


## The baked rock detail (rg: the height's slope, b: height, a: mottling;
## tileable, mipmapped), drawn once per run; null without a renderer.
static func rock_detail() -> Texture2D:
	if _rock_tried:
		return _rock
	_rock_tried = true
	if _off() or not PlantBake.available():
		return null
	var root := (Engine.get_main_loop() as SceneTree).root
	var t0 := Time.get_ticks_msec()
	var vp := SubViewport.new()
	vp.size = Vector2i(ROCK_PX, ROCK_PX)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(ROCK_PX, ROCK_PX)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scene/real/rock_detail_bake.gdshader")
	mat.set_shader_parameter("px", float(ROCK_PX))
	rect.material = mat
	vp.add_child(rect)
	root.add_child(vp)
	if not vp.is_inside_tree():
		vp.free()
		return null
	# A control draws itself at the end of the frame; this draw is now, so give it its rectangle directly.
	RenderingServer.canvas_item_add_rect(rect.get_canvas_item(), Rect2(0, 0, ROCK_PX, ROCK_PX), Color.WHITE)
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	_rock = ImageTexture.create_from_image(img)
	if OS.is_debug_build():
		print("[surface] rock detail baked in %d ms" % (Time.get_ticks_msec() - t0))
		if OS.get_cmdline_user_args().has("dump-atlas"):
			img.save_png("res://build/rock_detail.png")
	return _rock
