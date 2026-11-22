class_name RealGrass
extends Node3D
## The realistic look's meadow. Instead of baking grass into every terrain
## chunk, three rings of tufts follow the eye: fine blades within a few metres,
## coarser tufts to ~30 m, broad sparse ones to ~56 m. Each ring is a square
## block of small tiles that all share one MultiMesh (a grid of tuft slots) and
## step along with the eye a tile at a time; only the tiles its ring actually
## reaches are shown. The shader makes every tuft from its slot's place in the
## world, so nothing changes as tiles step, and thins tufts out with distance
## one by one (real_grass.gdshader).
## What the shader cannot know, the ground, is kept in a small "field" texture
## round the eye, one texel a metre: height, distance from the trail, how thick
## grass grows there (none in water, little in snow) and which biome's grass it
## is. It scrolls with the rider: only the rows that come into range are worked out.

const FIELD := 128                 ## texels across the field texture (metres)
const BUDGET_USEC := 1200          ## time a frame may spend filling the field
## The rings: tile size and tiles a side, slot pitch, blades a tuft, rows a
## blade, blade width, tuft radius, where it grows in (over `fade` metres) and
## where it is gone.
const RINGS := [
	{"tile": 4.0, "side": 6, "pitch": 0.25, "blades": 5, "rows": 3, "width": 0.011, "radius": 0.16, "in": 0.0, "out": 9.0, "fade": 3.0, "flower": 0.8},
	{"tile": 10.0, "side": 8, "pitch": 0.625, "blades": 4, "rows": 2, "width": 0.028, "radius": 0.34, "in": 9.0, "out": 30.0, "fade": 8.0, "flower": 1.3},
	{"tile": 20.0, "side": 8, "pitch": 1.25, "blades": 5, "rows": 1, "width": 0.06, "radius": 0.6, "in": 30.0, "out": 56.0, "fade": 8.0, "flower": 0.0},
]

var terrain: TerrainStreamer
var _image: Image
var _texture: ImageTexture
var _origin := Vector2i(1 << 30, 0)   ## the field's lowest corner (world metres)
var _rows: Array[Vector3i] = []       ## rows and columns waiting to be worked out: (axis 0 x / 1 z, index, how far along it is done)
var _tiles: Array = []                ## per ring: its MultiMeshInstance3Ds
var _cells: Array[Vector2i] = []      ## per ring: the tile the eye was last in
var _eye := Vector3(INF, INF, INF)    ## where the eye was when the tiles were last sorted out
var _materials: Array[ShaderMaterial] = []
var _first := true


func _init(t: TerrainStreamer, noise: Texture2D, biomes: Array[String]) -> void:
	terrain = t
	name = "RealGrass"
	_image = Image.create(FIELD, FIELD, false, Image.FORMAT_RGBAF)
	_texture = ImageTexture.create_from_image(_image)
	var shader := load("res://scene/real/real_grass.gdshader") as Shader
	# Each biome's grass (the field says which one a spot has).
	var tips := PackedVector3Array()
	var heights := PackedFloat32Array()
	var shares := PackedFloat32Array()
	var matched := PackedFloat32Array()
	var counts := PackedFloat32Array()
	var flowers := PackedVector3Array()
	flowers.resize(32)
	for i in 8:
		var b: Dictionary = RealFlora.BIOMES[biomes[mini(i, biomes.size() - 1)]]
		var c: Color = b.grass
		tips.append(Vector3(c.r, c.g, c.b))
		heights.append(float(b.grass_h))
		var fl: Array = b.get("flowers", [])
		shares.append(float(b.get("flower_share", 0.0)))
		counts.append(float(mini(fl.size(), 4)))
		matched.append(1.0 if str(b.get("ground", "grass")) == "grass" else 0.0)
		for k in mini(fl.size(), 4):
			flowers[i * 4 + k] = Vector3(fl[k].r, fl[k].g, fl[k].b)
	for r in RINGS.size():
		var ring: Dictionary = RINGS[r]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("field", _texture)
		mat.set_shader_parameter("noise_tex", noise)
		mat.set_shader_parameter("field_size", float(FIELD))
		mat.set_shader_parameter("pitch", ring.pitch)
		mat.set_shader_parameter("fade_in", ring["in"])
		mat.set_shader_parameter("fade_out", ring.out)
		mat.set_shader_parameter("fade_width", ring.fade)
		mat.set_shader_parameter("fade_in_width", 3.0 if r == 1 else float(ring.fade))
		mat.set_shader_parameter("blade_width", ring.width)
		mat.set_shader_parameter("tuft_radius", ring.radius)
		mat.set_shader_parameter("trail_half_width", TerrainStreamer.TRAIL_HALF_WIDTH)
		mat.set_shader_parameter("groove_depth", TerrainStreamer.GROOVE_DEPTH)
		mat.set_shader_parameter("bank_width", TerrainStreamer.BANK_WIDTH)
		mat.set_shader_parameter("tip_color", tips)
		mat.set_shader_parameter("blade_height", heights)
		mat.set_shader_parameter("flower_share", shares)
		mat.set_shader_parameter("flower_count", counts)
		mat.set_shader_parameter("on_grass", matched)
		mat.set_shader_parameter("flower_color", flowers)
		_materials.append(mat)
		var mm := _slots(float(ring.tile), float(ring.pitch), _tuft(ring, mat))
		var ring_tiles: Array[MultiMeshInstance3D] = []
		for i in int(ring.side) * int(ring.side):
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# The shader lifts the tufts onto the ground: allow for hills within a tile.
			mmi.custom_aabb = AABB(Vector3(-1.0, -40.0, -1.0), Vector3(float(ring.tile) + 2.0, 80.0, float(ring.tile) + 2.0))
			mmi.add_to_group("grass")
			mmi.add_to_group("grass_ring%d" % _tiles.size())
			add_child(mmi)
			ring_tiles.append(mmi)
		_tiles.append(ring_tiles)
		_cells.append(Vector2i(1 << 30, 0))


## One tuft: blades fanned out from a small patch, and a flower head (shown on few).
## Vertex data for the shader: VERTEX the blade's foot in the tuft (-1..1),
## UV x across the blade (-1, 1; 0 at the tip) and y along it, UV2 x the way it
## leans (radians) and y its height share, COLOR r bend, g width share (a flower:
## its corner), b 1 on a flower head, a a little shade of its own.
static func _tuft(ring: Dictionary, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + int(float(ring.tile))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rows := int(ring.rows)
	for i in int(ring.blades):
		var a := rng.randf() * TAU
		var foot := Vector3(cos(a), 0.0, sin(a)) * sqrt(rng.randf())
		var lean := a + rng.randf_range(-0.7, 0.7)
		var tall := rng.randf_range(0.55, 1.15)
		var c := Color(rng.randf_range(0.15, 0.75), rng.randf_range(0.7, 1.2), 0.0, rng.randf())
		var first := verts.size()
		for r in rows:
			var k := float(r) / float(rows) * (0.9 if rows > 1 else 1.0)
			for s: float in [-1.0, 1.0]:
				verts.append(foot)
				uvs.append(Vector2(s, k))
				uv2s.append(Vector2(lean, tall))
				cols.append(c)
		verts.append(foot)
		uvs.append(Vector2(0.0, 1.0))
		uv2s.append(Vector2(lean, tall))
		cols.append(c)
		for r in rows - 1:
			var q := first + r * 2
			idx.append_array(PackedInt32Array([q, q + 2, q + 1, q + 1, q + 2, q + 3]))
		var top := first + (rows - 1) * 2
		idx.append_array(PackedInt32Array([top, top + 2, top + 1]))
	if float(ring.flower) > 0.0:
		# A small six-sided head on the first blade's line.
		var first := verts.size()
		for k in 7:
			var a := TAU * float(k - 1) / 6.0
			var corner := Vector2.ZERO if k == 0 else Vector2(cos(a), sin(a))
			verts.append(Vector3.ZERO)
			uvs.append(Vector2(corner.x, 1.0))
			uv2s.append(Vector2(0.0, 1.0))
			cols.append(Color(0.2, corner.y * 0.5 + 0.5, 1.0, 0.5 * float(ring.flower)))
		for k in 6:
			idx.append_array(PackedInt32Array([first, first + 1 + k, first + 1 + (k + 1) % 6]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


## A tile's worth of tuft slots on the grid.
static func _slots(tile: float, pitch: float, mesh: Mesh) -> MultiMesh:
	var n := int(round(tile / pitch))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n * n
	for j in n:
		for i in n:
			mm.set_instance_transform(j * n + i, Transform3D(Basis.IDENTITY, Vector3((i + 0.5) * pitch, 0.0, (j + 0.5) * pitch)))
	return mm


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	if eye.distance_squared_to(_eye) > 0.25:
		_eye = eye
		_place_tiles(eye)
	_scroll_field(Vector2i(roundi(eye.x), roundi(eye.z)))
	_fill_field(Vector2(eye.x, eye.z))


## Step each ring's tiles to stay centred on the eye, and show only the tiles
## its tufts can stand in (between where the ring grows in and where it ends).
func _place_tiles(eye: Vector3) -> void:
	for r in RINGS.size():
		var ring: Dictionary = RINGS[r]
		var tile := float(ring.tile)
		var side := int(ring.side)
		var cell := Vector2i(roundi(eye.x / tile), roundi(eye.z / tile))
		var ring_tiles: Array = _tiles[r]
		if cell != _cells[r] or absf(eye.y - (ring_tiles[0] as Node3D).global_position.y) > 16.0:
			_cells[r] = cell
			for i in ring_tiles.size():
				(ring_tiles[i] as Node3D).global_position = Vector3((cell.x - side / 2 + i % side) * tile, eye.y, (cell.y - side / 2 + i / side) * tile)
		var inner := float(ring["in"]) - (3.0 if r == 1 else float(ring.fade))
		for i in ring_tiles.size():
			var node := ring_tiles[i] as Node3D
			var lo := Vector2(node.global_position.x, node.global_position.z)
			var e := Vector2(eye.x, eye.z)
			var near := e.clamp(lo, lo + Vector2(tile, tile)).distance_to(e)
			var far := maxf(maxf(e.distance_to(lo), e.distance_to(lo + Vector2(tile, tile))), maxf(e.distance_to(lo + Vector2(tile, 0.0)), e.distance_to(lo + Vector2(0.0, tile))))
			node.visible = near < float(ring.out) and far > inner


## Move the field with the eye; rows and columns that come into range are
## emptied (no grass) and queued for working out.
func _scroll_field(centre: Vector2i) -> void:
	var origin := centre - Vector2i(FIELD / 2, FIELD / 2)
	if origin == _origin:
		return
	var old := _origin
	_origin = origin
	if absi(origin.x - old.x) >= FIELD or absi(origin.y - old.y) >= FIELD:
		_image.fill(Color(0, 0, 0, 0))
		_rows.clear()
		for z in range(origin.y, origin.y + FIELD):
			_rows.append(Vector3i(1, z, -(1 << 30)))
		return
	var xs := range(old.x + FIELD, origin.x + FIELD) if origin.x > old.x else range(origin.x, old.x)
	for x: int in xs:
		_image.fill_rect(Rect2i(posmod(x, FIELD), 0, 1, FIELD), Color(0, 0, 0, 0))
		_rows.append(Vector3i(0, x, -(1 << 30)))
	var zs := range(old.y + FIELD, origin.y + FIELD) if origin.y > old.y else range(origin.y, old.y)
	for z: int in zs:
		_image.fill_rect(Rect2i(0, posmod(z, FIELD), FIELD, 1), Color(0, 0, 0, 0))
		_rows.append(Vector3i(1, z, 0))


## Work out waiting rows, nearest the eye first, within this frame's time (a
## row can stop part way and carry on next frame: its z says how far it got).
func _fill_field(eye: Vector2) -> void:
	if _rows.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var budget := BUDGET_USEC * (40 if _first else 1)     # the first frame may take longer: grass at once
	_first = false
	_rows.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return absf(float(a.y) - (eye.x if a.x == 0 else eye.y)) > absf(float(b.y) - (eye.x if b.x == 0 else eye.y)))
	while not _rows.is_empty() and Time.get_ticks_usec() - t0 < budget:
		var job: Vector3i = _rows.pop_back()
		var along_x := job.x == 1                 # a row of constant z runs along x
		var lo := _origin.x if along_x else _origin.y
		var fixed_lo := _origin.y if along_x else _origin.x
		if job.y < fixed_lo or job.y >= fixed_lo + FIELD:
			continue                              # left the field before its turn came
		var k := maxi(job.z, lo)
		while k < lo + FIELD:
			var x := k if along_x else job.y
			var z := job.y if along_x else k
			var g := terrain.grass_at(float(x), float(z))
			_image.set_pixel(posmod(x, FIELD), posmod(z, FIELD), Color(g.x, g.y, g.z, g.w))
			k += 1
			if k % 16 == 0 and Time.get_ticks_usec() - t0 >= budget:
				break
		if k < lo + FIELD:
			_rows.append(Vector3i(job.x, job.y, k))
	_texture.update(_image)
