class_name Palette
extends RefCounted
## The winter palette, sampled from the reference video: soft blues and pinks,
## deep teal pines, a red-and-blue rider. Both the mesh builders (vertex colours)
## and the post-process (quantization) draw from this list so the image stays
## inside it.

const SKY_TOP := Color("7f9fd8")
const SKY_HORIZON := Color("edc9d8")
const FOG := Color("cfc5e3")

const SNOW := Color("f4f1f7")
const SNOW_SHADE := Color("cdd6ec")
const SNOW_SHADOW := Color("9fb0d8")
const TRAIL := Color("bfb0d2")
const TRAIL_DARK := Color("a493bd")
const ROCK := Color("6f7a95")
const ROCK_DARK := Color("4d556e")

const MOUNTAIN_FAR := Color("dcb7cc")
const MOUNTAIN_MID := Color("b491bb")
const MOUNTAIN_NEAR := Color("8a93c6")

const PINE := Color("2b4f5e")
const PINE_DARK := Color("1f3a46")
const PINE_SNOW := Color("e9eff8")
const TRUNK := Color("4a3a3a")
const BRANCH := Color("5c4638")
const BERRY := Color("c8323a")

const RIDER_RED := Color("c8323a")
const RIDER_BLUE := Color("2b4a9a")
const RIDER_SKIN := Color("e0b090")
const HELMET := Color("23232e")
const BIKE := Color("1d2333")
const TIRE := Color("2a2a33")

static func list() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in [SKY_TOP, SKY_HORIZON, FOG, SNOW, SNOW_SHADE, SNOW_SHADOW, TRAIL, TRAIL_DARK, ROCK, ROCK_DARK,
			MOUNTAIN_FAR, MOUNTAIN_MID, MOUNTAIN_NEAR, PINE, PINE_DARK, PINE_SNOW, TRUNK, BRANCH, BERRY,
			RIDER_RED, RIDER_BLUE, RIDER_SKIN, HELMET, BIKE, TIRE,
			Color("f8dfe6"), Color("5d6fa8"), Color("e7a4b4")]:
		out.append(Vector3(c.r, c.g, c.b))
	return out
