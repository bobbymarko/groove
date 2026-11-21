class_name RealFlora
extends RefCounted
## The realistic look's plants and rocks for one biome: a few seeded variants of
## each kind built by PlantGen (once per app run and biome), and the scatter
## that places them around a terrain chunk. scatter() runs on the terrain
## worker thread, so it touches no nodes.

const BIOMES := {
	"winter": {"ground": "snow", "snow": 0.5, "spruce": 0.92, "broad": 0.0, "bare": 0.08, "trees": 0.55,
		"needle": Color(0.06, 0.14, 0.08), "bark": Color(0.24, 0.19, 0.15),
		"grass": Color(0.42, 0.36, 0.2), "grass_h": 0.5, "grass_blades": 7, "grass_density": 0.1,
		"bush": 0.0, "rock": Color(0.42, 0.41, 0.4), "rocks": 1.0},
	"summer": {"ground": "grass", "snow": 0.0, "spruce": 0.25, "broad": 0.75, "bare": 0.0, "trees": 0.5,
		"needle": Color(0.06, 0.15, 0.07), "bark": Color(0.27, 0.22, 0.17), "leaves": [Color(0.1, 0.22, 0.05), Color(0.13, 0.25, 0.05)],
		"grass": Color(0.13, 0.24, 0.06), "grass_h": 0.5, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85), Color(0.95, 0.78, 0.15)], "flower_share": 0.06,
		"bush": 0.6, "rock": Color(0.4, 0.39, 0.37), "rocks": 0.6, "moss": 0.6},
	"autumn": {"ground": "grass", "snow": 0.0, "spruce": 0.2, "broad": 0.8, "bare": 0.05, "trees": 0.5,
		"needle": Color(0.06, 0.14, 0.07), "bark": Color(0.25, 0.2, 0.16),
		"leaves": [Color(0.75, 0.32, 0.05), Color(0.8, 0.55, 0.08), Color(0.55, 0.12, 0.04), Color(0.45, 0.45, 0.08)],
		"grass": Color(0.24, 0.22, 0.08), "grass_h": 0.45, "grass_blades": 14, "grass_density": 0.8,
		"bush": 0.5, "rock": Color(0.4, 0.38, 0.35), "rocks": 0.7, "moss": 0.4},
	"spring": {"ground": "grass", "snow": 0.0, "spruce": 0.2, "broad": 0.8, "bare": 0.0, "trees": 0.45,
		"needle": Color(0.07, 0.17, 0.08), "bark": Color(0.28, 0.23, 0.18), "leaves": [Color(0.2, 0.36, 0.06), Color(0.85, 0.75, 0.8)],
		"grass": Color(0.15, 0.3, 0.06), "grass_h": 0.4, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85), Color(0.95, 0.8, 0.12), Color(0.55, 0.35, 0.8), Color(0.85, 0.2, 0.15)], "flower_share": 0.25,
		"bush": 0.6, "rock": Color(0.42, 0.41, 0.39), "rocks": 0.5, "moss": 0.7},
	"desert": {"ground": "sand", "snow": 0.0, "spruce": 0.0, "broad": 0.0, "bare": 0.0, "trees": 0.0,
		"grass": Color(0.45, 0.38, 0.2), "grass_h": 0.35, "grass_blades": 9, "grass_density": 0.12,
		"bush": 0.5, "bush_leaves": Color(0.28, 0.28, 0.14), "rock": Color(0.55, 0.3, 0.19), "rocks": 2.5},
	"birchwood": {"ground": "grass", "snow": 0.0, "spruce": 0.0, "broad": 1.0, "bare": 0.0, "trees": 0.55, "birch": true,
		"bark": Color(0.8, 0.78, 0.74), "leaves": [Color(0.3, 0.42, 0.08), Color(0.24, 0.38, 0.07)],
		"grass": Color(0.16, 0.28, 0.07), "grass_h": 0.5, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85)], "flower_share": 0.05,
		"bush": 0.4, "rock": Color(0.42, 0.41, 0.39), "rocks": 0.4, "moss": 0.6},
	"apocalypse": {"ground": "grass", "snow": 0.0, "spruce": 0.0, "broad": 0.0, "bare": 1.0, "trees": 0.35,
		"bark": Color(0.18, 0.16, 0.14), "grass": Color(0.3, 0.27, 0.16), "grass_h": 0.4, "grass_blades": 8, "grass_density": 0.3,
		"bush": 0.0, "rock": Color(0.3, 0.29, 0.28), "rocks": 1.0},
}

const GRASS_REACH := 22.0        ## metres either side of the trail that get grass
const GRASS_VISIBLE := 65.0      ## grass stops drawing past this (fog hides the edge)
const TREE_DETAIL_RANGE := 70.0  ## trees switch to their distant version past this

static var _cache: Dictionary = {}   # biome id -> RealFlora

var biome: Dictionary = {}
var meshes: Array[Mesh] = []
var kinds: Array[String] = []        ## "tree", "bush", "grass", "rock" per mesh
var far_meshes: Dictionary = {}     ## mesh index -> its distant version (trees only)
var _trees: Array[int] = []
var _spruce: Array[int] = []
var _broad: Array[int] = []
var _bare: Array[int] = []
var _bushes: Array[int] = []
var _grass: Array[int] = []
var _flowers: Array[int] = []
var _rocks: Array[int] = []
var _clump := FastNoiseLite.new()


static func for_biome(id: String) -> RealFlora:
	if not BIOMES.has(id):
		id = "summer"
	if not _cache.has(id):
		var f := RealFlora.new()
		f._build(id)
		_cache[id] = f
	return _cache[id]


func ground_type() -> String:
	return str(biome.get("ground", "grass"))


func _build(id: String) -> void:
	biome = BIOMES[id]
	_clump.seed = 77
	_clump.frequency = 0.035
	var snow := float(biome.get("snow", 0.0))
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://scene/real/real_foliage.gdshader")
	leaf_mat.set_shader_parameter("snow", snow)
	var needle_mat := ShaderMaterial.new()
	needle_mat.shader = leaf_mat.shader
	needle_mat.set_shader_parameter("snow", snow)
	needle_mat.set_shader_parameter("fringe", 0.75)
	needle_mat.set_shader_parameter("translucency", 0.3)
	var bark_mat := ShaderMaterial.new()
	bark_mat.shader = load("res://scene/real/real_bark.gdshader")
	bark_mat.set_shader_parameter("snow", snow * 0.8)
	var birch_mat := ShaderMaterial.new()
	birch_mat.shader = bark_mat.shader
	birch_mat.set_shader_parameter("birch", 1.0)
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = leaf_mat.shader
	grass_mat.set_shader_parameter("translucency", 0.35)
	grass_mat.set_shader_parameter("snow", snow * 0.3)
	var rock_mat := ShaderMaterial.new()
	rock_mat.shader = load("res://scene/real/real_rock.gdshader")
	rock_mat.set_shader_parameter("snow", snow)
	rock_mat.set_shader_parameter("moss_amount", float(biome.get("moss", 0.0)))
	var bark_col: Color = biome.get("bark", Color(0.26, 0.21, 0.16))
	var birch := bool(biome.get("birch", false))
	if float(biome.trees) > 0.0:
		if float(biome.spruce) > 0.0:
			for i in 4:
				_add(PlantGen.spruce(100 + i, bark_mat, needle_mat, biome.needle), "spruce",
						PlantGen.spruce(100 + i, bark_mat, needle_mat, biome.needle, 0.4))
		if float(biome.broad) > 0.0:
			var cols: Array = biome.get("leaves", [Color(0.12, 0.24, 0.05)])
			for i in 4:
				_add(PlantGen.broadleaf(200 + i, birch_mat if birch else bark_mat, leaf_mat, cols[i % cols.size()], bark_col, birch), "broad",
						PlantGen.broadleaf(200 + i, birch_mat if birch else bark_mat, leaf_mat, cols[i % cols.size()], bark_col, birch, false, 0.35))
		if float(biome.bare) > 0.0:
			for i in 2:
				_add(PlantGen.broadleaf(300 + i, bark_mat, leaf_mat, Color.BLACK, bark_col.darkened(0.2), false, true), "bare")
	if float(biome.bush) > 0.0:
		var bc: Color = biome.get("bush_leaves", biome.get("leaves", [Color(0.12, 0.22, 0.05)])[0])
		for i in 3:
			_add(PlantGen.bush(400 + i, bark_mat, leaf_mat, bc), "bush")
	for i in 3:
		_add(PlantGen.grass(500 + i, grass_mat, biome.grass, float(biome.grass_h), int(biome.grass_blades)), "grass")
	for fc in biome.get("flowers", []):
		_add(PlantGen.grass(600 + _flowers.size(), grass_mat, biome.grass, float(biome.grass_h) * 0.9, 10, fc), "flower")
	for i in 4:
		_add(PlantGen.rock(700 + i, rock_mat, biome.rock), "rock")


func _add(m: Mesh, kind: String, far: Mesh = null) -> void:
	var i := meshes.size()
	meshes.append(m)
	if far:
		far_meshes[i] = far
	match kind:
		"spruce", "broad", "bare":
			kinds.append("tree")
			_trees.append(i)
			({"spruce": _spruce, "broad": _broad, "bare": _bare}[kind] as Array[int]).append(i)
		"bush":
			kinds.append("bush")
			_bushes.append(i)
		"grass":
			kinds.append("grass")
			_grass.append(i)
		"flower":
			kinds.append("grass")
			_flowers.append(i)
		_:
			kinds.append("rock")
			_rocks.append(i)


## Worker thread: instance transforms and tints for one chunk, per mesh index.
## height: Callable(x, z, trail) -> float.
func scatter(z0: float, chunk_len: float, half_width: float, trail_clear: float, t: Trail, height: Callable) -> Dictionary:
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(z0) * 31 + 7)
	var tree_share := float(biome.trees)
	# Trees: clumped by noise, denser uphill, clear of the trail.
	if not _trees.is_empty():
		for i in 120:
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(-half_width, half_width)
			var ad := absf(lat)
			if ad < trail_clear + 2.5:
				continue
			var x := t.x_at(z) + lat
			var clump := _clump.get_noise_2d(x, z) * 0.5 + 0.5
			var p := tree_share * (1.25 if lat < 0.0 else 0.8) * smoothstep(0.25, 0.65, clump)
			if rng.randf() > p:
				continue
			var y := float(height.call(x, z, t))
			var mi := _pick_tree(rng)
			var s := rng.randf_range(0.7, 1.25)
			_put(out, mi, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.1, z)), _tint(rng, 0.12))
	# Bushes along the trail edges and in clearings.
	if not _bushes.is_empty():
		for i in int(40 * float(biome.bush)):
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(-30.0, 30.0)
			if absf(lat) < trail_clear + 1.2:
				continue
			var x := t.x_at(z) + lat
			var y := float(height.call(x, z, t))
			var s := rng.randf_range(0.6, 1.4)
			_put(out, _bushes[rng.randi() % _bushes.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.05, z)), _tint(rng, 0.15))
	# Rocks: many small, few big, half sunk.
	for i in int(14 * float(biome.rocks)):
		var z := z0 + rng.randf() * chunk_len
		var lat := rng.randf_range(-half_width, half_width)
		if absf(lat) < trail_clear + 0.6:
			continue
		var x := t.x_at(z) + lat
		var y := float(height.call(x, z, t))
		var s := 0.15 + 1.5 * pow(rng.randf(), 2.6)
		var basis := Basis(Vector3(rng.randf_range(-1.0, 1.0), 1.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf() * TAU)
		_put(out, _rocks[rng.randi() % _rocks.size()], Transform3D(basis.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), Vector3(x, y - s * 0.25, z)), _tint(rng, 0.1))
	# Grass: jittered grid near the trail, thinning with distance; patchy by noise.
	var density := 0.0 if OS.get_cmdline_user_args().has("nograss") else float(biome.grass_density)
	if density > 0.0 and not _grass.is_empty():
		var step := 0.4 / sqrt(density)
		var zz := z0
		while zz < z0 + chunk_len:
			var cx := t.x_at(zz)
			var lat := -GRASS_REACH
			while lat < GRASS_REACH:
				var ad := absf(lat)
				var spacing := step * (1.0 + ad * 0.06)
				lat += spacing * rng.randf_range(0.7, 1.3)
				if ad < trail_clear * 0.8:
					continue
				var x := cx + lat + rng.randf_range(-0.2, 0.2)
				var z := zz + rng.randf_range(-0.25, 0.25)
				var patch := _clump.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
				if rng.randf() > density * smoothstep(0.15, 0.55, patch) + 0.08:
					continue
				var y := float(height.call(x, z, t))
				var edge := smoothstep(trail_clear * 0.8, trail_clear + 0.8, ad)   # short at the trail's edge
				var s := rng.randf_range(0.7, 1.3) * lerpf(0.55, 1.0, edge)
				var mi := _grass[rng.randi() % _grass.size()]
				if not _flowers.is_empty() and rng.randf() < float(biome.get("flower_share", 0.0)):
					mi = _flowers[rng.randi() % _flowers.size()]
				_put(out, mi, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.02, z)), _tint(rng, 0.2))
			zz += step * rng.randf_range(0.8, 1.2)
	return out


func _pick_tree(rng: RandomNumberGenerator) -> int:
	var r := rng.randf() * (float(biome.spruce) + float(biome.broad) + float(biome.bare))
	var pool := _bare
	if r < float(biome.spruce) and not _spruce.is_empty():
		pool = _spruce
	elif r < float(biome.spruce) + float(biome.broad) and not _broad.is_empty():
		pool = _broad
	if pool.is_empty():
		pool = _trees
	return pool[rng.randi() % pool.size()]


func _tint(rng: RandomNumberGenerator, spread: float) -> Color:
	var v := rng.randf_range(1.0 - spread, 1.0 + spread)
	return Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.93, 1.05), 1.0)


static func _put(out: Dictionary, mi: int, xf: Transform3D, tint: Color) -> void:
	if not out.has(mi):
		out[mi] = [[] as Array[Transform3D], [] as Array[Color]]
	out[mi][0].append(xf)
	out[mi][1].append(tint)
