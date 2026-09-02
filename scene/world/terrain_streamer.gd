class_name TerrainStreamer
extends Node3D
## Generates terrain chunks around the rider along the trail and recycles them
## behind. Each chunk is a flat-shaded height mesh with vertex colours plus a
## MultiMesh of scattered props (pines, shrubs, rocks) that avoid the trail.

const CHUNK_LEN := 24.0          # metres along Z
const HALF_WIDTH := 70.0         # metres either side of the trail
const RES := 2.0                 # metres per grid step
const AHEAD := 9                 # chunks kept ahead of the rider
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
var _columns: PackedFloat64Array = []   # lateral grid offsets, dense near the trail
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
	var x := -HALF_WIDTH
	while x < HALF_WIDTH - 0.001:
		_columns.append(x)
		x += 0.5 if absf(x) < 6.0 else RES
	_columns.append(HALF_WIDTH)
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
func height(x: float, z: float) -> float:
	var tx := trail.x_at(z)
	var d := x - tx
	var ad := absf(d)
	var base := trail.h_at(z)
	# Groomed groove with a small bank on each side.
	var groove := 0.0
	if ad < TRAIL_HALF_WIDTH:
		groove = -GROOVE_DEPTH * (1.0 - pow(ad / TRAIL_HALF_WIDTH, 2.0))
	elif ad < TRAIL_HALF_WIDTH + BANK_WIDTH:
		groove = 0.09 * sin(PI * (ad - TRAIL_HALF_WIDTH) / BANK_WIDTH)
	var off := smoothstep(TRAIL_HALF_WIDTH + BANK_WIDTH, TRAIL_HALF_WIDTH + SHOULDER, ad)
	var rough_fade := smoothstep(SHOULDER, SHOULDER + 18.0, ad)
	var rough := (_noise.get_noise_2d(x, z) * 2.2 + _detail.get_noise_2d(x, z) * 0.35) * rough_fade
	var drifts := _drift.get_noise_2d(x, z) * 0.35 * smoothstep(TRAIL_HALF_WIDTH + BANK_WIDTH, SHOULDER, ad)
	base += groove + drifts
	var hillside := 0.0
	if d < 0.0:
		hillside = (ad - TRAIL_HALF_WIDTH) * 0.32 + pow(maxf(ad - 25.0, 0.0), 1.3) * 0.18   # uphill side
	else:
		hillside = -(ad - TRAIL_HALF_WIDTH) * 0.18                                          # downhill side
	return base + off * (rough + hillside)


func update_around(z: float) -> void:
	var center := int(floor(z / CHUNK_LEN))
	for i in range(center - BEHIND, center + AHEAD + 1):
		if not _chunks.has(i):
			_chunks[i] = _build_chunk(i)
	for key in _chunks.keys():
		if key < center - BEHIND or key > center + AHEAD:
			_chunks[key].queue_free()
			_chunks.erase(key)


func _build_chunk(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk%d" % index
	var z0 := index * CHUNK_LEN
	var st := MeshLib.begin()
	var nz := int(CHUNK_LEN / 1.0)
	for iz in nz:
		var za := z0 + iz * 1.0
		var zb := za + 1.0
		for ix in _columns.size() - 1:
			var xa := _columns[ix]
			var xb := _columns[ix + 1]
			# Grid is centred on the trail so the trail is always covered.
			var cx := trail.x_at((za + zb) * 0.5)
			var p00 := Vector3(cx + xa, height(cx + xa, za), za)
			var p10 := Vector3(cx + xb, height(cx + xb, za), za)
			var p01 := Vector3(cx + xa, height(cx + xa, zb), zb)
			var p11 := Vector3(cx + xb, height(cx + xb, zb), zb)
			var c1 := _color_for((p00 + p10 + p11) / 3.0)
			var c2 := _color_for((p00 + p11 + p01) / 3.0)
			MeshLib.tri(st, p00, p11, p10, c1)
			MeshLib.tri(st, p00, p01, p11, c2)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st)
	mi.material_override = _material
	root.add_child(mi)
	_scatter(root, z0)
	add_child(root)
	return root


func _color_for(p: Vector3) -> Color:
	var ad := absf(p.x - trail.x_at(p.z))
	if ad < TRAIL_HALF_WIDTH * 0.6:
		return Palette.TRAIL_DARK      # packed centre of the groove
	if ad < TRAIL_HALF_WIDTH:
		return Palette.TRAIL
	if ad < TRAIL_HALF_WIDTH + BANK_WIDTH:
		return Palette.SNOW_SHADE      # bank
	if ad < TRAIL_HALF_WIDTH + BANK_WIDTH + 0.6:
		return Palette.SNOW_MID
	# Slope from finite differences.
	var dzx := (height(p.x + 2.0, p.z) - height(p.x - 2.0, p.z)) / 4.0
	var dzz := (height(p.x, p.z + 2.0) - height(p.x, p.z - 2.0)) / 4.0
	var slope := sqrt(dzx * dzx + dzz * dzz)
	if slope > 1.3:
		return Palette.ROCK_DARK
	if slope > 0.95:
		return Palette.ROCK
	# Drifts and wind texture: large soft patches plus finer ripples.
	var d := _drift.get_noise_2d(p.x, p.z)
	var n := _detail.get_noise_2d(p.x * 2.5, p.z * 2.5)
	if d > 0.32 or n > 0.55:
		return Palette.SNOW_SHADE
	if d < -0.25:
		return Palette.SNOW_MID
	return Palette.SNOW


func _scatter(root: Node3D, z0: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(z0))
	var pines: Array = []       # per variant: Array[Transform3D]
	var rocks: Array = []
	var dead: Array = []
	for i in _pines.size():
		pines.append([] as Array[Transform3D])
	for i in _rocks.size():
		rocks.append([] as Array[Transform3D])
	for i in _dead_trees.size():
		dead.append([] as Array[Transform3D])
	var shrubs: Array[Transform3D] = []
	for i in 140:
		var z := z0 + rng.randf() * CHUNK_LEN
		var lateral := rng.randf_range(-HALF_WIDTH, HALF_WIDTH)
		var x := trail.x_at(z) + lateral
		var ad := absf(lateral)
		if ad < TRAIL_HALF_WIDTH + 1.0:
			continue
		var y := height(x, z)
		var dzx := height(x + 0.5, z) - height(x - 0.5, z)
		var dzz := height(x, z + 0.5) - height(x, z - 0.5)
		var slope := sqrt(dzx * dzx + dzz * dzz)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if ad < 4.0 and rng.randf() < 0.35:
			shrubs.append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)), Vector3(x, y - 0.05, z)))
		elif slope > 0.9:
			if rng.randf() < 0.3:
				rocks[rng.randi() % rocks.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.6, 1.4)), Vector3(x, y - 0.1, z)))
		elif ad > 3.0:
			var density := 0.55 if lateral < 0.0 else 0.35        # denser on the uphill side
			var r := rng.randf()
			if r < density:
				pines[rng.randi() % pines.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(PINE_SCALE.x, PINE_SCALE.y)), Vector3(x, y - 0.05, z)))
			elif r < density + 0.04 and not dead.is_empty():
				dead[rng.randi() % dead.size()].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.5, 0.8)), Vector3(x, y - 0.05, z)))
	for i in _pines.size():
		_add_multimesh(root, _pines[i], pines[i])
	for i in _rocks.size():
		_add_multimesh(root, _rocks[i], rocks[i])
	for i in _dead_trees.size():
		_add_multimesh(root, _dead_trees[i], dead[i])
	_add_multimesh(root, _shrub_mesh, shrubs)


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
