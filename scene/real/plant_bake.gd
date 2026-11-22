class_name PlantBake
extends RefCounted
## Draws plants into textures on the graphics card, at startup:
##  - the leaf atlas (once per app run): PlantGen's clusters of leaves, spruce
##    boughs and twigs, seen from above, which the trees' cards then show;
##  - a biome's flat pictures ("impostors"): every tree variant seen from
##    ANGLES directions round its trunk, which stand in for the tree far away.
## Each is two textures: colour, and "data" (rg the surface's normal as the
## camera saw it, b shade and leafiness, a how much of the texel is covered).
## Drawing happens at once (RenderingServer.force_draw), so callers get
## finished textures; headless runs (the tests) have no renderer and get none.

const CELL_PX := 512            ## one leaf-atlas cell
const ANGLES := 12              ## pictures round each tree
const PICTURE_W := 128          ## one picture's width in pixels (its height follows the tree's shape)

static var leaf_albedo: Texture2D
static var leaf_data: Texture2D
static var _twins: Dictionary = {}     # "<material id>:<channel>" -> its bake twin
static var _flat: ShaderMaterial


static func available() -> bool:
	return DisplayServer.get_name() != "headless" and Engine.get_main_loop() is SceneTree


## The leaf atlas, drawn on first use. False when there is no renderer.
static func ensure_leaf_atlas() -> bool:
	if leaf_albedo != null:
		return true
	if not available():
		return false
	var t0 := Time.get_ticks_msec()
	var cells := PlantGen.atlas_cells()
	var mats: Array[ShaderMaterial] = []
	for ch in 2:
		var m := ShaderMaterial.new()
		m.shader = load("res://scene/real/leaf_atlas_bake.gdshader")
		m.set_shader_parameter("bake_channel", ch)
		mats.append(m)
	var items := []
	var backs := []
	for i in cells.size():
		var col := i % PlantGen.ATLAS_COLS
		var row := i / PlantGen.ATLAS_COLS
		# Row 0 is the top of the picture; the camera's up is +y.
		var base := Vector3(col + 0.5, PlantGen.ATLAS_ROWS - 1 - row, 0.0)
		backs.append({"rect": Rect2(col, PlantGen.ATLAS_ROWS - 1 - row, 1.0, 1.0), "color": Color(0.62, 0.62, 0.56)})
		if cells[i] != null:
			items.append({"mesh": cells[i], "xf": Transform3D(Basis.IDENTITY, base), "mats": [[mats[0], mats[1]]]})
	var size := Vector2i(PlantGen.ATLAS_COLS, PlantGen.ATLAS_ROWS) * CELL_PX
	var imgs := render(size, Vector2(PlantGen.ATLAS_COLS, PlantGen.ATLAS_ROWS), items, backs, 1)
	if imgs.is_empty():
		return false
	leaf_albedo = ImageTexture.create_from_image(imgs[0])
	leaf_data = ImageTexture.create_from_image(imgs[1])
	if OS.is_debug_build():
		print("[bake] leaf atlas %s in %d ms" % [size, Time.get_ticks_msec() - t0])
		if OS.get_cmdline_user_args().has("dump-atlas"):
			imgs[0].save_png("res://build/atlas_leaf_albedo.png")
			imgs[1].save_png("res://build/atlas_leaf_data.png")
	return true


## Flat pictures of trees. variants: [{mesh: Mesh, color: Color (its foliage, for
## the backdrop)}]. Each tree gets a row of ANGLES pictures PICTURE_W wide and
## as tall as its shape needs. Returns {albedo, data: Texture2D, sizes:
## PackedVector3Array (per variant: picture width and height in metres, and
## where its bottom edge sits against the tree's root), rows: PackedVector2Array
## (per variant: its row's top and height in the atlas, 0..1)}, or {} with no renderer.
static func impostors(variants: Array) -> Dictionary:
	if variants.is_empty() or not available():
		return {}
	var t0 := Time.get_ticks_msec()
	var sizes := PackedVector3Array()
	var px := PackedInt32Array()          # each row's height in pixels
	var total := 0
	for v: Dictionary in variants:
		var mesh: Mesh = v.mesh
		# The picture must hold the tree from any side: its reach from the trunk, and its height.
		var reach := 0.1
		var lo := 0.0
		var hi := 0.1
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in verts:
				reach = maxf(reach, Vector2(p.x, p.z).length())
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
		var w := reach * 2.0 * 1.05
		var rows_px := mini(int(ceil((hi - lo) * 1.03 / w * PICTURE_W / 4.0)) * 4, PICTURE_W * 2)
		w = maxf(w, (hi - lo) * 1.03 * PICTURE_W / float(rows_px))
		sizes.append(Vector3(w, w * float(rows_px) / PICTURE_W, lo))
		px.append(rows_px)
		total += rows_px
	# World units: one picture is 1 wide; the camera's up is +y, row 0 at the top.
	var world := Vector2(float(ANGLES), float(total) / PICTURE_W)
	var items := []
	var backs := []
	var rows := PackedVector2Array()
	var top := 0
	for r in variants.size():
		var mesh: Mesh = variants[r].mesh
		var w := sizes[r].x
		var h := float(px[r]) / PICTURE_W
		var y := world.y - float(top) / PICTURE_W - h
		rows.append(Vector2(float(top) / float(total), float(px[r]) / float(total)))
		top += px[r]
		var mats := []
		for s in mesh.get_surface_count():
			var live := mesh.surface_get_material(s) as ShaderMaterial
			mats.append([twin(live, 0), twin(live, 1)])
		for k in ANGLES:
			# Picture k: the tree turned so the side facing direction k (round from +z toward +x) faces the camera.
			var basis := Basis(Vector3.UP, -TAU * float(k) / float(ANGLES)).scaled(Vector3.ONE / w)
			items.append({"mesh": mesh, "xf": Transform3D(basis, Vector3(float(k) + 0.5, y - sizes[r].z / w, 0.0)), "mats": mats})
		backs.append({"rect": Rect2(0.0, y, float(ANGLES), h), "color": variants[r].color})
	var size := Vector2i(PICTURE_W * ANGLES, total)
	var imgs := render(size, world, items, backs, 2)
	if imgs.is_empty():
		return {}
	if OS.is_debug_build():
		print("[bake] %d tree pictures %s in %d ms" % [variants.size(), size, Time.get_ticks_msec() - t0])
		if OS.get_cmdline_user_args().has("dump-atlas"):
			imgs[0].save_png("res://build/atlas_trees_albedo.png")
			imgs[1].save_png("res://build/atlas_trees_data.png")
	return {"albedo": ImageTexture.create_from_image(imgs[0]), "data": ImageTexture.create_from_image(imgs[1]), "sizes": sizes, "rows": rows}


## A live plant material's bake twin (its shader's *_bake version, same settings).
static func twin(live: ShaderMaterial, channel: int) -> ShaderMaterial:
	var key := "%d:%d" % [live.get_instance_id(), channel]
	if _twins.has(key):
		return _twins[key]
	var m := ShaderMaterial.new()
	m.shader = load(live.shader.resource_path.replace(".gdshader", "_bake.gdshader"))
	for u in live.shader.get_shader_uniform_list():
		var v: Variant = live.get_shader_parameter(u.name)
		if v != null:
			m.set_shader_parameter(u.name, v)
	m.set_shader_parameter("bake_channel", channel)
	_twins[key] = m
	return m


## Draw `items` ([{mesh, xf, mats: per surface [colour material, data material]}])
## with a camera looking down -z at the rectangle (0, 0)..world, over plain
## `backdrops` ([{rect, color}]: colour only, so a picture's edge blurs into its
## own colour in the small copies). `oversample` 2 draws at twice the size and
## halves it (cards' cut-out edges get no help from MSAA).
## Returns [colour (RGB8, sRGB, mipmaps), data (RGBA8, linear, mipmaps)].
static func render(size: Vector2i, world: Vector2, items: Array, backdrops: Array, oversample: int) -> Array:
	if not available():
		return []
	var root := (Engine.get_main_loop() as SceneTree).root
	var views: Array[SubViewport] = []
	for ch in 2:
		var vp := SubViewport.new()
		vp.size = size * oversample
		vp.own_world_3d = true
		vp.transparent_bg = ch == 1
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var cam := Camera3D.new()
		cam.environment = env
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.size = world.y
		cam.near = 1.0
		cam.far = 100.0
		cam.position = Vector3(world.x * 0.5, world.y * 0.5, 50.0)
		cam.current = true
		vp.add_child(cam)
		for it: Dictionary in items:
			var mi := MeshInstance3D.new()
			mi.mesh = it.mesh
			mi.transform = it.xf
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in (it.mats as Array).size():
				mi.set_surface_override_material(s, it.mats[s][ch])
			vp.add_child(mi)
		if ch == 0:
			vp.add_child(_backdrop(backdrops))
		root.add_child(vp)
		if not vp.is_inside_tree():
			# The window is still setting up its own children: no bake this time.
			vp.free()
			for v in views:
				v.queue_free()
			return []
		# Transforms normally reach the renderer at the end of the frame; this draw is now.
		for child in vp.get_children():
			(child as Node3D).force_update_transform()
		views.append(vp)
	RenderingServer.force_draw(false)
	var out := []
	for ch in 2:
		var img := views[ch].get_texture().get_image()
		views[ch].queue_free()
		if img == null or img.is_empty():
			return []
		img.convert(Image.FORMAT_RGBA8)
		if ch == 1:
			img.srgb_to_linear()      # the data went through the screen's colour curve on its way out
		for i in oversample - 1:
			img.shrink_x2()
		if ch == 0:
			img.convert(Image.FORMAT_RGB8)
		img.generate_mipmaps()
		out.append(img)
	return out


static func _backdrop(backdrops: Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in backdrops:
		var r: Rect2 = b.rect
		st.set_color(b.color)
		for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, r.position, r.end, Vector2(r.position.x, r.end.y)]:
			st.add_vertex(Vector3(p.x, p.y, -40.0))
	if _flat == null:
		_flat = ShaderMaterial.new()
		_flat.shader = load("res://scene/real/flat_color.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _flat
	return mi
