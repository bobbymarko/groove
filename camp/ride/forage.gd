class_name Forage
extends RefCounted
## The rules of foraging, apart from any visuals: are you in the band right
## now, did you earn a find, what is the basket worth.

const BAND_LOW := 0.90
const BAND_HIGH := 1.15
const SMOOTH_SECONDS := 3
const FREE_RIDE_FLOOR := 0.40    ## fraction of FTP that counts as riding in a meadow
const CRITTER_AVERAGE := 0.95    ## interval average needed to catch the critter
const VALUES := {"berry": 1, "flower": 4, "critter": 20, "honey": 3}

var ftp := 200
var basket := {"berry": 0, "flower": 0, "critter": 0, "honey": 0}
var _power: Array[float] = []    # last few one-second readings
var _seg_sum := 0.0              # this segment: sum of (power / target) per second
var _seg_n := 0
var _seg_honey := 0.0
var _value := 0.0                # coins' worth so far, bias applied at pickup


## Feed one power reading per second, with the target at that moment
## (0 for free ride), whether we are in a max effort, and the bias.
func add_second(watts: float, target: float, max_effort := false) -> void:
	_power.append(watts)
	while _power.size() > SMOOTH_SECONDS:
		_power.pop_front()
	if target > 0.0:
		_seg_sum += minf(watts / target, BAND_HIGH)
		_seg_n += 1
	if max_effort:
		# Every watt over FTP is nectar; a strong sprint fills a comb or two.
		_seg_honey += maxf(watts - ftp, 0.0) / ftp


func smoothed() -> float:
	if _power.is_empty():
		return 0.0
	var s := 0.0
	for p in _power:
		s += p
	return s / _power.size()


## "low", "in", or "high" against the target right now.
func band(target: float) -> String:
	var p := smoothed()
	if target <= 0.0:
		return "in" if p >= ftp * FREE_RIDE_FLOOR else "low"
	if p < target * BAND_LOW:
		return "low"
	if p > target * BAND_HIGH:
		return "high"
	return "in"


func in_band(target: float) -> bool:
	return band(target) != "low"   # over target still forages; it just costs you


func start_segment() -> void:
	_seg_sum = 0.0
	_seg_n = 0
	_seg_honey = 0.0


func segment_average() -> float:
	return _seg_sum / _seg_n if _seg_n > 0 else 0.0


## Called at the end of a segment that released a critter.
func critter_caught() -> bool:
	return _seg_n >= 5 and segment_average() >= CRITTER_AVERAGE


func honey_earned() -> int:
	return int(round(_seg_honey * 2.0))


## What a find is worth is fixed at the moment you pick it: bias scales it,
## and so does ripeness, how hard the ground you picked it on was.
func add(kind: String, count := 1, bias := 100, target_fraction := 0.0) -> void:
	basket[kind] = int(basket.get(kind, 0)) + count
	var ripe := ripeness(target_fraction) if kind in ["berry", "flower"] else 1.0
	_value += count * int(VALUES.get(kind, 0)) * bias / 100.0 * ripe


## Harder ground grows riper finds: endurance x1 up to VO2 x4.
static func ripeness(target_fraction: float) -> float:
	if target_fraction >= 1.05:
		return 4.0
	if target_fraction >= 0.90:
		return 3.0
	if target_fraction >= 0.76:
		return 2.0
	return 1.0


func value() -> int:
	return int(round(_value))


## Coins at the trading post: the haul plus a load bonus from the training
## stress actually ridden, so a hard plan pays even when ERG does the watts.
static func coins(haul_value: int, tss: float) -> int:
	return haul_value + int(round(tss * 1.5))
