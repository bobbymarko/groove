class_name RealQuality
extends RefCounted
## The realistic look's quality tiers (R15, R43) and the render-scale governor's
## rule. One place says how much each tier draws; the systems read it when the
## ride's scene is built (so a change of tier shows from the next ride).
## High is the full scene; Medium and Low thin the grass and the far forest,
## shorten the shadows and drop the costliest effects, to hold 60 fps on a
## smaller Apple GPU (a base M1 or M2 has roughly a quarter of an M4 Pro's).

const TIERS := ["low", "medium", "high"]

## Every number a tier sets.
##  scale_max      ceiling for the automatic render scale (1.0 = native)
##  range_mult     tree close-up and middle ranges (RealFlora.near_range, detail range)
##  forest_density share of the far woods that are planted (the strip and map rides)
##  forest_reach   share of RealFlora.FAR_WOODS the far woods reach out to
##  grass_pitch    tuft slot spacing multiplier (1.22 leaves two thirds of the tufts)
##  grass_reach    multiplier on where the middle and far grass rings end
##  grass_rings    how many of the grass rings are made (3 = all)
##  under_density  share of the undergrowth that is planted (ferns, herbs, saplings, deadwood, stones)
##  under_reach    multiplier on how far off the low undergrowth is drawn (RealFlora.UNDER_FAR)
##  shadow_splits  sun shadow cascades (Godot has 2 or 4); shadow_dist their reach in metres; shadow_atlas map size
##  split_1/2/3    cascade boundaries as shares of shadow_dist
##  ssao, vfog, ssr  ambient occlusion, volumetric fog, wet-ground reflections
##  cloud_steps    raymarch steps per cloud ray
const TABLE := {
	"low": {
		"scale_max": 0.5, "range_mult": 0.7, "forest_density": 0.5, "forest_reach": 0.7,
		"grass_pitch": 1.25, "grass_reach": 1.25, "grass_rings": 2,
		"under_density": 0.4, "under_reach": 0.7,
		"shadow_splits": 2, "shadow_dist": 70.0, "shadow_atlas": 2048,
		"split_1": 0.2, "split_2": 0.5, "split_3": 0.8,
		"ssao": false, "vfog": false, "ssr": false, "cloud_steps": 32,
	},
	"medium": {
		"scale_max": 0.59, "range_mult": 0.85, "forest_density": 0.67, "forest_reach": 0.85,
		"grass_pitch": 1.22, "grass_reach": 0.85, "grass_rings": 3,
		"under_density": 0.7, "under_reach": 0.85,
		"shadow_splits": 4, "shadow_dist": 110.0, "shadow_atlas": 4096,
		"split_1": 0.07, "split_2": 0.2, "split_3": 0.5,
		"ssao": true, "vfog": true, "ssr": true, "cloud_steps": 48,
	},
	"high": {
		"scale_max": 0.67, "range_mult": 1.0, "forest_density": 1.0, "forest_reach": 1.0,
		"grass_pitch": 1.0, "grass_reach": 1.0, "grass_rings": 3,
		"under_density": 1.0, "under_reach": 1.0,
		"shadow_splits": 4, "shadow_dist": 140.0, "shadow_atlas": 4096,
		"split_1": 0.06, "split_2": 0.18, "split_3": 0.45,
		"ssao": true, "vfog": true, "ssr": true, "cloud_steps": 64,
	},
}

## The tier the ride being built uses (RideScene sets it before the world is made).
static var tier := "high"

# --- the automatic render scale ---------------------------------------------------
## The only trustworthy signal on this renderer is the frame time itself (the
## viewport's GPU timer reads 0 under Metal). A vsynced frame time cannot go
## below the display's refresh interval, so on a 60 Hz display headroom is
## invisible: the governor then probes (tries one step up now and then) and backs
## off exponentially when a probe fails, which is what stops it flip-flopping.
const TARGET_MS := 16.7            ## 60 fps
const DOWN_MS := 17.7              ## smoothed time above this: a step down (target x 1.06)
const PINNED_MS := 17.2            ## at or under this (target x 1.03) the frame rate is holding
const UP_MS := 12.5                ## under this for UP_HOLD seconds: headroom is visible (fast displays), a step up
const UP_HOLD := 4.0
const STEP := 0.05
const SCALE_MIN := 0.4
const MIN_GAP := 3.0               ## seconds between changes (a change reallocates buffers and hitches)
const WARMUP := 5.0                ## no changes in a ride's first seconds (everything is still loading)
const PROBE_WAIT := 20.0           ## calm seconds before a probe step up; doubled after a failed probe
const PROBE_WAIT_MAX := 300.0
const PROBE_WINDOW := 6.0          ## a probe that has not gone over budget by now has held


static func normalize(id: String) -> String:
	return id if TABLE.has(id) else "high"


static func set_tier(id: String) -> void:
	tier = normalize(id)


static func get_value(key: String) -> Variant:
	return (TABLE[tier] as Dictionary)[key]


static func value_for(id: String, key: String) -> Variant:
	return (TABLE[normalize(id)] as Dictionary)[key]


static func scale_max() -> float:
	return float(get_value("scale_max"))


## The default tier for a GPU name (first run): Apple M-series Pro, Max or Ultra
## get High; everything else (base M-series, unknown, other makers) gets Medium.
static func default_for_gpu(gpu_name: String) -> String:
	var n := gpu_name.to_lower()
	if n.contains("apple m") and (n.contains("pro") or n.contains("max") or n.contains("ultra")):
		return "high"
	return "medium"


## The grass rings for this tier, from RealGrass.RINGS (copies; the constant is not touched).
static func grass_rings(base: Array) -> Array:
	var out: Array = []
	var n := int(get_value("grass_rings"))
	var pitch := float(get_value("grass_pitch"))
	var reach := float(get_value("grass_reach"))
	for r in mini(n, base.size()):
		var ring: Dictionary = (base[r] as Dictionary).duplicate()
		ring["pitch"] = float(ring.pitch) * pitch
		if r >= 1:
			ring["out"] = float(ring.out) * reach
		out.append(ring)
	return out


## A fresh governor state (a Dictionary, so the rule below stays a pure function of it).
## scale: current render scale; since_change: seconds since the last change;
## calm: seconds the frame rate has been holding; fast: seconds under UP_MS;
## wait: calm seconds the next probe needs; probing: a probe step is on trial;
## probe_t: seconds since the probe.
static func new_state(scale: float) -> Dictionary:
	return {"scale": scale, "since_change": 0.0, "calm": 0.0, "fast": 0.0,
			"wait": PROBE_WAIT, "probing": false, "probe_t": 0.0}


## The governor's rule, pure: `st` (see new_state) advanced by `dt` seconds with
## the smoothed frame time `avg_ms`; returns the new state (its "scale" is the
## render scale to use). Down a step over DOWN_MS; up a step when headroom shows
## (UP_MS for UP_HOLD seconds, and the step predicted to fit); otherwise up one
## probe step after `wait` calm seconds, undone (and `wait` doubled) if the
## frame time goes over budget within PROBE_WINDOW. Never within MIN_GAP of the
## last change; always inside [SCALE_MIN, ceiling] (a tier change clamps at once).
static func govern(st: Dictionary, avg_ms: float, dt: float, ceiling: float) -> Dictionary:
	var o := st.duplicate()
	var scale := float(o.scale)
	var top := maxf(ceiling, SCALE_MIN)
	var clamped := clampf(scale, SCALE_MIN, top)
	if not is_equal_approx(clamped, scale):
		return _changed(o, clamped, false)
	o.since_change = float(o.since_change) + dt
	o.fast = float(o.fast) + dt if avg_ms < UP_MS else 0.0
	if avg_ms <= PINNED_MS:
		o.calm = float(o.calm) + dt
	elif avg_ms > DOWN_MS:
		o.calm = 0.0
	if o.probing:
		o.probe_t = float(o.probe_t) + dt
	if float(o.since_change) < MIN_GAP:
		return o
	if avg_ms > DOWN_MS and scale > SCALE_MIN + 0.001:
		var failed: bool = o.probing
		o = _changed(o, maxf(snappedf(scale - STEP, 0.01), SCALE_MIN), false)
		if failed:
			o.wait = minf(float(st.wait) * 2.0, PROBE_WAIT_MAX)
		return o
	if o.probing and float(o.probe_t) >= PROBE_WINDOW:
		o.probing = false          # the probe held: climbing may go on at the short wait
		o.wait = PROBE_WAIT
	if scale < top - 0.001:
		var up := minf(snappedf(scale + STEP, 0.01), top)
		if float(o.fast) >= UP_HOLD:
			# Pixels grow with the square of the scale; only part of the frame follows them.
			var predicted := avg_ms * (1.0 + 0.6 * ((up * up) / (scale * scale) - 1.0))
			if predicted < 15.0:
				return _changed(o, up, false)
		elif not o.probing and float(o.calm) >= float(o.wait):
			return _changed(o, up, true)
	return o


static func _changed(o: Dictionary, scale: float, probe: bool) -> Dictionary:
	o.scale = scale
	o.since_change = 0.0
	o.calm = 0.0
	o.fast = 0.0
	o.probing = probe
	o.probe_t = 0.0
	return o
