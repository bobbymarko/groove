class_name RealFlora
extends RefCounted
## The realistic look's plants and rocks for one biome: a few seeded variants of
## each kind built by PlantGen (once per app run and biome; a tree in three
## versions: close-up, middle distance and a flat picture drawn by PlantBake,
## plus a cheap shadow caster), and the scatter that places them around a
## terrain chunk. scatter() runs on the terrain worker thread, so it touches
## no nodes. The meadow is RealGrass's.

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
const GRASS_VISIBLE := 65.0      ## (the old per-chunk grass; RealGrass draws the meadow now)
const NEAR_RANGE := 28.0         ## a tree's close-up version hands over to its middle one around here
const NEAR_FADE := 8.0
const TREE_DETAIL_RANGE := 64.0  ## and the middle one to its flat picture around here (in the shaders)
const TREE_FADE := 20.0
const SHADE_RANGE := 32.0        ## a tree's shadow comes from its middle version within this, from its picture (turned to the sun) beyond
const SHADE_FADE := 10.0
const TREE_FAR := 300.0          ## trees dither away by here unless a ride says otherwise (set_ranges)
const SMALL_FAR := 150.0         ## bushes and rocks
const FAR_WOODS := 600.0         ## the strip's woods reach this far either side (pictures only out there)

static var _cache: Dictionary = {}   # biome id -> RealFlora
## Where a tree's middle version hands over to its picture for the ride now
## showing: TREE_DETAIL_RANGE on the strip; nearer on a true-map ride, whose
## trees stand all round the rider, not only along the trail.
static var detail_range := TREE_DETAIL_RANGE
static var tree_far := TREE_FAR       ## trees are gone by this distance,
static var tree_far_z := 100000.0     ## and by this far along the trail (the strip's ground ends there)

var biome: Dictionary = {}
var meshes: Array[Mesh] = []         ## each plant's closest (or only) version
var kinds: Array[String] = []        ## "tree", "bush", "rock" per mesh
var mid_meshes: Dictionary = {}      ## tree mesh index -> its middle-distance version
var shade_meshes: Dictionary = {}    ## tree mesh index -> the same shape as its shadow caster (solid out to the handover)
var picture_rows: Dictionary = {}    ## tree mesh index -> its row in the picture atlas
var picture_mesh: Mesh               ## the card far trees are drawn on (null without a renderer)
var picture_shade_mesh: Mesh         ## the same card as shadow caster (it faces the sun in the shadow pass)
var _trees: Array[int] = []
var _spruce: Array[int] = []
var _broad: Array[int] = []
var _bare: Array[int] = []
var _saguaro: Array[int] = []
var _palo: Array[int] = []
var _bushes: Array[int] = []
var _rocks: Array[int] = []
var _clump := FastNoiseLite.new()
var _wood := FastNoiseLite.new()     ## where the far slopes are wooded and where open
var biome_id := ""
var _lod_mats: Array = []            # [material, role]: every material with a range, for set_ranges
var _roles: Dictionary = {}          # "<base material id>:<role>" -> its copy
var _bake_list: Array = []           # trees waiting for their pictures: {mesh, color}
var _picture_mat: ShaderMaterial


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
	_wood.seed = 78
	_wood.frequency = 0.006
	_wood.fractal_octaves = 3
	var snow := float(biome.get("snow", 0.0))
	PlantBake.ensure_leaf_atlas()
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://scene/real/real_leaf.gdshader")
	leaf_mat.set_shader_parameter("leaf_albedo", PlantBake.leaf_albedo)
	leaf_mat.set_shader_parameter("leaf_data", PlantBake.leaf_data)
	leaf_mat.set_shader_parameter("snow", snow)
	var needle_mat := leaf_mat.duplicate() as ShaderMaterial
	needle_mat.set_shader_parameter("translucency", 0.3)
	needle_mat.set_shader_parameter("roundness", 0.45)
	var bark_col: Color = biome.get("bark", Color(0.26, 0.21, 0.16))
	var twig_mat := leaf_mat.duplicate() as ShaderMaterial      # a bare tree's sprays of twigs
	twig_mat.set_shader_parameter("wood_color", Vector3(bark_col.r, bark_col.g, bark_col.b) * 0.8)
	twig_mat.set_shader_parameter("translucency", 0.0)
	var bark_mat := ShaderMaterial.new()
	bark_mat.shader = load("res://scene/real/real_bark.gdshader")
	bark_mat.set_shader_parameter("snow", snow * 0.8)
	var birch_mat := ShaderMaterial.new()
	birch_mat.shader = bark_mat.shader
	birch_mat.set_shader_parameter("birch", 1.0)
	var rock_mat := ShaderMaterial.new()
	rock_mat.shader = load("res://scene/real/real_rock.gdshader")
	rock_mat.set_shader_parameter("snow", snow)
	rock_mat.set_shader_parameter("moss_amount", float(biome.get("moss", 0.0)))
	rock_mat = _role(rock_mat, "small")
	if biome.get("ground", "") == "desert":
		_build_desert(bark_mat, leaf_mat, rock_mat)
		_bake_pictures(snow)
		return
	var birch := bool(biome.get("birch", false))
	if float(biome.trees) > 0.0:
		if float(biome.spruce) > 0.0:
			for i in 4:
				var sd := 100 + i
				_add(PlantGen.spruce(sd, _role(bark_mat, "near"), _role(needle_mat, "near"), biome.needle), "spruce",
						PlantGen.spruce(sd, null, _role(needle_mat, "mid"), biome.needle, 1),
						PlantGen.spruce(sd, null, _role(needle_mat, "shade"), biome.needle, 2), biome.needle)
		if float(biome.broad) > 0.0:
			var cols: Array = biome.get("leaves", [Color(0.12, 0.24, 0.05)])
			var wood := birch_mat if birch else bark_mat
			# A birch's limbs in the middle version are pale too.
			var limb := Color(0.7, 0.68, 0.64) if birch else bark_col
			for i in 4:
				var sd := 200 + i
				var lc: Color = cols[i % cols.size()]
				_add(PlantGen.broadleaf(sd, _role(wood, "near"), _role(leaf_mat, "near"), lc, bark_col, birch), "broad",
						PlantGen.broadleaf(sd, null, _role(leaf_mat, "mid"), lc, limb, birch, false, 1),
						PlantGen.broadleaf(sd, null, _role(leaf_mat, "shade"), lc, limb, birch, false, 2), lc)
		if float(biome.bare) > 0.0:
			var dark := bark_col.darkened(0.2)
			for i in 2:
				var sd := 300 + i
				_add(PlantGen.broadleaf(sd, _role(bark_mat, "near"), _role(twig_mat, "near"), Color.WHITE, dark, false, true), "bare",
						PlantGen.broadleaf(sd, null, _role(twig_mat, "mid"), Color.WHITE, dark, false, true, 1),
						PlantGen.broadleaf(sd, null, _role(twig_mat, "shade"), Color.WHITE, dark, false, true, 2), dark)
	if float(biome.bush) > 0.0:
		var bc: Color = biome.get("bush_leaves", biome.get("leaves", [Color(0.12, 0.22, 0.05)])[0])
		for i in 3:
			_add(PlantGen.bush(400 + i, _role(leaf_mat, "small"), bc), "bush")
	for i in 4:
		_add(PlantGen.rock(700 + i, rock_mat, biome.rock), "rock")
	_bake_pictures(snow)


## A copy of a plant material for one level of detail ("near", "mid", "shade":
## a tree's three versions; "small": bushes and rocks, one version out to SMALL_FAR).
func _role(m: ShaderMaterial, role: String) -> ShaderMaterial:
	var key := "%d:%s" % [m.get_instance_id(), role]
	if not _roles.has(key):
		var f := m.duplicate() as ShaderMaterial
		_roles[key] = f
		_lod_mats.append([f, role])
		_apply_range(f, role)
	return _roles[key]


static func _apply_range(m: ShaderMaterial, role: String) -> void:
	m.set_shader_parameter("lod_in_fade", NEAR_FADE)
	m.set_shader_parameter("lod_out_fade", TREE_FADE)
	m.set_shader_parameter("far_fade", 60.0)
	match role:
		"near":
			m.set_shader_parameter("lod_out", NEAR_RANGE)
			m.set_shader_parameter("lod_out_fade", NEAR_FADE)
			m.set_shader_parameter("far_end", 100000.0)
		"mid":
			m.set_shader_parameter("lod_in", NEAR_RANGE)
			m.set_shader_parameter("lod_out", detail_range)
			m.set_shader_parameter("sway_end", detail_range - TREE_FADE * 0.5)
			m.set_shader_parameter("far_end", 100000.0)
		"shade":
			m.set_shader_parameter("lod_out", SHADE_RANGE)
			m.set_shader_parameter("lod_out_fade", SHADE_FADE)
			m.set_shader_parameter("far_end", 100000.0)
		"picture_shade":
			m.set_shader_parameter("lod_in", SHADE_RANGE)
			m.set_shader_parameter("lod_in_fade", SHADE_FADE)
			m.set_shader_parameter("far_end", 400.0)
		"mid_only":      # no pictures: the middle version carries on to the trees' end
			m.set_shader_parameter("lod_in", NEAR_RANGE)
			m.set_shader_parameter("far_end", minf(tree_far, TREE_FAR))
		"shade_only":
			m.set_shader_parameter("far_end", 140.0)
		"picture":
			m.set_shader_parameter("lod_in", detail_range)
			m.set_shader_parameter("lod_in_fade", TREE_FADE)
			m.set_shader_parameter("far_end", tree_far)
			m.set_shader_parameter("far_z", tree_far_z)
		_:
			m.set_shader_parameter("far_end", SMALL_FAR)
			m.set_shader_parameter("far_fade", 40.0)


## Set this ride's tree ranges for every biome's plants (materials are shared
## and cached): where the middle version becomes a picture, and where trees end.
static func set_ranges(detail: float, far: float, far_z := 100000.0) -> void:
	if is_equal_approx(detail, detail_range) and is_equal_approx(far, tree_far) and is_equal_approx(far_z, tree_far_z):
		return
	detail_range = detail
	tree_far = far
	tree_far_z = far_z
	for f: RealFlora in _cache.values():
		for lm: Array in f._lod_mats:
			_apply_range(lm[0], lm[1])


## Draw this biome's trees into its picture atlas and make the card they are shown on.
func _bake_pictures(snow: float) -> void:
	if _bake_list.is_empty():
		return
	for v: Dictionary in _bake_list:
		var c: Color = v.color
		v.color = (c * 0.6).lerp(Color(0.8, 0.82, 0.86), snow * 0.35)
	var baked := PlantBake.impostors(_bake_list)
	_bake_list.clear()
	if baked.is_empty():
		# No renderer (tests), or the bake failed: the middle versions carry on to the trees' end.
		picture_rows.clear()
		for lm: Array in _lod_mats:
			if lm[1] == "mid" or lm[1] == "shade":
				lm[1] = "mid_only" if lm[1] == "mid" else "shade_only"
				(lm[0] as ShaderMaterial).set_shader_parameter("lod_out", 100000.0)
				_apply_range(lm[0], lm[1])
		return
	_picture_mat = ShaderMaterial.new()
	_picture_mat.shader = load("res://scene/real/real_impostor.gdshader")
	_picture_mat.set_shader_parameter("imp_albedo", baked.albedo)
	_picture_mat.set_shader_parameter("imp_data", baked.data)
	_picture_mat.set_shader_parameter("sizes", baked.sizes)
	_picture_mat.set_shader_parameter("frames", float(PlantBake.ANGLES))
	_picture_mat.set_shader_parameter("rows", baked.rows)
	_lod_mats.append([_picture_mat, "picture"])
	_apply_range(_picture_mat, "picture")
	# A unit card: x and y only say which corner (the shader places it from UV).
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _picture_mat)
	picture_mesh = m
	var shade_mat := _picture_mat.duplicate() as ShaderMaterial
	_lod_mats.append([shade_mat, "picture_shade"])
	_apply_range(shade_mat, "picture_shade")
	var sm := ArrayMesh.new()
	sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	sm.surface_set_material(0, shade_mat)
	picture_shade_mesh = sm


## The Sonoran desert's plants (they replace trees and bushes).
func _build_desert(bark_mat: ShaderMaterial, leaf_mat: ShaderMaterial, rock_mat: ShaderMaterial) -> void:
	var skin := ShaderMaterial.new()
	skin.shader = load("res://scene/real/real_cactus.gdshader")
	var spines := skin.duplicate() as ShaderMaterial
	spines.set_shader_parameter("fuzz", 0.3)
	spines.set_shader_parameter("fuzz_color", Vector3(0.78, 0.72, 0.48))
	spines = _role(spines, "small")
	var small_skin := _role(skin, "small")
	var old_leaf := ShaderMaterial.new()                 # ocotillo's leaves and flower tips, a barrel's flowers: solid blades
	old_leaf.shader = load("res://scene/real/real_foliage.gdshader")
	old_leaf = _role(old_leaf, "small")
	for i in 6:
		_add(PlantGen.saguaro(800 + i, _role(skin, "near")), "saguaro",
				PlantGen.saguaro(800 + i, _role(skin, "mid"), 1), PlantGen.saguaro(800 + i, _role(skin, "shade"), 1), Color(0.28, 0.35, 0.2))
	for i in 3:
		_add(PlantGen.palo_verde(850 + i, _role(bark_mat, "near"), _role(leaf_mat, "near")), "palo",
				PlantGen.palo_verde(850 + i, null, _role(leaf_mat, "mid"), 1), PlantGen.palo_verde(850 + i, null, _role(leaf_mat, "shade"), 2), Color(0.46, 0.52, 0.16))
	var stems := _role(bark_mat, "small")
	for i in 3:
		_add(PlantGen.ocotillo(870 + i, stems, old_leaf), "bush")
	for i in 3:
		_add(PlantGen.cholla(880 + i, spines), "bush")
	for i in 3:
		_add(PlantGen.prickly_pear(890 + i, small_skin), "bush")
	for i in 2:
		_add(PlantGen.barrel(900 + i, small_skin, old_leaf), "bush")
	for i in 5:
		_add(PlantGen.creosote(910 + i, _role(leaf_mat, "small")), "bush")
	for i in 5:
		_add(PlantGen.rock(700 + i, rock_mat, biome.rock), "rock")


## A plant variant. Trees come with their middle version, that shape again as
## shadow caster, and the colour behind their picture.
func _add(m: Mesh, kind: String, mid: Mesh = null, shade: Mesh = null, color := Color.BLACK) -> void:
	var i := meshes.size()
	meshes.append(m)
	if mid:
		mid_meshes[i] = mid
		shade_meshes[i] = shade
		picture_rows[i] = _bake_list.size()
		_bake_list.append({"mesh": mid, "color": color})
	match kind:
		"spruce", "broad", "bare", "saguaro", "palo":
			kinds.append("tree")
			_trees.append(i)
			({"spruce": _spruce, "broad": _broad, "bare": _bare, "saguaro": _saguaro, "palo": _palo}[kind] as Array[int]).append(i)
		"bush":
			kinds.append("bush")
			_bushes.append(i)
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
	# Woods out across the valley and up the far slopes, as far as the ground
	# goes: flat pictures out there, so real forest costs little. Broad noise
	# leaves meadows and clearings between the stands.
	if not _trees.is_empty() and tree_share > 0.0:
		for i in int(520 * minf(tree_share * 2.0, 1.2)):
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(half_width, FAR_WOODS) * (1.0 if rng.randf() < 0.5 else -1.0)
			var x := t.x_at(z) + lat
			var o := Vector3(1.0, 1.0, 0.0) if not own.is_valid() else own.call(x, z) as Vector3
			if o.x <= 0.0:
				continue
			var stand := smoothstep(-0.25, 0.1, _wood.get_noise_2d(x, z)) * (0.35 + 0.65 * smoothstep(0.2, 0.5, _clump.get_noise_2d(x, z) * 0.5 + 0.5))
			if rng.randf() > minf(o.y, 1.3) * stand:
				continue
			if absf(lat) < 240.0 and in_water.is_valid() and float(in_water.call(x, z, t)) < 1.6:
				continue
			var y := float(height.call(x, z, t))
			var s := rng.randf_range(0.8, 1.3)
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
