class_name WorkoutSegment
extends RefCounted
## One block of a workout: a span of time with a power target that is constant
## or ramps linearly. Power values are fractions of FTP.

enum Kind { WARMUP, STEADY, INTERVAL_ON, INTERVAL_OFF, RAMP, COOLDOWN, FREE_RIDE, MAX_EFFORT }

var kind: Kind = Kind.STEADY
var duration: float = 0.0        ## seconds
var power_low: float = 0.0       ## fraction of FTP at segment start
var power_high: float = 0.0      ## fraction of FTP at segment end
var cadence: int = 0             ## target rpm, 0 = none
var rep: int = 0                 ## 1-based, intervals only
var rep_count: int = 0


func has_target() -> bool:
	return kind != Kind.FREE_RIDE and kind != Kind.MAX_EFFORT


func is_ramp() -> bool:
	return not is_equal_approx(power_low, power_high)


func power_at(t: float) -> float:
	if duration <= 0.0:
		return power_low
	return lerpf(power_low, power_high, clampf(t / duration, 0.0, 1.0))


func peak() -> float:
	return maxf(power_low, power_high)


func label() -> String:
	match kind:
		Kind.WARMUP: return "Warm up"
		Kind.COOLDOWN: return "Cool down"
		Kind.STEADY: return "Steady"
		Kind.RAMP: return "Ramp"
		Kind.INTERVAL_ON: return "Rep %d of %d" % [rep, rep_count]
		Kind.INTERVAL_OFF: return "Recovery %d of %d" % [rep, rep_count]
		Kind.FREE_RIDE: return "Free ride"
		Kind.MAX_EFFORT: return "Max effort"
	return "Segment"
