class_name Palette
extends RefCounted
## The scene palette. Defaults are winter, sampled from the reference video:
## soft blues and pinks, deep teal pines, a red-and-blue rider. A ScenePreset
## overwrites these before a scene is built (apply()); the mesh builders
## (vertex colours) and the post-process (quantization) both read them, so the
## image stays inside the palette. SNOW_* double as the ground colours in
## other seasons.

static var SKY_TOP := Color("7f9fd8")
static var SKY_HORIZON := Color("edc9d8")
static var FOG := Color("cfc5e3")

static var SNOW := Color("f4f1f7")
static var SNOW_MID := Color("e4e2ee")
static var SNOW_SHADE := Color("cdd6ec")
static var SNOW_SHADOW := Color("8a9dcc")
static var SNOW_BRIGHT := Color("fbfaff")
static var TRAIL := Color("d6dbe8")        # packed snow, a shade below fresh snow
static var TRAIL_DARK := Color("bfc7da")   # the worn centre of the groove
static var ROCK := Color("6f7a95")
static var ROCK_DARK := Color("4d556e")

static var MOUNTAIN_FAR := Color("e3c4d6")
static var MOUNTAIN_FAR2 := Color("d0b3cf")
static var MOUNTAIN_MID := Color("b89ac4")
static var MOUNTAIN_MID2 := Color("9d9cc8")
static var MOUNTAIN_NEAR := Color("8391c2")
static var SKY_MID := Color("b7b5dc")
static var SKY_LOW := Color("d6bfd9")

static var PINE := Color("34667a")
static var PINE_LIGHT := Color("62a0ad")
static var PINE_DARK := Color("1d3d4a")
static var PINE_SNOW := Color("e9eff8")
static var TRUNK := Color("4a3a3a")
static var BRANCH := Color("5c4638")
static var BERRY := Color("c8323a")

static var RIDER_RED := Color("c8323a")
static var RIDER_BLUE := Color("2b4a9a")
static var RIDER_SKIN := Color("e0b090")
static var HELMET := Color("23232e")
static var BIKE := Color("1d2333")
static var TIRE := Color("2a2a33")
static var MOUNTAIN_SNOW := Color("f4eff6")   # snow line on the backdrop ridges
static var FLOWER := Color("e7a4b4")
static var FLOWER_DARK := Color("b0407a")

static var preset_id := "winter"
static var _defaults: Dictionary = {}

const NAMES := ["SKY_TOP", "SKY_HORIZON", "FOG", "SNOW", "SNOW_MID", "SNOW_SHADE", "SNOW_SHADOW", "SNOW_BRIGHT", "TRAIL", "TRAIL_DARK", "ROCK", "ROCK_DARK", "MOUNTAIN_FAR", "MOUNTAIN_FAR2", "MOUNTAIN_MID", "MOUNTAIN_MID2", "MOUNTAIN_NEAR", "SKY_MID", "SKY_LOW", "PINE", "PINE_LIGHT", "PINE_DARK", "PINE_SNOW", "TRUNK", "BRANCH", "BERRY", "RIDER_RED", "RIDER_BLUE", "RIDER_SKIN", "HELMET", "BIKE", "TIRE", "MOUNTAIN_SNOW", "FLOWER", "FLOWER_DARK"]


## Recolour the palette for a ScenePreset (colours it does not name fall back to winter).
static func apply(id: String) -> void:
	if _defaults.is_empty():
		for n in NAMES:
			_defaults[n] = get_color(n)
	var colors: Dictionary = ScenePreset.get_preset(id).colors
	for n in NAMES:
		set_color(n, Color(str(colors[n])) if colors.has(n) else _defaults[n])
	preset_id = id


static func get_color(n: String) -> Color:
	match n:
		"SKY_TOP": return SKY_TOP
		"SKY_HORIZON": return SKY_HORIZON
		"FOG": return FOG
		"SNOW": return SNOW
		"SNOW_MID": return SNOW_MID
		"SNOW_SHADE": return SNOW_SHADE
		"SNOW_SHADOW": return SNOW_SHADOW
		"SNOW_BRIGHT": return SNOW_BRIGHT
		"TRAIL": return TRAIL
		"TRAIL_DARK": return TRAIL_DARK
		"ROCK": return ROCK
		"ROCK_DARK": return ROCK_DARK
		"MOUNTAIN_FAR": return MOUNTAIN_FAR
		"MOUNTAIN_FAR2": return MOUNTAIN_FAR2
		"MOUNTAIN_MID": return MOUNTAIN_MID
		"MOUNTAIN_MID2": return MOUNTAIN_MID2
		"MOUNTAIN_NEAR": return MOUNTAIN_NEAR
		"SKY_MID": return SKY_MID
		"SKY_LOW": return SKY_LOW
		"PINE": return PINE
		"PINE_LIGHT": return PINE_LIGHT
		"PINE_DARK": return PINE_DARK
		"PINE_SNOW": return PINE_SNOW
		"TRUNK": return TRUNK
		"BRANCH": return BRANCH
		"BERRY": return BERRY
		"RIDER_RED": return RIDER_RED
		"RIDER_BLUE": return RIDER_BLUE
		"RIDER_SKIN": return RIDER_SKIN
		"HELMET": return HELMET
		"BIKE": return BIKE
		"TIRE": return TIRE
		"MOUNTAIN_SNOW": return MOUNTAIN_SNOW
		"FLOWER": return FLOWER
		"FLOWER_DARK": return FLOWER_DARK
	return Color.MAGENTA


static func set_color(n: String, c: Color) -> void:
	match n:
		"SKY_TOP": SKY_TOP = c
		"SKY_HORIZON": SKY_HORIZON = c
		"FOG": FOG = c
		"SNOW": SNOW = c
		"SNOW_MID": SNOW_MID = c
		"SNOW_SHADE": SNOW_SHADE = c
		"SNOW_SHADOW": SNOW_SHADOW = c
		"SNOW_BRIGHT": SNOW_BRIGHT = c
		"TRAIL": TRAIL = c
		"TRAIL_DARK": TRAIL_DARK = c
		"ROCK": ROCK = c
		"ROCK_DARK": ROCK_DARK = c
		"MOUNTAIN_FAR": MOUNTAIN_FAR = c
		"MOUNTAIN_FAR2": MOUNTAIN_FAR2 = c
		"MOUNTAIN_MID": MOUNTAIN_MID = c
		"MOUNTAIN_MID2": MOUNTAIN_MID2 = c
		"MOUNTAIN_NEAR": MOUNTAIN_NEAR = c
		"SKY_MID": SKY_MID = c
		"SKY_LOW": SKY_LOW = c
		"PINE": PINE = c
		"PINE_LIGHT": PINE_LIGHT = c
		"PINE_DARK": PINE_DARK = c
		"PINE_SNOW": PINE_SNOW = c
		"TRUNK": TRUNK = c
		"BRANCH": BRANCH = c
		"BERRY": BERRY = c
		"RIDER_RED": RIDER_RED = c
		"RIDER_BLUE": RIDER_BLUE = c
		"RIDER_SKIN": RIDER_SKIN = c
		"HELMET": HELMET = c
		"BIKE": BIKE = c
		"TIRE": TIRE = c
		"MOUNTAIN_SNOW": MOUNTAIN_SNOW = c
		"FLOWER": FLOWER = c
		"FLOWER_DARK": FLOWER_DARK = c


static func list() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in [SKY_TOP, SKY_MID, SKY_LOW, SKY_HORIZON, FOG, SNOW_BRIGHT, SNOW, SNOW_MID, SNOW_SHADE, SNOW_SHADOW, TRAIL, TRAIL_DARK, ROCK, ROCK_DARK,
			MOUNTAIN_FAR, MOUNTAIN_FAR2, MOUNTAIN_MID, MOUNTAIN_MID2, MOUNTAIN_NEAR, PINE, PINE_LIGHT, PINE_DARK, PINE_SNOW, TRUNK, BRANCH, BERRY,
			RIDER_RED, RIDER_BLUE, RIDER_SKIN, HELMET, BIKE, TIRE, MOUNTAIN_SNOW, FLOWER, FLOWER_DARK,
			Color("f8dfe6"), Color("5d6fa8")]:
		out.append(Vector3(c.r, c.g, c.b))
	return out
