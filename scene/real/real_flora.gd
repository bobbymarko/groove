class_name RealFlora
extends RefCounted
## The realistic look's plants and rocks for one biome: a few seeded variants of
## each kind built by PlantGen (once per app run and biome), and the scatter
## that places them around a terrain chunk. scatter() runs on the terrain
## worker thread, so it touches no nodes.

const BIOMES := {
	"winter": {"range": 1300.0, "snow_line": 250.0, "range_rock": Color(0.3, 0.3, 0.32), "range_scrub": Color(0.12, 0.16, 0.12), "water": "ice", "ground": "snow", "snow": 0.5, "spruce": 0.92, "broad": 0.0, "bare": 0.08, "trees": 0.55,
		"needle": Color(0.06, 0.14, 0.08), "bark": Color(0.24, 0.19, 0.15),
		"grass": Color(0.42, 0.36, 0.2), "grass_h": 0.5, "grass_blades": 7, "grass_density": 0.1,
		"bush": 0.0, "rock": Color(0.42, 0.41, 0.4), "rocks": 1.0},
	"summer": {"range": 700.0, "range_scrub": Color(0.16, 0.22, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.25, "broad": 0.75, "bare": 0.0, "trees": 0.5,
		"needle": Color(0.06, 0.15, 0.07), "bark": Color(0.27, 0.22, 0.17), "leaves": [Color(0.1, 0.22, 0.05), Color(0.13, 0.25, 0.05)],
		"grass": Color(0.13, 0.24, 0.06), "grass_h": 0.5, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85), Color(0.95, 0.78, 0.15)], "flower_share": 0.06,
		"bush": 0.6, "rock": Color(0.4, 0.39, 0.37), "rocks": 0.6, "moss": 0.6},
	"autumn": {"range": 800.0, "range_scrub": Color(0.3, 0.22, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.2, "broad": 0.8, "bare": 0.05, "trees": 0.5,
		"needle": Color(0.06, 0.14, 0.07), "bark": Color(0.25, 0.2, 0.16),
		"leaves": [Color(0.75, 0.32, 0.05), Color(0.8, 0.55, 0.08), Color(0.55, 0.12, 0.04), Color(0.45, 0.45, 0.08)],
		"grass": Color(0.24, 0.22, 0.08), "grass_h": 0.45, "grass_blades": 14, "grass_density": 0.8,
		"bush": 0.5, "rock": Color(0.4, 0.38, 0.35), "rocks": 0.7, "moss": 0.4},
	"spring": {"range": 650.0, "range_scrub": Color(0.18, 0.26, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.2, "broad": 0.8, "bare": 0.0, "trees": 0.45,
		"needle": Color(0.07, 0.17, 0.08), "bark": Color(0.28, 0.23, 0.18), "leaves": [Color(0.2, 0.36, 0.06), Color(0.85, 0.75, 0.8)],
		"grass": Color(0.15, 0.3, 0.06), "grass_h": 0.4, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85), Color(0.95, 0.8, 0.12), Color(0.55, 0.35, 0.8), Color(0.85, 0.2, 0.15)], "flower_share": 0.25,
		"bush": 0.6, "rock": Color(0.42, 0.41, 0.39), "rocks": 0.5, "moss": 0.7},
	# Sonoran desert, after Tucson: saguaros over palo verde, ocotillo, cholla,
	# prickly pear, barrel cactus and creosote on decomposed-granite gravel,
	# granite boulders, rugged mountains behind, a big clear sky and a high sun.
	"desert": {"range": 1500.0, "range_rock": Color(0.46, 0.3, 0.24), "range_scrub": Color(0.3, 0.28, 0.17), "ground": "desert", "snow": 0.0, "spruce": 0.0, "broad": 0.0, "bare": 0.0, "saguaro": 0.6, "palo": 0.4, "trees": 0.32,
		"grass": Color(0.5, 0.44, 0.27), "grass_h": 0.32, "grass_blades": 9, "grass_density": 0.14,
		"bush": 1.6, "rock": Color(0.56, 0.47, 0.4), "rocks": 2.2, "clouds": 0.22, "noon": 62.0,
		"relief": 320.0, "relief_from": 280.0, "hills": 0.3},
	"birchwood": {"range": 700.0, "range_scrub": Color(0.18, 0.24, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.0, "broad": 1.0, "bare": 0.0, "trees": 0.55, "birch": true,
		"bark": Color(0.8, 0.78, 0.74), "leaves": [Color(0.3, 0.42, 0.08), Color(0.24, 0.38, 0.07)],
		"grass": Color(0.16, 0.28, 0.07), "grass_h": 0.5, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85)], "flower_share": 0.05,
		"bush": 0.4, "rock": Color(0.42, 0.41, 0.39), "rocks": 0.4, "moss": 0.6},
	"apocalypse": {"range": 900.0, "range_rock": Color(0.22, 0.2, 0.19), "range_scrub": Color(0.2, 0.19, 0.16), "water": "river", "water_tint": Color(0.05, 0.05, 0.03), "ground": "grass", "snow": 0.0, "spruce": 0.0, "broad": 0.0, "bare": 1.0, "trees": 0.35,
		"bark": Color(0.18, 0.16, 0.14), "grass": Color(0.3, 0.27, 0.16), "grass_h": 0.4, "grass_blades": 8, "grass_density": 0.3,
		"bush": 0.0, "rock": Color(0.3, 0.29, 0.28), "rocks": 1.0},
}

const WOODS := 2.0               ## tree density that means a wood (a true-map ride's forest squares)
const GRASS_REACH := 22.0        ## metres either side of the trail that get grass
const GRASS_VISIBLE := 65.0      ## grass stops drawing past this (fog hides the edge)
const TREE_DETAIL_RANGE := 80.0  ## each tree crossfades to its distant version around here (in the shaders)
const TREE_FADE := 20.0
const TREE_SHADOWS := 90.0       ## trees cast shadows within this
const TREE_FAR := 300.0          ## and dithers away by here; new chunks are built further out
const SMALL_FAR := 180.0         ## bushes and rocks

static var _cache: Dictionary = {}   # biome id -> RealFlora
## Where close-up trees hand over to their distant versions for the ride now
## showing: TREE_DETAIL_RANGE on the strip; nearer on a true-map ride, whose
## trees stand all round the rider, not only along the trail.
static var detail_range := TREE_DETAIL_RANGE

var biome: Dictionary = {}
var meshes: Array[Mesh] = []
var kinds: Array[String] = []        ## "tree", "bush", "grass", "rock" per mesh
var far_meshes: Dictionary = {}     ## mesh index -> its distant version (trees only)
var _trees: Array[int] = []
var _spruce: Array[int] = []
var _broad: Array[int] = []
var _bare: Array[int] = []
var _saguaro: Array[int] = []
var _palo: Array[int] = []
var _bushes: Array[int] = []
var _grass: Array[int] = []
var _flowers: Array[int] = []
var _rocks: Array[int] = []
var _clump := FastNoiseLite.new()
var biome_id := ""


static func for_biome(id: String) -> RealFlora:
	if not BIOMES.has(id):
		id = "summer"
	if not _cache.has(id):
		var f := RealFlora.new()
		f.biome_id = id
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
	# Trees fade out at TREE_FAR; their close-up materials hand over at TREE_DETAIL_RANGE.
	for m: ShaderMaterial in [needle_mat, leaf_mat, bark_mat, birch_mat]:
		var near := m.duplicate() as ShaderMaterial
		_lod(near, 0, TREE_FAR)
		_tree_near[m] = near
	_lod(rock_mat, 2, SMALL_FAR)
	var bark_col: Color = biome.get("bark", Color(0.26, 0.21, 0.16))
	if biome.get("ground", "") == "desert":
		_build_desert(bark_mat, leaf_mat, rock_mat)
		return
	var birch := bool(biome.get("birch", false))
	if float(biome.trees) > 0.0:
		if float(biome.spruce) > 0.0:
			for i in 4:
				_add(PlantGen.spruce(100 + i, _near(bark_mat), _near(needle_mat), biome.needle), "spruce",
						PlantGen.spruce(100 + i, _far(bark_mat), _far(needle_mat), biome.needle, 0.55))
		if float(biome.broad) > 0.0:
			var cols: Array = biome.get("leaves", [Color(0.12, 0.24, 0.05)])
			for i in 4:
				_add(PlantGen.broadleaf(200 + i, _near(birch_mat if birch else bark_mat), _near(leaf_mat), cols[i % cols.size()], bark_col, birch), "broad",
						PlantGen.broadleaf(200 + i, _far(birch_mat if birch else bark_mat), _far(leaf_mat), cols[i % cols.size()], bark_col, birch, false, 0.35))
		if float(biome.bare) > 0.0:
			for i in 2:
				_add(PlantGen.broadleaf(300 + i, _single(bark_mat, TREE_FAR), leaf_mat, Color.BLACK, bark_col.darkened(0.2), false, true), "bare")
	if float(biome.bush) > 0.0:
		var bc: Color = biome.get("bush_leaves", biome.get("leaves", [Color(0.12, 0.22, 0.05)])[0])
		for i in 3:
			_add(PlantGen.bush(400 + i, _single(bark_mat, SMALL_FAR), _single(leaf_mat, SMALL_FAR), bc), "bush")
	for i in 3:
		_add(PlantGen.grass(500 + i, grass_mat, biome.grass, float(biome.grass_h), int(biome.grass_blades)), "grass")
	for fc in biome.get("flowers", []):
		_add(PlantGen.grass(600 + _flowers.size(), grass_mat, biome.grass, float(biome.grass_h) * 0.9, 10, fc), "flower")
	for i in 4:
		_add(PlantGen.rock(700 + i, rock_mat, biome.rock), "rock")


var _tree_near: Dictionary = {}     # base material -> its close-up copy
var _singles: Dictionary = {}       # base material and role -> its copy


static func _lod(m: ShaderMaterial, role: int, end: float) -> void:
	m.set_shader_parameter("lod_role", role)
	m.set_shader_parameter("lod_range", detail_range)
	m.set_shader_parameter("lod_fade", TREE_FADE)
	m.set_shader_parameter("far_end", end)


## Move the hand-over for every biome's plants (materials are shared and cached).
static func set_detail_range(r: float) -> void:
	if is_equal_approx(r, detail_range):
		return
	detail_range = r
	for f: RealFlora in _cache.values():
		for m: ShaderMaterial in f._tree_near.values() + f._singles.values():
			m.set_shader_parameter("lod_range", r)


func _near(m: ShaderMaterial) -> ShaderMaterial:
	return _tree_near[m]


## The distant version's material: role 1, fading out at TREE_FAR.
func _far(m: ShaderMaterial) -> ShaderMaterial:
	var key := "%d:far" % m.get_instance_id()
	if not _singles.has(key):
		var f := m.duplicate() as ShaderMaterial
		_lod(f, 1, TREE_FAR)
		_singles[key] = f
	return _singles[key]


## A plant with one version, fading out at `end`.
func _single(m: ShaderMaterial, end: float) -> ShaderMaterial:
	var key := "%d:%d" % [m.get_instance_id(), int(end)]
	if not _singles.has(key):
		var f := m.duplicate() as ShaderMaterial
		_lod(f, 2, end)
		_singles[key] = f
	return _singles[key]


## The Sonoran desert's plants (they replace trees, bushes and grass).
func _build_desert(bark_mat: ShaderMaterial, leaf_mat: ShaderMaterial, rock_mat: ShaderMaterial) -> void:
	var skin := ShaderMaterial.new()
	skin.shader = load("res://scene/real/real_cactus.gdshader")
	_lod(skin, 2, TREE_FAR)
	var spines := skin.duplicate() as ShaderMaterial
	spines.set_shader_parameter("fuzz", 0.3)
	spines.set_shader_parameter("fuzz_color", Vector3(0.78, 0.72, 0.48))
	_lod(spines, 2, SMALL_FAR)
	var small_skin := skin.duplicate() as ShaderMaterial
	_lod(small_skin, 2, SMALL_FAR)
	for i in 6:
		_add(PlantGen.saguaro(800 + i, skin), "saguaro")
	for i in 3:
		_add(PlantGen.palo_verde(850 + i, _near(bark_mat), _near(leaf_mat)), "palo",
				PlantGen.palo_verde(850 + i, _far(bark_mat), _far(leaf_mat), 0.4))
	var stems := _single(bark_mat, SMALL_FAR)
	var leaves := _single(leaf_mat, SMALL_FAR)
	for i in 3:
		_add(PlantGen.ocotillo(870 + i, stems, leaves), "bush")
	for i in 3:
		_add(PlantGen.cholla(880 + i, spines), "bush")
	for i in 3:
		_add(PlantGen.prickly_pear(890 + i, small_skin), "bush")
	for i in 2:
		_add(PlantGen.barrel(900 + i, small_skin, leaves), "bush")
	for i in 5:
		_add(PlantGen.creosote(910 + i, stems, leaves), "bush")
	var grass_mat := leaf_mat.duplicate() as ShaderMaterial
	grass_mat.set_shader_parameter("translucency", 0.35)
	for i in 2:
		_add(PlantGen.grass(500 + i, grass_mat, biome.grass, float(biome.grass_h), int(biome.grass_blades)), "grass")
	for i in 5:
		_add(PlantGen.rock(700 + i, rock_mat, biome.rock), "rock")


func _add(m: Mesh, kind: String, far: Mesh = null) -> void:
	var i := meshes.size()
	meshes.append(m)
	if far:
		far_meshes[i] = far
	match kind:
		"spruce", "broad", "bare", "saguaro", "palo":
			kinds.append("tree")
			_trees.append(i)
			({"spruce": _spruce, "broad": _broad, "bare": _bare, "saguaro": _saguaro, "palo": _palo}[kind] as Array[int]).append(i)
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
## in_water: Callable(x, z, trail) -> half widths into the river (< 1 is water).
## own (route rides, R41): func(x, z) -> Vector3(belongs here 0/1, tree
## density multiplier, tree mix 0 own / 1 conifer / 2 broadleaf), so several
## biomes share the land along a route; invalid for an ordinary ride.
func scatter(z0: float, chunk_len: float, half_width: float, trail_clear: float, t: Trail, height: Callable,
		in_water: Callable = Callable(), own: Callable = Callable()) -> Dictionary:
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
			var o := Vector3(1.0, 1.0, 0.0) if not own.is_valid() else own.call(x, z) as Vector3
			if o.x <= 0.0:
				continue
			var clump := _clump.get_noise_2d(x, z) * 0.5 + 0.5
			var p := tree_share * o.y * (1.25 if lat < 0.0 else 0.8) * smoothstep(0.25, 0.65, clump)
			if rng.randf() > p:
				continue
			if in_water.is_valid() and float(in_water.call(x, z, t)) < 1.4:
				continue
			var y := float(height.call(x, z, t))
			var mi := _pick_tree(rng, int(o.z))
			var s := rng.randf_range(0.7, 1.25)
			_put(out, mi, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.1, z)), _tint(rng, 0.12))
	# Thinner woods out across the valley and up the far slopes (distant versions do most of the drawing).
	if not _trees.is_empty() and tree_share > 0.0:
		for i in 70:
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(half_width, 230.0) * (1.0 if rng.randf() < 0.6 else -1.0)
			var x := t.x_at(z) + lat
			var o := Vector3(1.0, 1.0, 0.0) if not own.is_valid() else own.call(x, z) as Vector3
			if o.x <= 0.0:
				continue
			if rng.randf() > tree_share * minf(o.y, 1.3) * 0.6 * smoothstep(0.3, 0.6, _clump.get_noise_2d(x, z) * 0.5 + 0.5):
				continue
			if in_water.is_valid() and float(in_water.call(x, z, t)) < 1.6:
				continue
			var y := float(height.call(x, z, t))
			var s := rng.randf_range(0.75, 1.25)
			_put(out, _pick_tree(rng, int(o.z)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.1, z)), _tint(rng, 0.12))
	# Bushes along the trail edges and in clearings.
	if not _bushes.is_empty():
		for i in int(40 * float(biome.bush)):
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(-30.0, 30.0)
			if absf(lat) < trail_clear + 1.2:
				continue
			var x := t.x_at(z) + lat
			if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
				continue
			if in_water.is_valid() and float(in_water.call(x, z, t)) < 1.25:
				continue
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
		if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
			continue
		if in_water.is_valid() and float(in_water.call(x, z, t)) < 0.7:
			continue
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
				if in_water.is_valid() and float(in_water.call(x, z, t)) < 1.08:
					continue
				if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
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


## Plants for a square of real ground (map rides, R42): the same rules as
## scatter(), but placed by world position. near(x, z) -> distance to the
## trail (999 far away); height(x, z) -> ground; own as in scatter().
func scatter_area(x0: float, z0: float, size: float, near: Callable, height: Callable, own: Callable, trail_clear: float) -> Dictionary:
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(x0), int(z0)))
	var area := size * size
	var tree_share := float(biome.trees)
	# Trees: clumped by noise, thinner far from the trail (as the strip's far woods).
	if not _trees.is_empty():
		for i in int(area * 0.036):
			var x := x0 + rng.randf() * size
			var z := z0 + rng.randf() * size
			var o := Vector3(1.0, 1.0, 0.0) if not own.is_valid() else own.call(x, z) as Vector3
			if o.x <= 0.0:
				continue
			var ad := float(near.call(x, z))
			if ad < trail_clear + 2.5:
				continue
			var clump := _clump.get_noise_2d(x, z) * 0.5 + 0.5
			var p := tree_share * o.y * (1.0 if ad < 70.0 else 0.6) * smoothstep(0.25, 0.65, clump)
			if o.y >= WOODS:
				# A wood: thick along the trail, thinner deeper in (its edge still reads as woods).
				p = tree_share * o.y * lerpf(0.5, 0.85, clump) * (1.0 if ad < 90.0 else 0.55)
			if rng.randf() > p:
				continue
			var s := rng.randf_range(0.7, 1.25)
			_put(out, _pick_tree(rng, int(o.z)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, float(height.call(x, z)) - 0.1, z)), _tint(rng, 0.12))
	# Bushes and rocks, mostly near the trail.
	if not _bushes.is_empty():
		for i in int(area * 0.028 * float(biome.bush)):
			var x := x0 + rng.randf() * size
			var z := z0 + rng.randf() * size
			var ad := float(near.call(x, z))
			if ad < trail_clear + 1.2 or ad > 30.0 + rng.randf() * 60.0:
				continue
			if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
				continue
			var s := rng.randf_range(0.6, 1.4)
			_put(out, _bushes[rng.randi() % _bushes.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, float(height.call(x, z)) - 0.05, z)), _tint(rng, 0.15))
	for i in int(area * 0.0042 * float(biome.rocks)):
		var x := x0 + rng.randf() * size
		var z := z0 + rng.randf() * size
		if float(near.call(x, z)) < trail_clear + 0.6:
			continue
		if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
			continue
		var s := 0.15 + 1.5 * pow(rng.randf(), 2.6)
		var basis := Basis(Vector3(rng.randf_range(-1.0, 1.0), 1.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf() * TAU)
		_put(out, _rocks[rng.randi() % _rocks.size()], Transform3D(basis.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), Vector3(x, float(height.call(x, z)) - s * 0.25, z)), _tint(rng, 0.1))
	# Grass: a jittered grid within reach of the trail, thinning with distance.
	var density := 0.0 if OS.get_cmdline_user_args().has("nograss") else float(biome.grass_density)
	var grass_here := float(near.call(x0 + size * 0.5, z0 + size * 0.5)) < GRASS_REACH + size * 0.75
	if density > 0.0 and not _grass.is_empty() and grass_here:
		var step := 0.4 / sqrt(density)
		var gz := z0
		while gz < z0 + size:
			var gx := x0
			while gx < x0 + size:
				var x := gx + rng.randf_range(-0.2, 0.2)
				var z := gz + rng.randf_range(-0.2, 0.2)
				var ad := float(near.call(x, z))
				gx += step * (1.0 + minf(ad, GRASS_REACH) * 0.06) * rng.randf_range(0.7, 1.3)
				if ad > GRASS_REACH or ad < trail_clear * 0.8:
					continue
				var patch := _clump.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
				if rng.randf() > density * smoothstep(0.15, 0.55, patch) + 0.08:
					continue
				if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
					continue
				var edge := smoothstep(trail_clear * 0.8, trail_clear + 0.8, ad)
				var s := rng.randf_range(0.7, 1.3) * lerpf(0.55, 1.0, edge)
				var mi := _grass[rng.randi() % _grass.size()]
				if not _flowers.is_empty() and rng.randf() < float(biome.get("flower_share", 0.0)):
					mi = _flowers[rng.randi() % _flowers.size()]
				_put(out, mi, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, float(height.call(x, z)) - 0.02, z)), _tint(rng, 0.2))
			gz += step * rng.randf_range(0.8, 1.2)
	return out


func _pick_tree(rng: RandomNumberGenerator, mix := 0) -> int:
	# A route's woods can be all conifer or all broadleaf (OpenStreetMap's leaf_type).
	if mix == 1 and not _spruce.is_empty() and rng.randf() < 0.85:
		return _spruce[rng.randi() % _spruce.size()]
	if mix == 2 and not _broad.is_empty() and rng.randf() < 0.85:
		return _broad[rng.randi() % _broad.size()]
	var pools := [[float(biome.spruce), _spruce], [float(biome.broad), _broad], [float(biome.bare), _bare],
		[float(biome.get("saguaro", 0.0)), _saguaro], [float(biome.get("palo", 0.0)), _palo]]
	var total := 0.0
	for p in pools:
		total += float(p[0])
	var r := rng.randf() * total
	for p in pools:
		r -= float(p[0])
		if r <= 0.0 and not (p[1] as Array).is_empty():
			return p[1][rng.randi() % (p[1] as Array).size()]
	return _trees[rng.randi() % _trees.size()]


func _tint(rng: RandomNumberGenerator, spread: float) -> Color:
	var v := rng.randf_range(1.0 - spread, 1.0 + spread)
	return Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.93, 1.05), 1.0)


## A boulder at pos (its middle) for TerrainStreamer's streams.
func add_rock(out: Dictionary, pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	if _rocks.is_empty():
		return
	var basis := Basis(Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), rng.randf() * TAU)
	_put(out, _rocks[rng.randi() % _rocks.size()], Transform3D(basis.scaled(Vector3(size, size * rng.randf_range(0.85, 1.25), size)), pos), _tint(rng, 0.1))


static func _put(out: Dictionary, mi: int, xf: Transform3D, tint: Color) -> void:
	if not out.has(mi):
		out[mi] = [[] as Array[Transform3D], [] as Array[Color]]
	out[mi][0].append(xf)
	out[mi][1].append(tint)
