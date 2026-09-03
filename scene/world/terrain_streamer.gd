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
const SHOULDER := 4.0                 # smooth rideable snow either side before the rough field

var trail: Trail
var _chunks: Dictionary = {}     # chunk index -> Node3D
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _drift := FastNoiseLite.new()
var _fine_columns: PackedFloat64Array = []       # |x| <= 8 m: 0.2 m near the groove, then 0.5 m
var _coarse_columns_l: PackedFloat64Array = []   # -HALF_WIDTH .. -8 m at RES
var _coarse_columns_r: PackedFloat64Array = []   # 8 m .. HALF_WIDTH at RES
var _pending: Array[int] = []
var _thread: Thread
var density_scale := 1.0                 # tree density multiplier (new chunks only)
var _pines: Array[Mesh] = []      # variants; MeshLib procedural pine as fallback
var _rocks: Array[Mesh] = []
var _dead_trees: Array[Mesh] = []
var _shrub_mesh: ArrayMesh
var _material: Material
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
	for i in range(1, 6):
		var m := MeshLib.load_prop("res://assets/quaternius/Pine_%d.gltf" % i)
		if m:
			_pines.append(m)
	for i in range(1, 4):
		var m := MeshLib.load_prop("res://assets/quaternius/Rock_Medium_%d.gltf" % i)
		if m:
			_rocks.append(m)
	for i in range(1, 6):
		var m := MeshLib.load_prop("res://assets/quaternius/DeadTree_%d.gltf" % i, false)
		if m:
			_dead_trees.append(m)
	if _pines.is_empty():
		_pines.append(MeshLib.pine())
	if _rocks.is_empty():
		_rocks.append(MeshLib.rock())
	_shrub_mesh = MeshLib.shrub()
	_material = MeshLib.cel_material(true)


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
	return base + off * (rough + hillside)


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
	for i in range(center - BEHIND, center + AHEAD + 1):
		if not _chunks.has(i) and not _pending.has(i):
			_pending.append(i)
	for key in _chunks.keys():
		if key < center - BEHIND or key > center + AHEAD:
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
	out["scatter"] = _scatter_transforms(z0, t)
	out["usec"] = Time.get_ticks_usec() - t0
	return out


## Vertex/normal/colour arrays for a grid of columns (offsets from the trail centre) × rows.
func _grid_arrays(z0: float, cols: PackedFloat64Array, row: float, t: Trail) -> Dictionary:
	var nz := int(CHUNK_LEN / row)
	var ncols := cols.size()
	# Sample heights on a (nz+1) × ncols lattice, with one extra ring for normals.
	var hs := PackedFloat64Array()
	hs.resize((nz + 3) * (ncols + 2))
	var xs := PackedFloat64Array()
	xs.resize((nz + 3) * (ncols + 2))
	for iz in nz + 3:
		var zz := z0 + (iz - 1) * row
		var cx := t.x_at(zz)
		for ic in ncols + 2:
			var col_off := cols[clampi(ic - 1, 0, ncols - 1)] + (-(RES) if ic == 0 else (RES if ic == ncols + 1 else 0.0))
			var xx := cx + col_off
			xs[iz * (ncols + 2) + ic] = xx
			hs[iz * (ncols + 2) + ic] = height(xx, zz, t)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
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
			var c1 := _color_for_slope((p00 + p10 + p11) / 3.0, n00, t)
			var c2 := _color_for_slope((p00 + p11 + p01) / 3.0, n01, t)
			# Clockwise front faces (see MeshLib.tri).
			for tri in [[p00, n00, p10, n10, p11, n11, c1], [p00, n00, p11, n11, p01, n01, c2]]:
				verts.append(tri[0]); norms.append(tri[1]); colors.append(tri[6])
				verts.append(tri[4]); norms.append(tri[5]); colors.append(tri[6])
				verts.append(tri[2]); norms.append(tri[3]); colors.append(tri[6])
	return {"verts": verts, "norms": norms, "colors": colors}


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
		if slope > 0.9:
			if rng.randf() < 0.3:
				rocks[rng.randi() % rocks.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.6, 1.4)), Vector3(x, y - 0.1, z)))
		elif ad > 3.0:
			var density := (0.55 if lateral < 0.0 else 0.35) * minf(density_scale, 1.0)
			var r := rng.randf()
			if r < density:
				pines[rng.randi() % pines.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(PINE_SCALE.x, PINE_SCALE.y)), Vector3(x, y - 0.05, z)))
			elif r < density + 0.04 and not dead.is_empty():
				dead[rng.randi() % dead.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.5, 0.8)), Vector3(x, y - 0.05, z)))
	return {"pines": pines, "rocks": rocks, "dead": dead}


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
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material
		root.add_child(mi)
	var sc: Dictionary = r.scatter
	for i in _pines.size():
		_add_multimesh(root, _pines[i], sc.pines[i])
	for i in _rocks.size():
		_add_multimesh(root, _rocks[i], sc.rocks[i])
	for i in _dead_trees.size():
		_add_multimesh(root, _dead_trees[i], sc.dead[i])
	add_child(root)
	_chunks[index] = root
	if OS.is_debug_build() and r.usec > 60000:
		print("[terrain] chunk %d built in %d ms (worker)" % [index, r.usec / 1000])




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
