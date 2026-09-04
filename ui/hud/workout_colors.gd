class_name WorkoutColors
extends RefCounted
## The one place workout effort colours live (see Design.md, "Workout zones").
## The plan graph, the ride trace, the block rows in the HUD and the sheets all
## read these, so refining the palette later is a change here only.

const RECOVERY := Color("174c8b")     # below 55 % FTP
const ENDURANCE := Color("01b5cc")    # 55-75 %  (Teal 400)
const TEMPO := Color("feb801")        # 76-89 %  (Yellow 400)
const THRESHOLD := Color("ef6a01")    # 90-104 % (Orange 500)
const VO2 := Color("dc352d")          # 105 % and up (Red 500)
const FREE := Color("6b7a8c")         # free ride, max effort: no target
const HR := Color("ff5c7a")           # heart-rate trace
const POWER := Color("f4f5f5")        # the rider's actual power line (Ice 100)
const GLOW := Color("ffffff")         # the marker riding the groove
const DONE_ALPHA := 0.45              # blocks already ridden

const ENDURANCE_FROM := 0.55
const TEMPO_FROM := 0.76
const THRESHOLD_FROM := 0.90
const VO2_FROM := 1.05


## Colour for a target expressed as a fraction of FTP.
static func for_fraction(f: float, has_target := true) -> Color:
	if not has_target:
		return FREE
	if f >= VO2_FROM:
		return VO2
	if f >= THRESHOLD_FROM:
		return THRESHOLD
	if f >= TEMPO_FROM:
		return TEMPO
	if f >= ENDURANCE_FROM:
		return ENDURANCE
	return RECOVERY


static func for_segment(s: WorkoutSegment) -> Color:
	return for_fraction(s.peak(), s.has_target())


static func zone_name(f: float) -> String:
	if f >= VO2_FROM:
		return "VO2"
	if f >= THRESHOLD_FROM:
		return "Threshold"
	if f >= TEMPO_FROM:
		return "Tempo"
	if f >= ENDURANCE_FROM:
		return "Endurance"
	return "Recovery"


## Row background: the panel colour tinted toward the effort colour.
static func row_background(base: Color, effort: Color) -> Color:
	var c := base.lerp(effort, 0.42)
	c.a = maxf(base.a, 0.75)
	return c
