class_name TerrainStreamer
extends Node3D
## Generates terrain chunks around the rider along the trail and recycles them
## behind. Each chunk is a flat-shaded height mesh with vertex colours plus a
## MultiMesh of scattered props (pines, shrubs, rocks) that avoid the trail.

const CHUNK_LEN := 24.0          # metres along Z
const HALF_WIDTH := 70.0         # metres either side of the trail
const RES := 2.0                 # metres per grid step
const AHEAD := 6                 # chunks kept ahead of the rider (~150 m; shorter = better hill timing)
const BEHIND := 2
const TRAIL_HALF_WIDTH := 0.75      # groomed fat-bike track, about 1.5 m wide
const GROOVE_DEPTH := 0.22
const BANK_WIDTH := 0.7
const BAND_WIDTH := 35.0               ## realistic look: plants are grouped in sideways bands this wide
const BAND_PAD := 25.0                 ## and reach this far from their band's middle
const SHOULDER := 4.0                 # smooth rideable snow either side before the rough field

var trail: Trail
var _chunks: Dictionary = {}     # chunk index -> Node3D
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _drift := FastNoiseLite.new()
var _far := FastNoiseLite.new()     # broad hills beyond the near field (only the realistic look reaches them)
var far_relief := 70.0              ## height of the broad far hills (metres); the desert's ranges are taller
var relief_from := 70.0             ## where those hills start (metres from the trail)
var hill_scale := 1.0               ## the near hillside's steepness (the desert floor is nearly flat)
var water := false                  ## realistic look: a river (widening into lakes) down the downhill side
var _river_noise := FastNoiseLite.new()
var _lake_noise := FastNoiseLite.new()
var _water_material: Material
var _fine_columns: PackedFloat64Array = []       # |x| <= 8 m: 0.2 m near the groove, then 0.5 m
var _coarse_columns_l: PackedFloat64Array = []   # -HALF_WIDTH .. -8 m at RES
var _coarse_columns_r: PackedFloat64Array = []   # 8 m .. HALF_WIDTH at RES
var _pending: Array[int] = []
var _thread: Thread
var density_scale := 1.0                 # tree density multiplier (new chunks only)
var _pines: Array[Mesh] = []      # variants; MeshLib procedural pine as fallback
var _rocks: Array[Mesh] = []
var _dead_trees: Array[Mesh] = []
var _cover: Array[Mesh] = []       # grass, flowers, mushrooms near the trail
var _cover_scale: Array[Vector2] = []   # min/max scale per cover mesh (the kit's flowers are huge at 1.0)
var _dead_share := 0.04
var _tree_scale := ScenePreset.DEFAULT_TREE_SCALE
var _density_mult := 1.0            # preset factor: open desert scatters far fewer "trees"
var _shrub_mesh: ArrayMesh
var _material: Material
var ahead_chunks := AHEAD           ## more in first person, which sees further down the trail
var real_ground := false            ## the realistic look: real_ground shader and procedural flora
var flora: RealFlora                ## the realistic look's plants and rocks (replaces the props)
const PINE_SCALE := Vector2(0.45, 0.8)   # Quaternius pines are ~7 m tall at scale 1


func _init(t: Trail) -> void:
	trail = t
	_noise.seed = 11
	_noise.frequency = 0.045
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.seed = 12
	_detail.frequency = 0.25
	_drift.seed = 13
	_drift.frequency = 0.07
	_drift.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_far.seed = 14
	_far.frequency = 0.0035
	_far.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_far.fractal_octaves = 4
	_river_noise.seed = 15
	_river_noise.frequency = 0.004
	_river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lake_noise.seed = 16
	_lake_noise.frequency = 0.0025
	_lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var x := -8.0
	while x < 8.0 - 0.001:
		_fine_columns.append(x)
		x += 0.2 if absf(x) < 3.0 else 0.5
	_fine_columns.append(8.0)
	x = -HALF_WIDTH
	while x < -8.0 - 0.001:
		_coarse_columns_l.append(x)
		x += RES
	_coarse_columns_l.append(-8.0)
	x = 8.0
	while x < HALF_WIDTH - 0.001:
		_coarse_columns_r.append(x)
		x += RES
	_coarse_columns_r.append(HALF_WIDTH)
	var preset := ScenePreset.get_preset(Palette.preset_id)
	var snow: bool = preset.prop_snow
	_dead_share = float(preset.dead_share)
	_density_mult = float(preset.get("tree_density", 1.0))
	if preset.has("tree_scale"):
		_tree_scale = Vector2(float(preset.tree_scale[0]), float(preset.tree_scale[1]))
	for n in preset.trees:
		var m := MeshLib.load_prop(ScenePreset.prop_path(n), snow)
		if m:
			_pines.append(m)
	for n in preset.rocks:
		var m := MeshLib.load_prop(ScenePreset.prop_path(n), snow)
		if m:
			_rocks.append(m)
	for n in preset.dead:
		var m := MeshLib.load_prop(ScenePreset.prop_path(n), false)
		if m:
			_dead_trees.append(m)
	for n in preset.cover:
		var m := MeshLib.load_prop(ScenePreset.prop_path(n), false)
		if m:
			_cover.append(m)
			if "Flower" in n or "Mushroom" in n:
				_cover_scale.append(Vector2(0.28, 0.45))
			elif "Grass" in n:
				_cover_scale.append(Vector2(0.45, 0.75))
			else:
				_cover_scale.append(Vector2(0.7, 1.1))
	if _pines.is_empty():
		_pines.append(MeshLib.pine())
	if _rocks.is_empty():
		_rocks.append(MeshLib.rock())
	_shrub_mesh = MeshLib.shrub()
	_material = MeshLib.cel_material(true)
	_material.set_shader_parameter("speckle", true)
	_material.set_shader_parameter("smooth_lighting", true)


## The realistic look's ground: one shader for field, trail and rock, fed the
## distance from the trail centre through UV.x. Call before the first update.
func use_real_ground(kind: String, plants: RealFlora) -> void:
	real_ground = true
	flora = plants
	ahead_chunks = 16                 # built ~380 m out, beyond where trees fade in
	var kind_water := str(plants.biome.get("water", ""))
	water = kind_water != ""
	# First person sees far: carry the ground out to ~600 m either side, the
	# columns spreading out with distance (the hills there need no detail),
	# except across the river valley on the downhill side, kept at 3 m.
	var x := HALF_WIDTH
	var step := 4.0
	while x < 600.0:
		x += step
		step *= 1.22
		_coarse_columns_l.insert(0, -x)
	x = HALF_WIDTH
	step = 3.0
	while x < 600.0:
		x += step
		if x > 260.0 or not water:
			step *= 1.22
		_coarse_columns_r.append(x)
	if water:
		var wm := ShaderMaterial.new()
		wm.shader = load("res://scene/real/real_ice.gdshader" if kind_water == "ice" else "res://scene/real/real_water.gdshader")
		var wn := FastNoiseLite.new()
		wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		wn.fractal_octaves = 3
		wn.frequency = 0.02
		var wt := NoiseTexture2D.new()
		wt.width = 256
		wt.height = 256
		wt.seamless = true
		wt.as_normal_map = true
		wt.bump_strength = 6.0
		wt.noise = wn
		wt.generate_mipmaps = true
		wm.set_shader_parameter("ripples", wt)
		if plants.biome.has("water_tint"):
			wm.set_shader_parameter("deep", plants.biome.water_tint)
		_water_material = wm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scene/real/real_ground.gdshader")
	mat.set_shader_parameter("ground", {"snow": 0, "grass": 1, "sand": 2, "desert": 3}.get(kind, 0))
	# Desert: the far hills become jagged ranges (ridged noise, much taller), like the Catalinas over Tucson.
	far_relief = float(plants.biome.get("relief", far_relief))
	relief_from = float(plants.biome.get("relief_from", relief_from))
	hill_scale = float(plants.biome.get("hills", hill_scale))
	if plants.biome.has("relief"):
		_far.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		_far.frequency = 0.0028
	mat.set_shader_parameter("trail_half_width", TRAIL_HALF_WIDTH)
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_octaves = 4
	fn.frequency = 0.01
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = fn
	tex.generate_mipmaps = true
	var nrm := NoiseTexture2D.new()
	nrm.width = 512
	nrm.height = 512
	nrm.seamless = true
	nrm.as_normal_map = true
	nrm.bump_strength = 4.0
	nrm.noise = fn
	nrm.generate_mipmaps = true
	mat.set_shader_parameter("noise_tex", tex)
	mat.set_shader_parameter("noise_nrm", nrm)
	_material = mat


## The river at distance z: x = centre's offset from the trail (downhill side),
## y = half width, z = water level, w = depth. It meanders 40-85 m out and
## widens into a lake where the noise says so and its datum runs nearly flat.
func river(z: float, t: Trail = trail) -> Vector4:
	var slope := absf(t.river_base(z + 40.0) - t.river_base(z - 40.0)) / 80.0
	var lake := smoothstep(0.0, 0.3, _lake_noise.get_noise_1d(z)) * (1.0 - smoothstep(0.009, 0.02, slope))
	var bend := 62.0 + 24.0 * _river_noise.get_noise_1d(z)
	var half := 13.0 + 4.0 * _river_noise.get_noise_1d(z * 3.0 + 400.0) + lake * 60.0
	var level := t.river_base(z) - 0.18 * bend - 1.2
	return Vector4(bend + lake * 62.0, half, level, 2.2 + lake * 4.0)


## How far a point is into the river, in half widths (< 1 is water); 99 without water.
func water_depth_u(x: float, z: float, t: Trail = trail) -> float:
	if not water:
		return 99.0
	var r := river(z, t)
	return absf(x - t.x_at(z) - r.x) / r.y


## The water's own ground: the river bed dips under the level, banks climb
## back out at 30 %; the land is only ever lowered to meet them.
func _carve_river(h: float, d: float, z: float, t: Trail) -> float:
	var r := river(z, t)
	var u := absf(d - r.x) / r.y
	if u > 8.0:
		return h
	var target := r.z - r.w * (1.0 - u * u) if u < 1.0 else r.z + (u - 1.0) * r.y * 0.3
	return minf(h, target)


## Terrain height at any point: the trail's own height on the trail, rising
## into a hillside on the left and dropping away on the right, with noise.
func height(x: float, z: float, t: Trail = trail) -> float:
	var tx := t.x_at(z)
	var d := x - tx
	var ad := absf(d)
	var base := t.h_at(z)
	# Groomed groove with a small bank on each side.
	var groove := 0.0
	if ad < TRAIL_HALF_WIDTH:
		groove = -GROOVE_DEPTH * (1.0 - pow(ad / TRAIL_HALF_WIDTH, 2.0))
	elif ad < TRAIL_HALF_WIDTH + BANK_WIDTH:
		groove = 0.09 * sin(PI * (ad - TRAIL_HALF_WIDTH) / BANK_WIDTH)
	var off := smoothstep(TRAIL_HALF_WIDTH + BANK_WIDTH, TRAIL_HALF_WIDTH + SHOULDER, ad)
	var rough_fade := smoothstep(SHOULDER, SHOULDER + 18.0, ad)
	var rough := (_noise.get_noise_2d(x, z) * 2.2 + _detail.get_noise_2d(x, z) * 0.12) * rough_fade
	var drifts := _drift.get_noise_2d(x, z) * 0.25 * smoothstep(TRAIL_HALF_WIDTH + BANK_WIDTH, SHOULDER, ad)
	base += groove + drifts
	var hillside := 0.0
	if d < 0.0:
		hillside = (ad - TRAIL_HALF_WIDTH) * 0.32 + pow(maxf(ad - 25.0, 0.0), 1.3) * 0.18   # uphill side
	else:
		hillside = -(ad - TRAIL_HALF_WIDTH) * 0.18                                          # downhill side
	hillside *= hill_scale
	if ad > 70.0:
		# Beyond the near field: the downhill side levels into a valley floor, the
		# uphill side stops climbing at a ridge, and broad hills roll over both.
		var far := smoothstep(relief_from, relief_from + 190.0 + far_relief * 0.6, ad)
		if d < 0.0:
			hillside = minf(hillside, 70.0 + (ad - 70.0) * 0.25)
		else:
			hillside = -(minf(ad, 150.0) - TRAIL_HALF_WIDTH) * 0.18
		hillside += (_far.get_noise_2d(x, z) * 0.5 + 0.5) * far_relief * far
	var h := base + off * (rough + hillside)
	if water and d > 20.0:
		h = _carve_river(h, d, z, t)
	return h


## Drop every chunk so the next update regenerates them (after a density change).
func rebuild() -> void:
	for key in _chunks.keys():
		_chunks[key].queue_free()
	_chunks.clear()
	_pending.clear()


func update_around(z: float) -> void:
	var center := int(floor(z / CHUNK_LEN))
	# Ground under and just ahead of the rider must exist this frame, even if
	# the worker is behind (fast-forward, first frame): build those in place.
	for i in [center, center + 1]:
		if not _chunks.has(i):
			_pending.erase(i)
			trail.h_at((i + 2) * CHUNK_LEN + 4.0)
			_finish_chunk(_build_chunk_arrays(i, trail.snapshot()))
	for i in range(center - BEHIND, center + ahead_chunks + 1):
		if not _chunks.has(i) and not _pending.has(i):
			_pending.append(i)
	for key in _chunks.keys():
		if key < center - BEHIND or key > center + ahead_chunks:
			_chunks[key].queue_free()
			_chunks.erase(key)
	_pump()


## Chunk builds run on a worker thread one at a time; the main thread only
## turns finished arrays into meshes. Nearest chunks first.
func _pump() -> void:
	if _thread != null:
		if _thread.is_alive():
			return
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		_finish_chunk(result)
	if _pending.is_empty():
		return
	_pending.sort()
	var index: int = _pending.pop_front()
	# Extend the real trail past this chunk on the main thread, then give the
	# worker a private snapshot so no array is shared across threads.
	trail.h_at((index + 2) * CHUNK_LEN + 4.0)
	var snap := trail.snapshot()
	_thread = Thread.new()
	_thread.start(_build_chunk_arrays.bind(index, snap))


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_pump()


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()


## Worker: all geometry and scatter math for one chunk, no scene-tree access.
func _build_chunk_arrays(index: int, t: Trail) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var z0 := index * CHUNK_LEN
	var out := {"index": index, "z0": z0}
	# Fine strip around the trail (0.2 m columns within 3 m, 0.5 m to 8 m; 0.5 m rows),
	# coarse field beyond (2 m grid). Heights are sampled once per grid vertex.
	out["fine"] = _grid_arrays(z0, _fine_columns, 0.5, t)
	out["coarse_l"] = _grid_arrays(z0, _coarse_columns_l, RES, t)
	out["coarse_r"] = _grid_arrays(z0, _coarse_columns_r, RES, t)
	if flora:
		out["flora"] = flora.scatter(z0, CHUNK_LEN, HALF_WIDTH, TRAIL_HALF_WIDTH + BANK_WIDTH, t, height, water_depth_u)
	if water:
		out["water"] = _water_arrays(z0, t)
	else:
		out["scatter"] = _scatter_transforms(z0, t)
	out["usec"] = Time.get_ticks_usec() - t0
	return out


## The river's surface for one chunk: a ribbon across its width (a little over,
## tucked under the banks), one row every 2 m. UV in metres: x across, y along.
func _water_arrays(z0: float, t: Trail) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var cols := 12
	var rows := int(CHUNK_LEN / 2.0)
	for i in rows + 1:
		var z := z0 + i * 2.0
		var rv := river(z, t)
		var cx := t.x_at(z) + rv.x
		for c in cols + 1:
			var s := lerpf(-1.12, 1.12, float(c) / cols)
			verts.append(Vector3(cx + s * rv.y, rv.z, z))
			norms.append(Vector3.UP)
			uvs.append(Vector2(s * rv.y, z))
	for i in rows:
		for c in cols:
			var a := i * (cols + 1) + c
			var b := a + cols + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	return {"verts": verts, "norms": norms, "uvs": uvs, "idx": idx}


## Vertex/normal/colour arrays for a grid of columns (offsets from the trail centre) × rows.
func _grid_arrays(z0: float, cols: PackedFloat64Array, row: float, t: Trail) -> Dictionary:
	var nz := int(CHUNK_LEN / row)
	var ncols := cols.size()
	# Sample heights on a (nz+1) × ncols lattice, with one extra ring for normals.
	var hs := PackedFloat64Array()
	hs.resize((nz + 3) * (ncols + 2))
	var xs := PackedFloat64Array()
	xs.resize((nz + 3) * (ncols + 2))
	var fine := row < RES - 0.001
	for iz in nz + 3:
		var zz := z0 + (iz - 1) * row
		var cx := t.x_at(zz)
		for ic in ncols + 2:
			var col_off := cols[clampi(ic - 1, 0, ncols - 1)] + (-(RES) if ic == 0 else (RES if ic == ncols + 1 else 0.0))
			var xx := cx + col_off
			var hh := height(xx, zz, t)
			if fine and (ic == 1 or ic == ncols):
				# Seam with the coarse field: this edge must be the coarse mesh's
				# straight edge, so interpolate between the coarse rows bracketing zz
				# instead of sampling here (otherwise T-junction cracks show the sky).
				var zc0 := z0 + floorf((zz - z0) / RES) * RES
				var f := (zz - zc0) / RES
				var xa := t.x_at(zc0) + col_off
				var xb := t.x_at(zc0 + RES) + col_off
				xx = lerpf(xa, xb, f)
				hh = lerpf(height(xa, zc0, t), height(xb, zc0 + RES, t), f)
			xs[iz * (ncols + 2) + ic] = xx
			hs[iz * (ncols + 2) + ic] = hh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()       # x: offset from the trail centre (the realistic ground uses it)
	var W := ncols + 2
	for iz in range(1, nz + 1):
		for ic in range(1, ncols):
			var p00 := Vector3(xs[iz * W + ic], hs[iz * W + ic], z0 + (iz - 1) * row)
			var p10 := Vector3(xs[iz * W + ic + 1], hs[iz * W + ic + 1], z0 + (iz - 1) * row)
			var p01 := Vector3(xs[(iz + 1) * W + ic], hs[(iz + 1) * W + ic], z0 + iz * row)
			var p11 := Vector3(xs[(iz + 1) * W + ic + 1], hs[(iz + 1) * W + ic + 1], z0 + iz * row)
			var n00 := _grid_normal(hs, xs, W, iz, ic, row)
			var n10 := _grid_normal(hs, xs, W, iz, ic + 1, row)
			var n01 := _grid_normal(hs, xs, W, iz + 1, ic, row)
			var n11 := _grid_normal(hs, xs, W, iz + 1, ic + 1, row)
			# Per-vertex colours: zones (trail, bank, snow) blend across each triangle
			# instead of switching at polygon edges.
			var c00 := _color_for_slope(p00, n00, t)
			var c10 := _color_for_slope(p10, n10, t)
			var c01 := _color_for_slope(p01, n01, t)
			var c11 := _color_for_slope(p11, n11, t)
			# Clockwise front faces (see MeshLib.tri).
			for tri in [[p00, n00, c00, p10, n10, c10, p11, n11, c11], [p00, n00, c00, p11, n11, c11, p01, n01, c01]]:
				# The realistic ground culls back faces, so it needs Godot's own front-face winding.
				var order := [0, 3, 6] if real_ground else [0, 6, 3]
				for k in order:
					verts.append(tri[k]); norms.append(tri[k + 1]); colors.append(tri[k + 2])
					uvs.append(Vector2(tri[k].x - t.x_at(tri[k].z), 0.0))
	return {"verts": verts, "norms": norms, "colors": colors, "uvs": uvs}


func _grid_normal(hs: PackedFloat64Array, xs: PackedFloat64Array, W: int, iz: int, ic: int, row: float) -> Vector3:
	var dx := xs[iz * W + ic + 1] - xs[iz * W + ic - 1]
	var dhx := hs[iz * W + ic + 1] - hs[iz * W + ic - 1]
	var dhz := hs[(iz + 1) * W + ic] - hs[(iz - 1) * W + ic]
	return Vector3(-dhx / maxf(dx, 0.01), 1.0, -dhz / (2.0 * row)).normalized()


func _color_for_slope(p: Vector3, n: Vector3, t: Trail) -> Color:
	var ad := absf(p.x - t.x_at(p.z))
	if ad < TRAIL_HALF_WIDTH * 0.6:
		return Palette.TRAIL_DARK
	if ad < TRAIL_HALF_WIDTH:
		return Palette.TRAIL
	if ad < TRAIL_HALF_WIDTH + BANK_WIDTH:
		return Palette.SNOW_SHADE
	if ad < TRAIL_HALF_WIDTH + BANK_WIDTH + 0.6:
		return Palette.SNOW_MID
	var slope := sqrt(maxf(1.0 - n.y * n.y, 0.0)) / maxf(n.y, 0.05)
	if slope > 1.3:
		return Palette.ROCK_DARK
	if slope > 0.95:
		return Palette.ROCK
	var d := _drift.get_noise_2d(p.x, p.z)
	var nn := _detail.get_noise_2d(p.x * 2.5, p.z * 2.5)
	if d > 0.32 or nn > 0.55:
		return Palette.SNOW_SHADE
	if d < -0.25:
		return Palette.SNOW_MID
	return Palette.SNOW


func _scatter_transforms(z0: float, t: Trail) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(z0))
	var pines: Array = []
	var rocks: Array = []
	var dead: Array = []
	var cover: Array = []
	for i in _cover.size():
		cover.append([] as Array[Transform3D])
	for i in _pines.size():
		pines.append([] as Array[Transform3D])
	for i in _rocks.size():
		rocks.append([] as Array[Transform3D])
	for i in _dead_trees.size():
		dead.append([] as Array[Transform3D])
	var samples := int(140 * maxf(density_scale, 1.0))
	for i in samples:
		var z := z0 + rng.randf() * CHUNK_LEN
		var lateral := rng.randf_range(-HALF_WIDTH, HALF_WIDTH)
		var x := t.x_at(z) + lateral
		var ad := absf(lateral)
		if ad < TRAIL_HALF_WIDTH + 1.0:
			continue
		var y := height(x, z, t)
		var dzx := height(x + 0.5, z, t) - height(x - 0.5, z, t)
		var dzz := height(x, z + 0.5, t) - height(x, z - 0.5, t)
		var slope := sqrt(dzx * dzx + dzz * dzz)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		# Ground cover hugs the trail edges where the rider sees it.
		if not _cover.is_empty() and ad < 6.0 and slope < 0.9 and rng.randf() < 0.45 * minf(density_scale, 1.0):
			var ci := rng.randi() % cover.size()
			var sc: Vector2 = _cover_scale[ci]
			cover[ci].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y)), Vector3(x, y - 0.02, z)))
			continue
		if slope > 0.9:
			if rng.randf() < 0.3:
				rocks[rng.randi() % rocks.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.6, 1.4)), Vector3(x, y - 0.1, z)))
		elif ad > 3.0:
			var density := (0.55 if lateral < 0.0 else 0.35) * minf(density_scale, 1.0) * _density_mult
			var r := rng.randf()
			if r < density:
				pines[rng.randi() % pines.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(_tree_scale.x, _tree_scale.y)), Vector3(x, y - 0.05, z)))
			elif r < density + _dead_share and not dead.is_empty():
				dead[rng.randi() % dead.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.5, 0.8)), Vector3(x, y - 0.05, z)))
	return {"pines": pines, "rocks": rocks, "dead": dead, "cover": cover}


## Main thread: turn worker output into nodes.
func _finish_chunk(r: Dictionary) -> void:
	var index: int = r.index
	if _chunks.has(index):
		return
	var root := Node3D.new()
	root.name = "Chunk%d" % index
	for key in ["fine", "coarse_l", "coarse_r"]:
		var g: Dictionary = r[key]
		if g.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.norms
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material
		root.add_child(mi)
	if r.has("water") and not (r.water as Dictionary).verts.is_empty():
		var wa := []
		wa.resize(Mesh.ARRAY_MAX)
		wa[Mesh.ARRAY_VERTEX] = r.water.verts
		wa[Mesh.ARRAY_NORMAL] = r.water.norms
		wa[Mesh.ARRAY_TEX_UV] = r.water.uvs
		wa[Mesh.ARRAY_INDEX] = r.water.idx
		var wmesh := ArrayMesh.new()
		wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wmesh
		wmi.material_override = _water_material
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wmi)
	if r.has("flora"):
		_add_flora(root, r.flora, float(r.z0))
		add_child(root)
		_chunks[index] = root
		return
	var sc: Dictionary = r.scatter
	for i in _pines.size():
		_add_multimesh(root, _pines[i], sc.pines[i])
	for i in _rocks.size():
		_add_multimesh(root, _rocks[i], sc.rocks[i])
	for i in _dead_trees.size():
		_add_multimesh(root, _dead_trees[i], sc.dead[i])
	for i in _cover.size():
		_add_multimesh(root, _cover[i], sc.cover[i])
	add_child(root)
	_chunks[index] = root
	if OS.is_debug_build() and r.usec > 60000:
		print("[terrain] chunk %d built in %d ms (worker)" % [index, r.usec / 1000])




## The realistic look's plants for one chunk. Each plant variant's instances
## are split into sideways bands (BAND_WIDTH) with a MultiMesh per band, sitting
## at the band's middle, so visibility ranges cull it tightly; each plant's
## own fade and close-up/distant handover happen per plant in the shaders.
func _add_flora(root: Node3D, placed: Dictionary, z0: float) -> void:
	for mi in placed:
		var xfs: Array[Transform3D] = placed[mi][0]
		var tints: Array[Color] = placed[mi][1]
		var bands: Dictionary = {}
		for i in xfs.size():
			var o := xfs[i].origin
			var band := int(floor((o.x - trail.x_at(o.z)) / BAND_WIDTH))
			if not bands.has(band):
				bands[band] = []
			bands[band].append(i)
		for band in bands:
			var idx: Array = bands[band]
			var mid := Vector3.ZERO
			for i in idx:
				mid += xfs[i].origin
			mid /= float(idx.size())
			_flora_band(root, mi, xfs, tints, idx, mid)


func _flora_band(root: Node3D, mi: int, xfs: Array[Transform3D], tints: Array[Color], idx: Array, mid: Vector3) -> void:
	var mm := _band_multimesh(flora.meshes[mi], xfs, tints, idx, mid)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = mid
	if flora.far_meshes.has(mi):
		# Close-up tree near the camera, its cheaper twin beyond.
		var fmm := _band_multimesh(flora.far_meshes[mi], xfs, tints, idx, mid)
		var far := MultiMeshInstance3D.new()
		far.multimesh = fmm
		far.position = mid
		far.visibility_range_begin = maxf(RealFlora.TREE_DETAIL_RANGE - BAND_PAD, 0.0)
		far.visibility_range_end = RealFlora.TREE_FAR + BAND_PAD
		root.add_child(far)
		mmi.visibility_range_end = RealFlora.TREE_DETAIL_RANGE + BAND_PAD
		# Up close the shadow comes from the cheaper twin too: soft shadows hide the difference.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shade := MultiMeshInstance3D.new()
		shade.multimesh = fmm
		shade.position = mid
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shade.visibility_range_end = RealFlora.TREE_DETAIL_RANGE + BAND_PAD
		root.add_child(shade)
	match flora.kinds[mi]:
		"grass":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = RealFlora.GRASS_VISIBLE
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		"tree":
			if not flora.far_meshes.has(mi):
				mmi.visibility_range_end = RealFlora.TREE_FAR + BAND_PAD
		"rock", "bush":
			mmi.visibility_range_end = RealFlora.SMALL_FAR + BAND_PAD
	root.add_child(mmi)


func _band_multimesh(mesh: Mesh, xfs: Array[Transform3D], tints: Array[Color], idx: Array, mid: Vector3) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = idx.size()
	for k in idx.size():
		var xf := xfs[idx[k]]
		xf.origin -= mid
		mm.set_instance_transform(k, xf)
		mm.set_instance_custom_data(k, tints[idx[k]])
	return mm


func _add_multimesh(root: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Procedural meshes carry vertex colours and share the vertex-colour material;
	# imported props have per-surface palette materials baked into the mesh.
	if mesh is ArrayMesh and mesh.surface_get_material(0) == null:
		mmi.material_override = _material
	root.add_child(mmi)
