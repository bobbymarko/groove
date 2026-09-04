class_name WorkoutColors
extends RefCounted
## The one place workout effort colours live. The plan graph, the ride trace,
## the block rows in the HUD and the sheets all read these, so refining the
## palette later is a change here only.

const EASY := Color(0.35, 0.55, 0.85)     # endurance and recovery, below 76 % FTP
const TEMPO := Color(0.62, 0.55, 0.72)    # tempo and sweet spot, up to 95 %
const HARD := Color(0.95, 0.45, 0.35)     # threshold and above
const FREE := Color(0.5, 0.5, 0.5)        # free ride, max effort: no target
const HR := Color(1.0, 0.42, 0.5)         # heart-rate trace
const DONE_ALPHA := 0.45                  # blocks already ridden

const TEMPO_FROM := 0.76
const HARD_FROM := 0.95


## Colour for a target expressed as a fraction of FTP.
static func for_fraction(f: float, has_target := true) -> Color:
	if not has_target:
		return FREE
	if f >= HARD_FROM:
		return HARD
	if f >= TEMPO_FROM:
		return TEMPO
	return EASY


static func for_segment(s: WorkoutSegment) -> Color:
	return for_fraction(s.peak(), s.has_target())


## Row background: the panel colour tinted toward the effort colour.
static func row_background(base: Color, effort: Color) -> Color:
	var c := base.lerp(effort, 0.42)
	c.a = maxf(base.a, 0.75)
	return c
