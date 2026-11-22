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
		"bush": 0.0, "rock": Color(0.42, 0.41, 0.4), "rocks": 1.0,
		"under": {"seed": 0.8, "seed_col": Color(0.5, 0.42, 0.26), "young": 1.0, "bare_shrub": 0.6, "log": 0.5, "stump": 0.4, "stick": 0.3, "stones": 0.3}},
	"summer": {"range": 700.0, "range_scrub": Color(0.16, 0.22, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.25, "broad": 0.75, "bare": 0.0, "trees": 0.5,
		"needle": Color(0.06, 0.15, 0.07), "bark": Color(0.27, 0.22, 0.17), "leaves": [Color(0.1, 0.22, 0.05), Color(0.13, 0.25, 0.05)],
		"grass": Color(0.13, 0.24, 0.06), "grass_h": 0.5, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85), Color(0.95, 0.78, 0.15)], "flower_share": 0.06,
		"bush": 0.6, "rock": Color(0.4, 0.39, 0.37), "rocks": 0.6, "moss": 0.6,
		"under": {"fern": 1.0, "fern_col": Color(0.11, 0.25, 0.055), "herb": 1.0, "herb_col": Color(0.2, 0.36, 0.08), "umbel": 0.7, "fireweed": 0.8,
			"seed": 0.6, "seed_col": Color(0.4, 0.4, 0.17),      # grasses gone to seed, standing over the meadow
			"sapling": 0.7, "young": 0.4, "shrub": 0.5, "thorn": 0.4, "log": 0.5, "stump": 0.3, "stick": 0.5, "litter": 0.07, "litter_col": Color(0.3, 0.2, 0.1), "stones": 0.5}},
	"autumn": {"range": 800.0, "range_scrub": Color(0.3, 0.22, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.2, "broad": 0.8, "bare": 0.05, "trees": 0.5,
		"needle": Color(0.06, 0.14, 0.07), "bark": Color(0.25, 0.2, 0.16),
		"leaves": [Color(0.75, 0.32, 0.05), Color(0.8, 0.55, 0.08), Color(0.55, 0.12, 0.04), Color(0.45, 0.45, 0.08)],
		"grass": Color(0.24, 0.22, 0.08), "grass_h": 0.45, "grass_blades": 14, "grass_density": 0.8,
		"bush": 0.5, "rock": Color(0.4, 0.38, 0.35), "rocks": 0.7, "moss": 0.4,
		"under": {"fern": 0.8, "fern_col": Color(0.4, 0.3, 0.07), "herb": 0.6, "herb_col": Color(0.4, 0.34, 0.09), "seed": 0.8, "seed_col": Color(0.46, 0.36, 0.2),
			"sapling": 0.7, "young": 0.4, "shrub": 0.5, "thorn": 0.4, "log": 0.5, "stump": 0.3, "stick": 0.6,
			"litter": 1.0, "litter_col": Color(0.6, 0.36, 0.1), "verge_litter": 1.0, "stones": 0.5}},
	"spring": {"range": 650.0, "range_scrub": Color(0.18, 0.26, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.2, "broad": 0.8, "bare": 0.0, "trees": 0.45,
		"needle": Color(0.07, 0.17, 0.08), "bark": Color(0.28, 0.23, 0.18), "leaves": [Color(0.2, 0.36, 0.06), Color(0.85, 0.75, 0.8)],
		"grass": Color(0.15, 0.3, 0.06), "grass_h": 0.4, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85), Color(0.95, 0.8, 0.12), Color(0.55, 0.35, 0.8), Color(0.85, 0.2, 0.15)], "flower_share": 0.25,
		"bush": 0.6, "rock": Color(0.42, 0.41, 0.39), "rocks": 0.5, "moss": 0.7,
		"under": {"fern": 0.6, "fern_col": Color(0.2, 0.36, 0.08), "herb": 1.0, "herb_col": Color(0.24, 0.42, 0.09), "umbel": 1.2,
			"sapling": 0.7, "young": 0.4, "shrub": 0.5, "thorn": 0.4, "log": 0.5, "stump": 0.3, "stick": 0.6, "litter": 0.15, "litter_col": Color(0.4, 0.3, 0.18), "stones": 0.5}},
	# Sonoran desert, after Tucson: saguaros over palo verde, ocotillo, cholla,
	# prickly pear, barrel cactus and creosote on decomposed-granite gravel,
	# granite boulders, rugged mountains behind, a big clear sky and a high sun.
	"desert": {"range": 1500.0, "range_rock": Color(0.46, 0.3, 0.24), "range_scrub": Color(0.3, 0.28, 0.17), "ground": "desert", "snow": 0.0, "spruce": 0.0, "broad": 0.0, "bare": 0.0, "saguaro": 0.6, "palo": 0.4, "trees": 0.32,
		"grass": Color(0.5, 0.44, 0.27), "grass_h": 0.32, "grass_blades": 9, "grass_density": 0.14,
		"bush": 1.6, "rock": Color(0.56, 0.47, 0.4), "rocks": 2.2, "clouds": 0.22, "noon": 62.0,
		"relief": 320.0, "relief_from": 280.0, "hills": 0.3,
		"under": {"seed": 0.4, "seed_col": Color(0.6, 0.52, 0.32), "dry": 1.0, "dry_col": Color(0.8, 0.7, 0.42), "log": 0.25, "stick": 0.8, "stones": 2.0}},
	"birchwood": {"range": 700.0, "range_scrub": Color(0.18, 0.24, 0.1), "water": "river", "ground": "grass", "snow": 0.0, "spruce": 0.0, "broad": 1.0, "bare": 0.0, "trees": 0.55, "birch": true,
		"bark": Color(0.8, 0.78, 0.74), "leaves": [Color(0.3, 0.42, 0.08), Color(0.24, 0.38, 0.07)],
		"grass": Color(0.16, 0.28, 0.07), "grass_h": 0.5, "grass_blades": 15, "grass_density": 1.0,
		"flowers": [Color(0.95, 0.93, 0.85)], "flower_share": 0.05,
		"bush": 0.4, "rock": Color(0.42, 0.41, 0.39), "rocks": 0.4, "moss": 0.6,
		"under": {"fern": 1.2, "bracken": 0.7, "fern_col": Color(0.14, 0.29, 0.06), "herb": 0.8, "herb_col": Color(0.22, 0.38, 0.085), "umbel": 0.5, "fireweed": 0.5,
			"sapling": 0.9, "shrub": 0.3, "shrub_col": Color(0.15, 0.27, 0.07), "thorn": 0.3, "log": 0.5, "stump": 0.3, "stick": 0.6, "litter": 0.07, "litter_col": Color(0.34, 0.26, 0.12), "stones": 0.3}},
	"apocalypse": {"range": 900.0, "range_rock": Color(0.22, 0.2, 0.19), "range_scrub": Color(0.2, 0.19, 0.16), "water": "river", "water_tint": Color(0.05, 0.05, 0.03), "ground": "grass", "snow": 0.0, "spruce": 0.0, "broad": 0.0, "bare": 1.0, "trees": 0.35,
		"bark": Color(0.18, 0.16, 0.14), "grass": Color(0.3, 0.27, 0.16), "grass_h": 0.4, "grass_blades": 8, "grass_density": 0.3,
		"bush": 0.0, "rock": Color(0.3, 0.29, 0.28), "rocks": 1.0,
		"under": {"seed": 0.6, "seed_col": Color(0.28, 0.25, 0.18), "bare_shrub": 0.8, "log": 1.0, "stump": 0.8, "stick": 1.2, "stones": 0.8}},
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
const UNDER_FAR := 46.0          ## ferns, herbs, fallen leaves, sticks and small stones are gone by here (times the tier's under_reach)
const UNDER_FADE := 18.0
const SMALL_NEAR := 32.0         ## a bush's, boulder's or log's close-up hands over to its cheap version around here (times range_mult)
const LOW_FAR := 100.0           ## low things end here (saplings, young spruces, stumps, barrel cacti)
const SHADE_SMALL := 30.0        ## small plants throw shadows within this (cast by their cheap version)
const UNDER_REACH := 28.0        ## undergrowth is planted within this of the trail (thinning fast past a dozen metres); under TerrainStreamer.BAND_WIDTH, so each chunk's lies in one band, and near enough its middle for BAND_PAD

static var _cache: Dictionary = {}   # biome id -> RealFlora
## Where a tree's middle version hands over to its picture for the ride now
## showing: TREE_DETAIL_RANGE on the strip; nearer on a true-map ride, whose
## trees stand all round the rider, not only along the trail.
static var detail_range := TREE_DETAIL_RANGE
static var tree_far := TREE_FAR       ## trees are gone by this distance,
static var tree_far_z := 100000.0     ## and by this far along the trail (the strip's ground ends there)


## Where a tree's close-up version hands over to the middle one, for the quality tier (RealQuality).
static func near_range() -> float:
	return NEAR_RANGE * float(RealQuality.get_value("range_mult"))


## Where a small plant's close-up hands over to its cheap version, for the quality tier.
static func small_near() -> float:
	return SMALL_NEAR * float(RealQuality.get_value("range_mult"))


## Where the undergrowth ends, for the quality tier.
static func under_far() -> float:
	return UNDER_FAR * float(RealQuality.get_value("under_reach"))


## Where the lowest of it ends (leafy herbs, fallen leaves, sticks, small stones:
## a hand high, they are a few pixels by here and cost what a fern does).
static func under_low_far() -> float:
	return under_far() * 0.68

var biome: Dictionary = {}
var meshes: Array[Mesh] = []         ## each plant's closest (or only) version
var kinds: Array[String] = []        ## per mesh, how it meets the ground: "tree", "bush", "rock", or "flat" (casts nothing, shades nothing)
var far_meshes: Dictionary = {}      ## small plant index -> its cheap distant version (bushes, boulders, logs, cacti)
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
var _pools: Dictionary = {}          # what scatter picks from: "bush", "rock", "fern", "log"... -> Array[int] of mesh indices
var _ends: Dictionary = {}           # small plant index -> where it is gone (metres)
var _shade_mats: Dictionary = {}     # small plant index -> the material its cheap version wears as shadow caster
var _casts: Dictionary = {}          # small plants of one version that throw a shadow near the trail
var _patch := FastNoiseLite.new()    ## where the undergrowth's drifts lie
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
	_patch.seed = 79
	_patch.frequency = 0.055
	_patch.fractal_octaves = 2
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
	SurfaceTex.rock(rock_mat)
	if biome.get("ground", "") == "desert":
		_build_desert(bark_mat, leaf_mat, twig_mat, rock_mat)
		_bake_pictures(snow)
		return
	# Scanned bark (palo verde above keeps its smooth noise bark): pine on spruces, oak on broadleaves and bare trees.
	var pine_mat := bark_mat.duplicate() as ShaderMaterial
	SurfaceTex.bark(pine_mat, "bark_pine")
	SurfaceTex.bark(bark_mat, "bark_oak")
	SurfaceTex.bark(birch_mat, "bark_birch")
	var birch := bool(biome.get("birch", false))
	if float(biome.trees) > 0.0:
		if float(biome.spruce) > 0.0:
			for i in 4:
				var sd := 100 + i
				_add(PlantGen.spruce(sd, _role(pine_mat, "near"), _role(needle_mat, "near"), biome.needle), "spruce",
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
		for i in 2:
			_add_small("bush", "bush", PlantGen.bush(400 + i, _role(leaf_mat, "near_small"), bc),
					PlantGen.bush(400 + i, _role(leaf_mat, "far_low"), bc, [PlantGen.LEAF_A, PlantGen.LEAF_B, PlantGen.LEAF_C], 0.85, 0, 1), _role(leaf_mat, "shade_small"), LOW_FAR)
	_build_under(leaf_mat, needle_mat, twig_mat, birch_mat if birch else (pine_mat if float(biome.spruce) > 0.6 else bark_mat), snow)
	_build_rocks(rock_mat, 4)
	_bake_pictures(snow)


## The undergrowth this biome lists (BIOMES' "under"): what stands between the grass and the trees.
func _build_under(leaf_mat: ShaderMaterial, needle_mat: ShaderMaterial, twig_mat: ShaderMaterial, wood_mat: ShaderMaterial, snow: float) -> void:
	var u: Dictionary = biome.get("under", {})
	if u.is_empty():
		return
	# Ferns, herbs and fallen leaves all wear this one. No snow on it: what
	# stands in winter is dry stalks, and they poke out of the snow bare.
	var under_base := leaf_mat
	if snow > 0.0:
		under_base = leaf_mat.duplicate() as ShaderMaterial
		under_base.set_shader_parameter("snow", 0.0)
	var under := _role(under_base, "under")
	var low := _role(under_base, "under_low")
	var leaves: Array = biome.get("leaves", [Color(0.12, 0.24, 0.05)])
	var bark_col: Color = biome.get("bark", Color(0.26, 0.21, 0.16))
	var birch := bool(biome.get("birch", false))
	var cells: Array = [PlantGen.LEAF_A, PlantGen.LEAF_B, PlantGen.LEAF_C]
	if float(u.get("fern", 0.0)) > 0.0:
		var fc: Color = u.get("fern_col", Color(0.11, 0.25, 0.055))
		_add_small("fern", "bush", PlantGen.fern(500, under, fc), null, null, under_far())
		_add_small("bracken", "bush", PlantGen.fern(510, under, fc.lerp(Color(fc.r * 1.2, fc.g * 1.05, fc.b, 1.0), 0.6), true), null, null, under_far())
	if float(u.get("herb", 0.0)) > 0.0:
		var hc: Color = u.get("herb_col", Color(0.12, 0.24, 0.055))
		# (both stand over the meadow's grass: a lower herb would only hide in it)
		_add_small("herb", "flat", PlantGen.herb(520, low, [PlantGen.HERB_C], 0.52, 2, hc, 1.05), null, null, under_low_far())
		_add_small("herb", "flat", PlantGen.herb(521, low, [PlantGen.LEAF_SMALL, PlantGen.HERB_C], 0.78, 2, hc, 0.75), null, null, under_low_far())
	if float(u.get("umbel", 0.0)) > 0.0:
		_add_small("umbel", "flat", PlantGen.herb(530, under, [PlantGen.HERB_A], 1.15, 2, Color(1.0, 1.0, 1.0), 0.9), null, null, under_far())
	if float(u.get("fireweed", 0.0)) > 0.0:
		_add_small("fireweed", "flat", PlantGen.herb(540, under, [PlantGen.HERB_B], 1.5, 2, Color(1.0, 1.0, 1.0), 0.62), null, null, under_far())
	if float(u.get("seed", 0.0)) > 0.0:
		for i in 2:
			_add_small("seed", "flat", PlantGen.herb(550 + i, under, [PlantGen.SEED_A], 0.8 + 0.25 * i, 2, u.get("seed_col", Color(0.5, 0.42, 0.26)), 0.8, 0.75), null, null, under_far())
	if float(u.get("dry", 0.0)) > 0.0:
		for i in 2:
			_add_small("dry", "flat", PlantGen.herb(555 + i, under, [PlantGen.GRASS_A, PlantGen.GRASS_B], 0.4 + 0.15 * i, 4, u.get("dry_col", Color(0.6, 0.52, 0.32)), 1.0, 0.8), null, null, under_far())
	if float(u.get("sapling", 0.0)) > 0.0 and float(biome.broad) > 0.0:
		var stem := Color(0.6, 0.57, 0.52) if birch else bark_col
		_add_small("sapling", "bush", PlantGen.sapling(560, _role(leaf_mat, "low"), leaves[0], stem, [PlantGen.BIRCH_A, PlantGen.LEAF_SMALL] if birch else cells, birch), null, null, LOW_FAR)
	if float(u.get("young", 0.0)) > 0.0 and float(biome.spruce) > 0.0:
		# In winter the small spruces carry far more snow than the tall ones (it does not slide off them).
		var nm := needle_mat
		if snow > 0.0:
			nm = needle_mat.duplicate() as ShaderMaterial
			nm.set_shader_parameter("snow", 1.0)
		var needle: Color = biome.needle
		# (no shadow caster for these or for shrubs: among the trees' shadows theirs are not missed, and the contact shade grounds them)
		_add_small("young", "bush", PlantGen.young_spruce(570, _role(nm, "near_low"), needle.lightened(0.03)),
				PlantGen.young_spruce(570, _role(nm, "far_low"), needle.lightened(0.03), 1), null, LOW_FAR)
	if float(u.get("shrub", 0.0)) > 0.0:
		var sc: Color = u.get("shrub_col", (leaves[leaves.size() - 1] as Color).darkened(0.18))
		_add_small("shrub", "bush", PlantGen.bush(580, _role(leaf_mat, "near_small"), sc, cells, 0.95, 1),
				PlantGen.bush(580, _role(leaf_mat, "far_low"), sc, cells, 0.95, 1, 1), null, LOW_FAR)
	if float(u.get("bare_shrub", 0.0)) > 0.0:
		var twigs: Array = [PlantGen.TWIG_A, PlantGen.TWIG_B]
		for i in 2:
			_add_small("shrub", "bush", PlantGen.bush(585 + i, _role(twig_mat, "near_small"), Color.WHITE, twigs, 1.2, i),
					PlantGen.bush(585 + i, _role(twig_mat, "far_low"), Color.WHITE, twigs, 1.2, i, 1), null, LOW_FAR)
	if float(u.get("thorn", 0.0)) > 0.0:
		var tm := leaf_mat.duplicate() as ShaderMaterial      # its canes and twigs are a red-brown, not a tree's grey
		tm.set_shader_parameter("wood_color", Vector3(0.2, 0.11, 0.09))
		var tc := (leaves[0] as Color).darkened(0.15)
		_add_small("thorn", "bush", PlantGen.thorn(590, _role(tm, "near_small"), tc), PlantGen.thorn(590, _role(tm, "far_low"), tc, 1), null, LOW_FAR)
	if float(u.get("log", 0.0)) > 0.0 or float(u.get("stump", 0.0)) > 0.0:
		# Deadwood: the trees' bark, moss on top where the rocks have moss, deep snow where there is snow.
		var dm := wood_mat.duplicate() as ShaderMaterial
		dm.set_shader_parameter("moss", float(biome.get("moss", 0.0)))
		dm.set_shader_parameter("snow", minf(snow * 2.0, 1.0))
		var dc := bark_col if not birch else Color(0.26, 0.21, 0.16)
		if float(u.get("log", 0.0)) > 0.0:
			# (logs and thorns lie low: they throw no shadow of their own; the contact shade grounds them)
			_add_small("log", "rock", PlantGen.fallen_log(600, _role(dm, "near_small"), dc), PlantGen.fallen_log(600, _role(dm, "far_low"), dc, 1), null, LOW_FAR)
		if float(u.get("stump", 0.0)) > 0.0:
			_add_small("stump", "rock", PlantGen.stump(610, _role(dm, "low"), dc), null, null, LOW_FAR)
	if float(u.get("stick", 0.0)) > 0.0:
		# Dead wood on the ground weathers paler than the bark it had.
		var wc := bark_col.lerp(Color(0.4, 0.36, 0.3), 0.6)
		var sm := twig_mat.duplicate() as ShaderMaterial
		sm.set_shader_parameter("wood_color", Vector3(wc.r, wc.g, wc.b) * 0.9)
		sm.set_shader_parameter("snow", minf(snow * 2.0, 1.0))
		_add_small("stick", "flat", PlantGen.dead_branch(620, _role(sm, "under_low"), wc), null, null, under_low_far())
	if float(u.get("litter", 0.0)) > 0.0:
		_add_small("litter", "flat", PlantGen.litter(630, low, u.get("litter_col", Color(0.3, 0.2, 0.1)), PlantGen.LITTER_A), null, null, under_low_far())


## Boulders in four forms (rounded, slab, jointed block, shard), each with its
## cheap version, and two small stones (the cheap shape, short range) for the
## scatter round a boulder, the trail's edge and stream beds.
func _build_rocks(rock_mat: ShaderMaterial, forms: int) -> void:
	var col: Color = biome.rock
	for i in forms:
		_add_small("rock", "rock", PlantGen.rock(700 + i, _role(rock_mat, "near_small"), col, i % 4), PlantGen.rock(700 + i, _role(rock_mat, "far_low"), col, i % 4, 1), _role(rock_mat, "shade_small"), LOW_FAR)
	_add_small("stone", "rock", PlantGen.rock(720, _role(rock_mat, "under_low"), col, 0, 1), null, null, under_low_far())


## A copy of a plant material for one level of detail ("near", "mid", "shade":
## a tree's three versions; "near_small", "far_small", "shade_small": a small
## plant's close-up, its cheap version and that version as shadow caster;
## "near_low", "far_low", "low": the same for low things, gone by LOW_FAR;
## "under": the undergrowth, one version, a short range, and "under_low" the lowest of it, shorter still;
## "small": one version out to SMALL_FAR).
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
			m.set_shader_parameter("lod_out", near_range())
			m.set_shader_parameter("lod_out_fade", NEAR_FADE)
			m.set_shader_parameter("far_end", 100000.0)
		"mid":
			m.set_shader_parameter("lod_in", near_range())
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
			m.set_shader_parameter("lod_in", near_range())
			m.set_shader_parameter("far_end", minf(tree_far, TREE_FAR))
		"shade_only":
			m.set_shader_parameter("far_end", 140.0)
		"picture":
			m.set_shader_parameter("lod_in", detail_range)
			m.set_shader_parameter("lod_in_fade", TREE_FADE)
			m.set_shader_parameter("far_end", tree_far)
			m.set_shader_parameter("far_z", tree_far_z)
		"under", "under_low":
			m.set_shader_parameter("far_end", under_far() if role == "under" else under_low_far())
			m.set_shader_parameter("far_fade", UNDER_FADE if role == "under" else UNDER_FADE * 0.7)
			m.set_shader_parameter("shade_own", 0.0)
		"near_small", "near_low":
			m.set_shader_parameter("lod_out", small_near())
			m.set_shader_parameter("lod_out_fade", NEAR_FADE)
			m.set_shader_parameter("far_end", 100000.0)
			m.set_shader_parameter("shade_own", 0.0)
		"far_small", "far_low":
			m.set_shader_parameter("lod_in", small_near())
			m.set_shader_parameter("far_end", SMALL_FAR if role == "far_small" else LOW_FAR)
			m.set_shader_parameter("far_fade", 40.0 if role == "far_small" else 30.0)
			m.set_shader_parameter("shade_own", 0.0)
		"shade_small":
			m.set_shader_parameter("lod_out", SHADE_SMALL)
			m.set_shader_parameter("lod_out_fade", SHADE_FADE)
			m.set_shader_parameter("far_end", 100000.0)
			m.set_shader_parameter("shade_own", 0.0)
		"low":
			m.set_shader_parameter("far_end", LOW_FAR)
			m.set_shader_parameter("far_fade", 30.0)
			m.set_shader_parameter("shade_own", 0.0)
		_:
			m.set_shader_parameter("far_end", SMALL_FAR)
			m.set_shader_parameter("far_fade", 40.0)
			m.set_shader_parameter("shade_own", 0.0)   # bushes put no crown in the canopy map (RealShade)


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


## The Sonoran desert's plants (they replace trees and bushes). The small ones
## are many and were the heaviest thing in any biome with one full version
## each out to 150 m: each now has a cheap version beyond SMALL_NEAR, which
## also casts its shadow, and one surface (ocotillo, barrel), and the lowest
## (barrel, prickly pear) end at LOW_FAR.
func _build_desert(bark_mat: ShaderMaterial, leaf_mat: ShaderMaterial, twig_mat: ShaderMaterial, rock_mat: ShaderMaterial) -> void:
	var skin := ShaderMaterial.new()
	skin.shader = load("res://scene/real/real_cactus.gdshader")
	var spines := skin.duplicate() as ShaderMaterial
	spines.set_shader_parameter("fuzz", 0.3)
	spines.set_shader_parameter("fuzz_color", Vector3(0.78, 0.72, 0.48))
	var old_leaf := ShaderMaterial.new()                 # ocotillo: whips, leaves and flower tips as solid blades
	old_leaf.shader = load("res://scene/real/real_foliage.gdshader")
	for i in 6:
		_add(PlantGen.saguaro(800 + i, _role(skin, "near")), "saguaro",
				PlantGen.saguaro(800 + i, _role(skin, "mid"), 1), PlantGen.saguaro(800 + i, _role(skin, "shade"), 1), Color(0.28, 0.35, 0.2))
	for i in 3:
		_add(PlantGen.palo_verde(850 + i, _role(bark_mat, "near"), _role(leaf_mat, "near")), "palo",
				PlantGen.palo_verde(850 + i, null, _role(leaf_mat, "mid"), 1), PlantGen.palo_verde(850 + i, null, _role(leaf_mat, "shade"), 2), Color(0.46, 0.52, 0.16))
	for i in 2:
		_add_small("bush", "bush", PlantGen.ocotillo(870 + i, _role(old_leaf, "near_small")), PlantGen.ocotillo(870 + i, _role(old_leaf, "far_small"), 1), _role(old_leaf, "shade_small"))
	for i in 2:
		_add_small("bush", "bush", PlantGen.cholla(880 + i, _role(spines, "near_small")), PlantGen.cholla(880 + i, _role(spines, "far_small"), 1), _role(spines, "shade_small"))
	for i in 2:
		_add_small("bush", "bush", PlantGen.prickly_pear(890 + i, _role(skin, "near_low")), PlantGen.prickly_pear(890 + i, _role(skin, "far_low"), 1), _role(skin, "shade_small"), LOW_FAR)
	for i in 2:
		_add_small("bush", "bush", PlantGen.barrel(900 + i, _role(skin, "near_low")), PlantGen.barrel(900 + i, _role(skin, "far_low"), 1), _role(skin, "shade_small"), LOW_FAR)
	# Creosote is the commonest by far: three of the eleven kinds, as it was five of sixteen.
	for i in 3:
		_add_small("bush", "bush", PlantGen.creosote(910 + i, _role(leaf_mat, "near_small")), PlantGen.creosote(910 + i, _role(leaf_mat, "far_small"), 1), _role(leaf_mat, "shade_small"))
	# Deadwood here is bleached grey and dry.
	var grey := bark_mat.duplicate() as ShaderMaterial
	var dry_twig := twig_mat.duplicate() as ShaderMaterial
	dry_twig.set_shader_parameter("wood_color", Vector3(0.42, 0.38, 0.32))
	var u: Dictionary = biome.get("under", {})
	var under := _role(leaf_mat, "under")
	if float(u.get("log", 0.0)) > 0.0:
		_add_small("log", "rock", PlantGen.fallen_log(600, _role(grey, "near_small"), Color(0.5, 0.46, 0.4)), PlantGen.fallen_log(600, _role(grey, "far_small"), Color(0.5, 0.46, 0.4), 1))
	if float(u.get("stick", 0.0)) > 0.0:
		_add_small("stick", "flat", PlantGen.dead_branch(620, _role(dry_twig, "under_low"), Color(0.5, 0.46, 0.4)), null, null, under_low_far())
	if float(u.get("seed", 0.0)) > 0.0:
		_add_small("seed", "flat", PlantGen.herb(550, under, [PlantGen.SEED_A], 0.7, 3, u.get("seed_col", Color(0.6, 0.52, 0.32)), 0.8, 0.75), null, null, under_far())
	if float(u.get("dry", 0.0)) > 0.0:
		for i in 2:
			_add_small("dry", "flat", PlantGen.herb(555 + i, under, [PlantGen.GRASS_A, PlantGen.GRASS_B], 0.4 + 0.15 * i, 4, u.get("dry_col", Color(0.6, 0.52, 0.32)), 1.0, 0.8), null, null, under_far())
	_build_rocks(rock_mat, 4)


## A tree variant, with its middle version, that shape again as shadow caster,
## and the colour behind its picture.
func _add(m: Mesh, kind: String, mid: Mesh = null, shade: Mesh = null, color := Color.BLACK) -> void:
	var i := meshes.size()
	meshes.append(m)
	mid_meshes[i] = mid
	shade_meshes[i] = shade
	picture_rows[i] = _bake_list.size()
	_bake_list.append({"mesh": mid, "color": color})
	kinds.append("tree")
	_trees.append(i)
	({"spruce": _spruce, "broad": _broad, "bare": _bare, "saguaro": _saguaro, "palo": _palo}[kind] as Array[int]).append(i)


## A small plant or stone variant, in `pool` (what scatter picks from). kind:
## how it meets the ground (see `kinds`). far: its cheap distant version, and
## shade_mat the material that version wears as shadow caster; end: where it is
## gone; casts: a plant of one version that throws a shadow near the trail.
func _add_small(pool: String, kind: String, m: Mesh, far: Mesh = null, shade_mat: Material = null, end := SMALL_FAR, casts := false) -> void:
	var i := meshes.size()
	meshes.append(m)
	kinds.append(kind)
	if not _pools.has(pool):
		_pools[pool] = [] as Array[int]
	(_pools[pool] as Array[int]).append(i)
	_ends[i] = end
	if far != null:
		far_meshes[i] = far
		_shade_mats[i] = shade_mat
	if casts:
		_casts[i] = true


## What to draw for a small plant variant in one band of a chunk (TerrainStreamer._flora_band):
## [{mesh, begin, end: metres from the eye, cast: a GeometryInstance3D shadow setting,
## material: an override or null}]. close: the band can come within reach of the rider.
func small_versions(mi: int, close: bool) -> Array:
	var end := float(_ends.get(mi, SMALL_FAR))
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not far_meshes.has(mi):
		return [{"mesh": meshes[mi], "begin": 0.0, "end": end, "material": null,
				"cast": GeometryInstance3D.SHADOW_CASTING_SETTING_ON if close and _casts.has(mi) else off}]
	var hand := small_near()
	var out := [{"mesh": far_meshes[mi], "begin": hand - NEAR_FADE * 0.5, "end": end, "cast": off, "material": null}]
	if close:
		out.append({"mesh": meshes[mi], "begin": 0.0, "end": hand + NEAR_FADE * 0.5, "cast": off, "material": null})
		if _shade_mats[mi] != null:
			# Its shadow comes from the cheap version: a fraction of the triangles in every shadow map.
			out.append({"mesh": far_meshes[mi], "begin": 0.0, "end": SHADE_SMALL + SHADE_FADE * 0.5, "material": _shade_mats[mi],
					"cast": GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY})
	return out


func _has(pool: String) -> bool:
	return _pools.has(pool)


func _pick(rng: RandomNumberGenerator, pool: String) -> int:
	var p: Array[int] = _pools[pool]
	return p[rng.randi() % p.size()]


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
	var near_trees := []           # the trees the undergrowth dresses: [x, z, scale, mesh index]
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
			if ad < UNDER_REACH - 4.0:
				near_trees.append([x, z, s, mi])
	# Woods out across the valley and up the far slopes, as far as the ground
	# goes: flat pictures out there, so real forest costs little. Broad noise
	# leaves meadows and clearings between the stands.
	if not _trees.is_empty() and tree_share > 0.0:
		for i in int(520 * float(RealQuality.get_value("forest_density")) * minf(tree_share * 2.0, 1.2)):
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(half_width, maxf(FAR_WOODS * float(RealQuality.get_value("forest_reach")), half_width + 20.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
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
	var ground := func(x: float, z: float) -> float:
		return float(height.call(x, z, t))
	var wet_at := func(x: float, z: float) -> float:
		return float(in_water.call(x, z, t)) if in_water.is_valid() else 9.0
	var own_at := func(x: float, z: float) -> Vector3:
		return own.call(x, z) as Vector3 if own.is_valid() else Vector3(1.0, 1.0, 0.0)
	# Bushes along the trail edges and in clearings.
	if _has("bush"):
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
			_put(out, _pick(rng, "bush"), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.05, z)), _tint(rng, 0.15))
	# Boulders, each with its scatter of stones.
	if _has("rock"):
		for i in int(9 * float(biome.rocks)):
			var z := z0 + rng.randf() * chunk_len
			var lat := rng.randf_range(-half_width, half_width)
			if absf(lat) < trail_clear + 0.6:
				continue
			var x := t.x_at(z) + lat
			if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
				continue
			if in_water.is_valid() and float(in_water.call(x, z, t)) < 0.7:
				continue
			_boulder(out, rng, x, z, absf(lat) - trail_clear, ground)
	# The undergrowth, within reach of the trail.
	var x_of := t
	var pick := func(r: RandomNumberGenerator) -> Vector2:
		var z := z0 + r.randf() * chunk_len
		return Vector2(x_of.x_at(z) + r.randf_range(-UNDER_REACH, UNDER_REACH), z)
	var ad_at := func(x: float, z: float) -> float:
		return absf(x - x_of.x_at(z))
	_undergrowth(out, rng, chunk_len * UNDER_REACH * 2.0, pick, ad_at, own_at, wet_at, ground, trail_clear, near_trees)
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
	var near_trees := []
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
			var mi := _pick_tree(rng, int(o.z))
			_put(out, mi, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, float(height.call(x, z)) - 0.1, z)), _tint(rng, 0.12))
			if ad < UNDER_REACH - 4.0:
				near_trees.append([x, z, s, mi])
	# Bushes and rocks, mostly near the trail.
	if _has("bush"):
		for i in int(area * 0.028 * float(biome.bush)):
			var x := x0 + rng.randf() * size
			var z := z0 + rng.randf() * size
			var ad := float(near.call(x, z))
			if ad < trail_clear + 1.2 or ad > 30.0 + rng.randf() * 60.0:
				continue
			if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
				continue
			var s := rng.randf_range(0.6, 1.4)
			_put(out, _pick(rng, "bush"), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, float(height.call(x, z)) - 0.05, z)), _tint(rng, 0.15))
	if _has("rock"):
		for i in int(area * 0.0027 * float(biome.rocks)):
			var x := x0 + rng.randf() * size
			var z := z0 + rng.randf() * size
			var ad := float(near.call(x, z))
			if ad < trail_clear + 0.6:
				continue
			if own.is_valid() and (own.call(x, z) as Vector3).x <= 0.0:
				continue
			_boulder(out, rng, x, z, ad - trail_clear, height)
	# The undergrowth. Both the distance to the trail and what grows where are
	# costly to ask of a route, so they are read off a coarse grid over the
	# square (and asked properly only close to the trail, or where the grid
	# shows water or another biome's ground nearby).
	const G := 8.0
	var n := int(ceil(size / G)) + 1
	var g_ad := PackedFloat32Array()
	var g_own := PackedVector3Array()
	g_ad.resize(n * n)
	var close := false
	for j in n:
		for i in n:
			g_ad[j * n + i] = float(near.call(x0 + float(i) * G, z0 + float(j) * G))
			close = close or g_ad[j * n + i] < UNDER_REACH + G
	if not close:
		return out
	g_own.resize(n * n)
	for j in n:
		for i in n:
			g_own[j * n + i] = own.call(x0 + float(i) * G, z0 + float(j) * G) as Vector3 if own.is_valid() else Vector3(1.0, 1.0, 0.0)
	var ad_at := func(x: float, z: float) -> float:
		var fx := clampf((x - x0) / G, 0.0, float(n) - 1.001)
		var fz := clampf((z - z0) / G, 0.0, float(n) - 1.001)
		var i := int(fx)
		var j := int(fz)
		var k := j * n + i
		var d := lerpf(lerpf(g_ad[k], g_ad[k + 1], fx - float(i)), lerpf(g_ad[k + n], g_ad[k + n + 1], fx - float(i)), fz - float(j))
		return float(near.call(x, z)) if d < G + 2.0 else d
	var own_at := func(x: float, z: float) -> Vector3:
		var i := clampi(int((x - x0) / G), 0, n - 2)
		var j := clampi(int((z - z0) / G), 0, n - 2)
		var k := j * n + i
		var o := g_own[k]
		if o.is_equal_approx(g_own[k + 1]) and o.is_equal_approx(g_own[k + n]) and o.is_equal_approx(g_own[k + n + 1]):
			return o
		return own.call(x, z) as Vector3
	var wet_at := func(_x: float, _z: float) -> float:
		return 9.0            # (own() already says no where a route's water lies)
	var pick := func(r: RandomNumberGenerator) -> Vector2:
		return Vector2(x0 + r.randf() * size, z0 + r.randf() * size)
	_undergrowth(out, rng, area, pick, ad_at, own_at, wet_at, height, trail_clear, near_trees)
	return out


## How wooded a spot is, 0 open ground .. 1 inside a stand: the noise the trees
## are clumped by, and what the land's owner says of it (a map ride's woods are 1).
func _woodiness(x: float, z: float, o: Vector3) -> float:
	if _trees.is_empty() or float(biome.trees) <= 0.0:
		return 0.0
	if o.y >= WOODS:
		return 1.0
	return smoothstep(0.25, 0.65, _clump.get_noise_2d(x, z) * 0.5 + 0.5) * minf(o.y, 1.0)


## How thick undergrowth stands by distance from the trail: full to about a
## dozen metres (where the rider sees it), thinning fast, none past UNDER_REACH.
static func _by_trail(ad: float) -> float:
	return (1.0 - 0.78 * smoothstep(9.0, 20.0, ad)) * (1.0 - smoothstep(UNDER_REACH - 8.0, UNDER_REACH, ad))


## A drift: where a kind of undergrowth gathers (each kind its own pattern), 0 none .. 1 its heart.
func _drift(kind: int, x: float, z: float, cover: float) -> float:
	var v := _patch.get_noise_2d(x + 311.0 * float(kind), z - 173.0 * float(kind)) * 0.5 + 0.5
	return smoothstep(1.0 - cover, 1.0 - cover + 0.18, v)


## A basis lying on the ground at (x, z): y along the ground's normal, turned by yaw.
static func _on_ground(ground: Callable, x: float, z: float, yaw: float) -> Basis:
	var h := float(ground.call(x, z))
	var up := Vector3(h - float(ground.call(x + 0.6, z)), 0.6, h - float(ground.call(x, z + 0.6))).normalized()
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var right := fwd.cross(up).normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()


## A boulder at (x, z), half sunk, and what lies round it: a few stones and
## now and then a second boulder leaning on the first. room: how far the trail's
## bank is (stones keep off it).
func _boulder(out: Dictionary, rng: RandomNumberGenerator, x: float, z: float, room: float, ground: Callable) -> void:
	var s := 0.3 + 1.5 * pow(rng.randf(), 2.2)
	var basis := Basis(Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized(), rng.randf() * TAU)
	var y := float(ground.call(x, z))
	_put(out, _pick(rng, "rock"), Transform3D(basis.scaled(Vector3(s, s * rng.randf_range(0.75, 1.1), s)), Vector3(x, y - s * 0.22, z)), _tint(rng, 0.1))
	var around := rng.randi_range(2, 4) + int(s * 3.0)
	for k in around:
		var a := rng.randf() * TAU
		var r := s * rng.randf_range(0.75, 2.2) + 0.15
		if r > room + 0.3:
			continue
		var sx := x + cos(a) * r
		var sz := z + sin(a) * r
		# Most are fist to head sized; one in six a small boulder of its own.
		var big := rng.randf() < 0.17
		var ss := s * rng.randf_range(0.3, 0.55) if big else rng.randf_range(0.06, 0.22) * (0.6 + 0.4 * s)
		# (stones lie nearly the right way up: the mesh's flat cut and dark baked underside belong on the ground)
		var sb := Basis(Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.9, 1.1), rng.randf_range(-0.35, 0.35)).normalized(), rng.randf() * TAU)
		var pool := "rock" if big and ss > 0.28 else "stone"
		if not _has(pool):
			continue
		_put(out, _pick(rng, pool), Transform3D(sb.scaled(Vector3(ss, ss * rng.randf_range(0.6, 1.0), ss)), Vector3(sx, float(ground.call(sx, sz)) - ss * 0.2, sz)), _tint(rng, 0.12))


## Worker thread: the undergrowth for one piece of ground of `area` square
## metres, placed with intent: ferns in drifts under and beside the stands of
## trees and at each trunk's foot, saplings and young spruces at the stands'
## edges, tall herbs and thorns along the verge and stream banks, low herbs
## breaking the lawn everywhere near the trail, logs and sticks by old trees,
## fallen leaves under crowns and (autumn) in the verge, stones at the trail's
## edge. Thick within about a dozen metres of the trail and thinning fast
## beyond (_by_trail); nothing tall on the trail's banks; clearings stay open.
## pick(rng) -> a random spot (x, z); ad_at(x, z) -> metres from the trail's
## middle; own_at(x, z) -> as scatter()'s own; wet_at(x, z) -> half widths from
## the water (big: none near); ground(x, z) -> height; clear: the trail's half
## width with its banks; trees: [x, z, scale, mesh index] of the trees near the trail.
func _undergrowth(out: Dictionary, rng: RandomNumberGenerator, area: float, pick: Callable, ad_at: Callable, own_at: Callable,
		wet_at: Callable, ground: Callable, clear: float, trees: Array) -> void:
	var u: Dictionary = biome.get("under", {})
	if u.is_empty():
		return
	var q := float(RealQuality.get_value("under_density"))
	var n := area * q
	# Ferns: drifts where trees stand, bracken at the stands' edges and ferns inside.
	if _has("fern"):
		for i in int(n * 0.6 * float(u.get("fern", 0.0))):
			var p: Vector2 = pick.call(rng)
			var drift := _drift(1, p.x, p.y, 0.6)
			if drift <= 0.0:
				continue
			var ad := float(ad_at.call(p.x, p.y))
			if ad < clear + 0.7 or ad > UNDER_REACH:
				continue
			var o: Vector3 = own_at.call(p.x, p.y)
			if o.x <= 0.0:
				continue
			var wood := _woodiness(p.x, p.y, o)
			if rng.randf() > drift * smoothstep(0.08, 0.4, wood) * _by_trail(ad) or float(wet_at.call(p.x, p.y)) < 1.15:
				continue
			var bracken := wood < 0.75 and rng.randf() < float(u.get("bracken", 0.35)) * (1.6 - wood)
			var s := rng.randf_range(0.7, 1.2) * (0.75 + 0.4 * drift)
			_put(out, _pick(rng, "bracken" if bracken else "fern"), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(p.x, float(ground.call(p.x, p.y)) - 0.03, p.y)), _tint(rng, 0.16))
	# Low leafy herbs: patches everywhere near the trail, thickest along its verge, so the grass is not a lawn.
	if _has("herb"):
		for i in int(n * 0.5 * float(u.get("herb", 0.0))):
			var p: Vector2 = pick.call(rng)
			var drift := _drift(2, p.x, p.y, 0.62)
			if drift <= 0.0:
				continue
			var ad := float(ad_at.call(p.x, p.y))
			if ad < clear + 0.25 or ad > UNDER_REACH:
				continue
			# (small things: past a dozen metres they cost more than they show)
			if rng.randf() > drift * _by_trail(ad) * (1.0 if ad < clear + 5.0 else 0.6) * (1.0 - 0.6 * smoothstep(10.0, 18.0, ad)):
				continue
			if (own_at.call(p.x, p.y) as Vector3).x <= 0.0 or float(wet_at.call(p.x, p.y)) < 1.1:
				continue
			var s := rng.randf_range(0.6, 1.3)
			_put(out, _pick(rng, "herb"), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, float(ground.call(p.x, p.y)), p.y)), _tint(rng, 0.14))
	# Tall herbs: cow parsley along the verge and the water, fireweed in drifts in the open, dry stalks where either stood.
	for kind: Array in [["umbel", 3, 0.45, 0.42], ["fireweed", 4, 0.34, 0.5], ["seed", 5, 0.5, 0.36], ["dry", 5, 0.6, 0.4]]:
		var pool: String = kind[0]
		if not _has(pool):
			continue
		for i in int(n * float(kind[3]) * float(u.get(pool, 0.0))):
			var p: Vector2 = pick.call(rng)
			var drift := _drift(int(kind[1]), p.x, p.y, float(kind[2]))
			if drift <= 0.0:
				continue
			var ad := float(ad_at.call(p.x, p.y))
			if ad < clear + 0.5 or ad > UNDER_REACH:
				continue
			var o: Vector3 = own_at.call(p.x, p.y)
			if o.x <= 0.0:
				continue
			var wet := float(wet_at.call(p.x, p.y))
			if wet < 1.12:
				continue
			var grow := drift * _by_trail(ad)
			if pool == "umbel" or pool == "seed":
				# The verge and the banks of the water first.
				grow *= maxf(1.0 - 0.75 * smoothstep(clear + 3.0, clear + 10.0, ad), 1.0 - smoothstep(1.4, 2.6, wet))
			if pool == "fireweed":
				grow *= 1.0 - 0.85 * _woodiness(p.x, p.y, o)
			if rng.randf() > grow:
				continue
			var s := rng.randf_range(0.7, 1.2) * (0.8 + 0.3 * drift)
			_put(out, _pick(rng, pool), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, float(ground.call(p.x, p.y)), p.y)), _tint(rng, 0.1))
	# Saplings and young spruces at the edges of the stands; shrubs there and in the open; thorns by the verge.
	for kind: Array in [["sapling", 0.06, 2.0], ["young", 0.06, 2.2], ["shrub", 0.018, 3.2], ["thorn", 0.02, 1.6]]:
		var pool: String = kind[0]
		if not _has(pool):
			continue
		for i in int(n * float(kind[1]) * float(u.get(pool, u.get("bare_shrub", 0.0)))):
			var p: Vector2 = pick.call(rng)
			var ad := float(ad_at.call(p.x, p.y))
			if ad < clear + float(kind[2]) or ad > UNDER_REACH:
				continue
			var o: Vector3 = own_at.call(p.x, p.y)
			if o.x <= 0.0:
				continue
			var wood := _woodiness(p.x, p.y, o)
			var edge := smoothstep(0.03, 0.25, wood) * (1.0 - 0.8 * smoothstep(0.5, 0.9, wood))
			var grow := edge
			if pool == "shrub":
				grow = 0.25 + 0.75 * edge
			elif pool == "thorn":
				grow = maxf(edge, 1.0 - smoothstep(clear + 2.0, clear + 7.0, ad)) * _drift(6, p.x, p.y, 0.6)
			elif pool == "young" and int(o.z) == 2:
				grow *= 0.2          # a broadleaf wood on the map has few
			elif pool == "sapling" and int(o.z) == 1:
				grow *= 0.2
			# These show from further off than the low undergrowth: they thin more slowly.
			if rng.randf() > grow * sqrt(_by_trail(ad)) or float(wet_at.call(p.x, p.y)) < 1.25:
				continue
			var s := rng.randf_range(0.65, 1.25)
			_put(out, _pick(rng, pool), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, float(ground.call(p.x, p.y)) - 0.05, p.y)), _tint(rng, 0.14))
	# Stumps and sticks in the woods; the odd log far from any marked tree.
	for kind: Array in [["stump", 0.006, 1.5], ["stick", 0.03, 1.2], ["log", 0.0015, 4.5]]:
		var pool: String = kind[0]
		if not _has(pool):
			continue
		# (a desert or a dead land has deadwood without woods)
		var needs_wood := not _trees.is_empty() and float(biome.trees) >= 0.4
		for i in int(n * float(kind[1]) * float(u.get(pool, 0.0))):
			var p: Vector2 = pick.call(rng)
			var ad := float(ad_at.call(p.x, p.y))
			if ad < clear + float(kind[2]) or ad > UNDER_REACH:
				continue
			var o: Vector3 = own_at.call(p.x, p.y)
			if o.x <= 0.0:
				continue
			var grow := sqrt(_by_trail(ad)) * (smoothstep(0.2, 0.6, _woodiness(p.x, p.y, o)) if needs_wood else 0.6)
			if rng.randf() > grow or float(wet_at.call(p.x, p.y)) < 1.2:
				continue
			_deadwood(out, rng, pool, p.x, p.y, ground)
	# At the foot of each tree near the trail: a skirt of ferns and herbs, fallen
	# leaves under a broadleaf's crown, a stick or two, and now and then the log
	# of a neighbour that came down.
	for tr: Array in trees:
		var tx := float(tr[0])
		var tz := float(tr[1])
		var ts := float(tr[2])
		var spruce := _spruce.has(int(tr[3]))
		var by := _by_trail(float(ad_at.call(tx, tz)))
		var dress := []          # [pool, count, nearest, furthest (metres from the trunk)]
		if _has("fern") and rng.randf() < 0.8 * float(u.get("fern", 0.0)) * by:
			dress.append(["fern", rng.randi_range(2, 5), 0.7, 2.4])
		if _has("herb") and rng.randf() < 0.9 * by:
			dress.append(["herb", rng.randi_range(2, 4), 0.5, 1.8])
		if _has("seed") and not _has("fern") and rng.randf() < 0.4 * by:
			dress.append(["seed", rng.randi_range(1, 3), 0.5, 1.6])
		if _has("litter") and not spruce and rng.randf() < 1.2 * float(u.get("litter", 0.0)) * by:
			dress.append(["litter", rng.randi_range(2, 4), 0.3, 3.2 * ts])
		if _has("stick") and rng.randf() < 0.3 * float(u.get("stick", 0.0)) * by:
			dress.append(["stick", 1, 1.0, 3.0])
		if _has("log") and ts > 1.0 and rng.randf() < 0.14 * float(u.get("log", 0.0)):
			dress.append(["log", 1, 2.0, 4.0])
		for d: Array in dress:
			var pool: String = d[0]
			for k in int(d[1]):
				var a := rng.randf() * TAU
				var r := rng.randf_range(float(d[2]), float(d[3]))
				var x := tx + cos(a) * r
				var z := tz + sin(a) * r
				var need := clear + (4.5 if pool == "log" else (0.2 if pool == "litter" else 0.7))
				if float(ad_at.call(x, z)) < need or (own_at.call(x, z) as Vector3).x <= 0.0 or float(wet_at.call(x, z)) < 1.15:
					continue
				if pool == "log" or pool == "stick":
					_deadwood(out, rng, pool, x, z, ground)
				elif pool == "litter":
					var s := rng.randf_range(1.1, 2.3)
					_put(out, _pick(rng, pool), Transform3D(_on_ground(ground, x, z, rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), Vector3(x, float(ground.call(x, z)), z)), _tint(rng, 0.18))
				else:
					var s := rng.randf_range(0.6, 1.1)
					_put(out, _pick(rng, pool), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, float(ground.call(x, z)) - 0.02, z)), _tint(rng, 0.15))
	# Along the trail's edge: a ragged fringe of taller herbs and grasses gone to
	# seed (a verge nobody mows), stones on its banks in loose groups, and in
	# autumn the leaves that blew into it.
	# [pool, candidates a square metre, drift pattern, drift cover, nearest, furthest (metres from the trail's middle), the biome's share]
	for kind: Array in [["herb", 0.5, 9, 0.8, clear + 0.25, clear + 2.8, "herb"], ["seed", 0.3, 10, 0.65, clear + 0.4, clear + 3.2, "seed"],
			["stone", 0.3, 7, 0.5, 1.05, 3.4, "stones"], ["litter", 0.5, 8, 0.7, 0.85, 4.5, "verge_litter"]]:
		var pool: String = kind[0]
		var share := float(u.get(kind[6], 0.0))
		if not _has(pool) or share <= 0.0:
			continue
		for i in int(n * float(kind[1]) * share):
			var p: Vector2 = pick.call(rng)
			var ad := float(ad_at.call(p.x, p.y))
			if ad < float(kind[4]) or ad > float(kind[5]):
				continue
			if rng.randf() > _drift(int(kind[2]), p.x * 3.0, p.y * 3.0, float(kind[3])) * 1.6 or (own_at.call(p.x, p.y) as Vector3).x <= 0.0:
				continue
			if pool == "stone":
				var s := rng.randf_range(0.035, 0.11) * (1.0 + 2.0 * pow(rng.randf(), 5.0))
				var sb := Basis(Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.9, 1.1), rng.randf_range(-0.35, 0.35)).normalized(), rng.randf() * TAU)
				_put(out, _pick(rng, pool), Transform3D(sb.scaled(Vector3(s, s * rng.randf_range(0.5, 0.9), s)), Vector3(p.x, float(ground.call(p.x, p.y)) - s * 0.15, p.y)), _tint(rng, 0.14))
			elif pool == "litter":
				var s := rng.randf_range(0.8, 1.7)
				_put(out, _pick(rng, pool), Transform3D(_on_ground(ground, p.x, p.y, rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), Vector3(p.x, float(ground.call(p.x, p.y)), p.y)), _tint(rng, 0.18))
			elif float(wet_at.call(p.x, p.y)) > 1.1:
				var s := rng.randf_range(0.8, 1.35)
				_put(out, _pick(rng, pool), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, float(ground.call(p.x, p.y)), p.y)), _tint(rng, 0.14))


## A log, stump or stick at (x, z). Logs are built standing (PlantGen.fallen_log)
## and laid along the ground here, a quarter sunk in.
func _deadwood(out: Dictionary, rng: RandomNumberGenerator, pool: String, x: float, z: float, ground: Callable) -> void:
	var y := float(ground.call(x, z))
	var yaw := rng.randf() * TAU
	if pool == "stump":
		var s := rng.randf_range(0.7, 1.3)
		_put(out, _pick(rng, pool), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, y, z)), _tint(rng, 0.12))
		return
	var b := _on_ground(ground, x, z, yaw)
	if pool == "stick":
		var s := rng.randf_range(0.7, 1.2)
		_put(out, _pick(rng, pool), Transform3D(b.scaled(Vector3.ONE * s), Vector3(x, y, z)), _tint(rng, 0.12))
		return
	var s := rng.randf_range(0.75, 1.15)
	# The log's own up (its length) lies along the ground; its roll does not matter.
	var lying := Basis(b.y, b.x, b.z * -1.0)
	_put(out, _pick(rng, pool), Transform3D(lying.scaled(Vector3.ONE * s), Vector3(x, y + 0.13 * s, z)), _tint(rng, 0.12))


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


## A boulder at pos (its middle) for TerrainStreamer's streams, and a stone or two against it.
func add_rock(out: Dictionary, pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	if not _has("rock"):
		return
	var basis := Basis(Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), rng.randf() * TAU)
	_put(out, _pick(rng, "rock"), Transform3D(basis.scaled(Vector3(size, size * rng.randf_range(0.85, 1.25), size)), pos), _tint(rng, 0.1))
	if not _has("stone"):
		return
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var ss := size * rng.randf_range(0.18, 0.4)
		var sb := Basis(Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.9, 1.1), rng.randf_range(-0.35, 0.35)).normalized(), rng.randf() * TAU)
		# Against the boulder's foot, a little lower: the stream's bed falls away from it.
		_put(out, _pick(rng, "stone"), Transform3D(sb.scaled(Vector3.ONE * ss), pos + Vector3(cos(a), 0.0, sin(a)) * size * rng.randf_range(0.8, 1.15) - Vector3.UP * size * 0.3), _tint(rng, 0.12))


static func _put(out: Dictionary, mi: int, xf: Transform3D, tint: Color) -> void:
	if not out.has(mi):
		out[mi] = [[] as Array[Transform3D], [] as Array[Color]]
	out[mi][0].append(xf)
	out[mi][1].append(tint)
