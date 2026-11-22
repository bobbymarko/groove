class_name RealShade
extends Node
## Light and shade at the scale of the land (R43 stage 5), for the realistic
## look's shaders (shade.gdshaderinc reads all of it as global uniforms):
##  - the canopy: how much leaf cover hangs over each spot, so woods have a
##    dark floor and a shaded inside, near and far. Every chunk or tile of the
##    world says where its trees, bushes and rocks stand (blobs(), worked out on
##    the terrain's worker thread with the scatter); a Blobs node in the chunk
##    hands them to this, and they are drawn as soft discs, added up, into two
##    small maps round the eye: a near one, fine (half a metre a texel), that
##    also says where something meets the ground (trunks, rocks, bushes) for
##    contact shade; and a far one, coarse, for the woods across the valley.
##    The maps are drawn on the GPU only when the eye has moved some way or a
##    chunk came or went; otherwise they cost nothing.
##  - cloud shadows: the sky's own clouds (cloud_shape.gdshaderinc, the very
##    shapes real_sky draws), how much sunlight gets through each column down to
##    a plane at the eye's height, drawn every frame into a map kilometres
##    across (clouds drift), so shadows sit under the clouds overhead and move
##    with them over the far hills.
## The maps' textures are SubViewports inside the 3D view's own viewport, so
## each is drawn earlier in the same frame than the scene that reads it.

## Per quality tier: texels across and metres a texel of the near map (canopy
## and contact), the far map (canopy) and the cloud map.
const MAPS := {
	"low": {"near": 256, "near_m": 0.5, "far": 256, "far_m": 5.0, "cloud": 128, "cloud_m": 192.0},
	"medium": {"near": 512, "near_m": 0.5, "far": 512, "far_m": 2.5, "cloud": 256, "cloud_m": 96.0},
	"high": {"near": 512, "near_m": 0.5, "far": 512, "far_m": 2.5, "cloud": 256, "cloud_m": 96.0},
}
const NEAR_STEP := 24.0       ## the near map moves when the eye is this far from its middle (metres)
const FAR_STEP := 160.0       ## the far map likewise
const CLOUD_SHADOW := 0.85    ## how much of the sun a thick cloud takes away (the rest is light through and round it)
const CLOUD_EVERY := 3        ## the cloud map is drawn every this many frames
const BLOB_FLOATS := 12       ## per blob in a MultiMesh buffer: a 2D transform (8) and custom data (x, z, radius, value)

## The one in the scene now (null outside the realistic look; Blobs then keep to themselves).
static var current: RealShade
static var _live: Dictionary = {}        ## every Blobs in the tree: instance id -> Blobs
static var _profiles: Dictionary = {}    ## "<flora id>:<mesh index>" -> Vector4 (crown radius, crown density, contact radius, contact value)
static var _profiles_lock := Mutex.new()

var _maps: Dictionary
var _near: SubViewport
var _far: SubViewport
var _cloud: SubViewport
var _near_mat := ShaderMaterial.new()
var _far_mat := ShaderMaterial.new()
var cloud_mat := ShaderMaterial.new()    ## RealLook keeps its sky settings in step with real_sky's
var _quad: ArrayMesh
var _drawn: Dictionary = {}              ## Blobs instance id -> [near MultiMeshInstance2D, far one]
var _keys: Dictionary = {}               ## Blobs key -> instance id (a rebuilt tile replaces its old blobs at once)
var _near_mid := Vector2(INF, INF)
var _far_mid := Vector2(INF, INF)
var _dirty := false
var _cloud_tick := 0
var _amount := Vector4.ZERO              ## shade_amount: canopy on, cloud strength, leaf green, real shadow reach
var _debug_frames := 236 if OS.get_cmdline_user_args().has("shademaps") else 0
## Preview tool switches, for comparison: all of this off (`noshade`), the canopy off, the cloud shadows off.
var _off := Vector3(float(OS.get_cmdline_user_args().has("noshade")), float(OS.get_cmdline_user_args().has("nocanopy")), float(OS.get_cmdline_user_args().has("nocloudshade")))


## A chunk's blobs. It lives in the chunk's node, so the blobs go when the chunk does.
class Blobs:
	extends Node
	var key := ""
	var buffer := PackedFloat32Array()

	func _enter_tree() -> void:
		RealShade._live[get_instance_id()] = self
		if RealShade.current != null:
			RealShade.current._add(self)

	func _exit_tree() -> void:
		RealShade._live.erase(get_instance_id())
		if RealShade.current != null:
			RealShade.current._remove(self)


## Main thread: the node that carries one chunk's blobs (from blobs()); key
## names the chunk or tile, so a rebuilt one replaces its old blobs.
static func holder(key: String, buffer: PackedFloat32Array) -> Node:
	var b := Blobs.new()
	b.name = "Shade"
	b.key = key
	b.buffer = buffer
	return b


## Worker thread: the blobs for one chunk's plants, {biome id: placed} as
## RealFlora.scatter / scatter_area give them. Each tree gives a canopy disc
## the size of its crown and a contact disc round its foot; bushes and rocks a
## contact disc. Returned as a MultiMesh buffer ready to hand to the GPU.
static func blobs(placed_by_biome: Dictionary, floras: Dictionary, fallback: RealFlora) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id: String in placed_by_biome:
		var fl: RealFlora = floras.get(id, fallback)
		if fl == null:
			continue
		var placed: Dictionary = placed_by_biome[id]
		for mi: int in placed:
			var pr := _profile(fl, mi)
			var xfs: Array = placed[mi][0]
			for xf: Transform3D in xfs:
				var s := maxf(xf.basis.x.length(), xf.basis.z.length())
				var o := xf.origin
				if pr.x > 0.0:
					_put(out, o.x, o.z, pr.x * s, pr.y)
				if pr.z > 0.0:
					_put(out, o.x, o.z, pr.z * s, -pr.w)    # negative: contact, not canopy
	return out


static func _put(out: PackedFloat32Array, x: float, z: float, r: float, v: float) -> void:
	out.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, x, z, r, v]))


## How a plant variant shades, from its size and kind (worked out once per variant).
static func _profile(fl: RealFlora, mi: int) -> Vector4:
	var key := "%d:%d" % [fl.get_instance_id(), mi]
	_profiles_lock.lock()
	var have: Variant = _profiles.get(key)
	_profiles_lock.unlock()
	if have != null:
		return have
	var mesh: Mesh = fl.meshes[mi]
	var box := mesh.get_aabb() if mesh != null else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	var half := maxf(box.size.x, box.size.z) * 0.5
	var pr := Vector4.ZERO
	match fl.kinds[mi]:
		"tree":
			# How much light a crown stops: thick for a spruce or a leafy broadleaf,
			# little for bare twigs, next to none for a saguaro's column.
			# (The kind lists are read by name: RealFlora's plant lists change as plants are added.)
			var density := 0.9
			if _listed(fl, "_spruce", mi):
				density = 1.0
			elif _listed(fl, "_bare", mi):
				density = 0.22
			elif _listed(fl, "_saguaro", mi):
				density = 0.0
			elif _listed(fl, "_palo", mi):
				density = 0.4
			pr = Vector4(half * 0.9, density, clampf(half * 0.3, 0.7, 1.8), 0.85)
		"bush":
			pr = Vector4(0.0, 0.0, half * 0.95 + 0.15, 0.45)
		"rock":
			# Rocks, logs, stumps: as wide as they are on the ground (a log's
			# length would spread its contact far past its sides).
			pr = Vector4(0.0, 0.0, sqrt(box.size.x * box.size.z) * 0.5 * 1.45 + 0.25, 1.0)
		_:
			pass        # "flat" (herbs, litter): nothing
	_profiles_lock.lock()
	_profiles[key] = pr
	_profiles_lock.unlock()
	return pr


static func _listed(fl: RealFlora, list: String, mi: int) -> bool:
	var a: Variant = fl.get(list)
	return a is Array and (a as Array).has(mi)


func _init() -> void:
	name = "RealShade"
	_maps = MAPS[RealQuality.tier]
	_quad = ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var blob := load("res://scene/real/shade_blob.gdshader") as Shader
	_near_mat.shader = blob
	_near_mat.set_shader_parameter("px_per_m", 1.0 / float(_maps.near_m))
	_near_mat.set_shader_parameter("min_radius", float(_maps.near_m) * 1.5)
	_near_mat.set_shader_parameter("contact", 1.0)
	_far_mat.shader = blob
	_far_mat.set_shader_parameter("px_per_m", 1.0 / float(_maps.far_m))
	_far_mat.set_shader_parameter("min_radius", float(_maps.far_m) * 1.5)
	_far_mat.set_shader_parameter("contact", 0.0)
	_near = _viewport(int(_maps.near), true)
	_far = _viewport(int(_maps.far), true)
	_cloud = _viewport(int(_maps.cloud), false)
	cloud_mat.shader = load("res://scene/real/cloud_shadow.gdshader")
	var rect := ColorRect.new()
	rect.size = Vector2(_cloud.size)
	rect.material = cloud_mat
	_cloud.add_child(rect)


func _viewport(px: int, hdr: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.disable_3d = true
	vp.transparent_bg = true          # clears to zero: no cover
	vp.use_hdr_2d = hdr               # covers add up past 1 (float texels)
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	return vp


func _enter_tree() -> void:
	current = self
	for b: Blobs in _live.values():
		_add(b)
	RenderingServer.global_shader_parameter_set("shade_near", _near.get_texture())
	RenderingServer.global_shader_parameter_set("shade_far", _far.get_texture())
	RenderingServer.global_shader_parameter_set("shade_cloud", _cloud.get_texture())


func _exit_tree() -> void:
	if current == self:
		current = null
	RenderingServer.global_shader_parameter_set("shade_amount", Vector4.ZERO)


func _add(b: Blobs) -> void:
	var id := b.get_instance_id()
	if _drawn.has(id) or b.buffer.is_empty():
		return
	if _keys.has(b.key) and _drawn.has(_keys[b.key]):
		_free(_keys[b.key])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = b.buffer.size() / BLOB_FLOATS
	mm.buffer = b.buffer
	# The shader places each disc (from its custom data); never cull the lot.
	mm.custom_aabb = AABB(Vector3(-1e7, -1e7, -1.0), Vector3(2e7, 2e7, 2.0))
	var pair: Array = []
	for vp_mat: Array in [[_near, _near_mat], [_far, _far_mat]]:
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.material = vp_mat[1]
		(vp_mat[0] as SubViewport).add_child(mmi)
		pair.append(mmi)
	_drawn[id] = pair
	_keys[b.key] = id
	_dirty = true


func _remove(b: Blobs) -> void:
	var id := b.get_instance_id()
	if _drawn.has(id):
		_free(id)
		if _keys.get(b.key, -1) == id:
			_keys.erase(b.key)


func _free(id: int) -> void:
	for mmi: Node in _drawn[id]:
		mmi.queue_free()
	_drawn.erase(id)
	_dirty = true


## The weather and the light this frame (RealLook.apply_daylight): how strong
## cloud shadows are (none in rain, where the whole sky is one grey cloud and
## the sun is already dimmed), how green the light under leaves is, and how far
## the sun's real shadow maps reach (beyond them the canopy map shades the sun too).
func set_light(rain: float, leaf_green: float, shadow_reach: float) -> void:
	_amount = Vector4(1.0, CLOUD_SHADOW * (1.0 - rain), leaf_green, shadow_reach)
	if _off.x > 0.5:
		_amount = Vector4.ZERO
	_amount.x *= 1.0 - _off.y
	_amount.y *= 1.0 - _off.z


## Every frame (RealLook.update): move the maps with the eye.
func update(eye: Vector3) -> void:
	var e := Vector2(eye.x, eye.z)
	var near_m := float(_maps.near_m)
	var far_m := float(_maps.far_m)
	var near_size := float(_maps.near) * near_m
	var far_size := float(_maps.far) * far_m
	if absf(e.x - _near_mid.x) > NEAR_STEP or absf(e.y - _near_mid.y) > NEAR_STEP:
		_near_mid = (e / (near_m * 16.0)).round() * near_m * 16.0
		_dirty = true
	if absf(e.x - _far_mid.x) > FAR_STEP or absf(e.y - _far_mid.y) > FAR_STEP:
		_far_mid = (e / (far_m * 16.0)).round() * far_m * 16.0
		_dirty = true
	var near_corner := _near_mid - Vector2.ONE * near_size * 0.5
	var far_corner := _far_mid - Vector2.ONE * far_size * 0.5
	if _dirty:
		_dirty = false
		_near_mat.set_shader_parameter("origin", near_corner)
		_far_mat.set_shader_parameter("origin", far_corner)
		_near.render_target_update_mode = SubViewport.UPDATE_ONCE
		_far.render_target_update_mode = SubViewport.UPDATE_ONCE
		# Where each map gives way: inside what the map surely covers until it moves again.
		RenderingServer.global_shader_parameter_set("shade_near_at", Vector4(near_corner.x, near_corner.y, 1.0 / near_size, near_size * 0.5 - NEAR_STEP - 4.0))
		RenderingServer.global_shader_parameter_set("shade_far_at", Vector4(far_corner.x, far_corner.y, 1.0 / far_size, far_size * 0.5 - FAR_STEP - 8.0))
	# The cloud map: on the eye, a texel at a time, at the eye's height; drawn
	# every third frame (clouds drift a few decimetres in that time). Where it
	# lies changes only on a frame it is drawn, so map and reader agree.
	_cloud_tick = (_cloud_tick + 1) % CLOUD_EVERY
	if _cloud_tick == 0 and _off.x < 0.5:
		var cloud_m := float(_maps.cloud_m)
		var cloud_size := float(_maps.cloud) * cloud_m
		var cc := (e / cloud_m).round() * cloud_m - Vector2.ONE * cloud_size * 0.5
		cloud_mat.set_shader_parameter("corner_km", cc / 1000.0)
		cloud_mat.set_shader_parameter("size_km", cloud_size / 1000.0)
		cloud_mat.set_shader_parameter("ref_km", 0.25 + eye.y / 1000.0)
		_cloud.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.global_shader_parameter_set("shade_cloud_at", Vector4(cc.x, cc.y, 1.0 / cloud_size, eye.y))
	RenderingServer.global_shader_parameter_set("shade_amount", _amount)
	if _debug_frames > 0:
		_debug_frames -= 1
		if _debug_frames == 0:
			_save_debug()
	RenderingServer.global_shader_parameter_set("shade_trees", Vector4(eye.x, eye.z, RealFlora.tree_far, RealFlora.tree_far_z))


## Preview tool (`shademaps`): the three maps as pictures in build/ (cover x0.5 in red, contact in green).
func _save_debug() -> void:
	print("[shade] amount %s near mid %s far mid %s cloud corner %s ready %s wind %s cov %s" % [_amount, _near_mid, _far_mid, cloud_mat.get_shader_parameter("corner_km"), cloud_mat.get_shader_parameter("ready"), cloud_mat.get_shader_parameter("wind"), cloud_mat.get_shader_parameter("coverage")])
	for pair: Array in [[_near, "near"], [_far, "far"], [_cloud, "cloud"]]:
		var img := (pair[0] as SubViewport).get_texture().get_image()
		img.convert(Image.FORMAT_RGBAF)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * 0.5, c.g, c.b, 1.0) if pair[1] != "cloud" else Color(c.r, c.r, c.r, 1.0))
		img.convert(Image.FORMAT_RGB8)
		img.save_png("res://build/shade_map_%s.png" % pair[1])
