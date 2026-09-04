class_name RidePhysics
extends RefCounted
## Rider speed from power and grade: a simple bike model so hard efforts move
## faster, climbs slow you down, and coasting decays.

const MASS := 92.0          # default rider + fat bike, kg (see `mass`)
const CDA := 0.55           # upright, winter clothing
const CRR := 0.030          # fat tyres on groomed snow: slow going
const RHO := 1.2
const G := 9.81
const MIN_SPEED := 0.0      # no pedalling, no rolling: the rider stands still until power arrives
const MAX_SPEED := 18.0
## How much of the (exaggerated, visual) grade acts on speed. 0 keeps speed a
## function of power alone, so the terrain generator can predict where the
## rider will be and hills line up with intervals. The trainer supplies the
## real resistance; the hill is scenery.
const GRADE_EFFECT := 0.0

var speed := 0.0            # m/s; nobody rolls until they pedal
var mass := MASS            # rider weight + bike, set from Settings


func step(power_w: float, grade_percent: float, delta: float, riding := true) -> float:
	var v := maxf(speed, 0.5)
	var f_drag := 0.5 * RHO * CDA * v * v
	var f_roll := CRR * mass * G
	var f_grade := mass * G * (grade_percent * GRADE_EFFECT / 100.0)
	var f_prop := power_w / v
	var accel := (f_prop - f_drag - f_roll - f_grade) / mass
	speed = clampf(speed + accel * delta, MIN_SPEED if riding else 0.0, MAX_SPEED)
	if power_w < 1.0 and speed < 0.3:
		speed = 0.0   # rolling resistance stops a coasting bike; do not creep
	return speed


## Steady-state speed for a power and grade (for tests and tuning).
static func steady_speed(power_w: float, grade_percent: float, mass_kg := MASS) -> float:
	var lo := 0.5
	var hi := MAX_SPEED
	for i in 40:
		var v := (lo + hi) * 0.5
		var need := (0.5 * RHO * CDA * v * v + CRR * mass_kg * G + mass_kg * G * grade_percent * GRADE_EFFECT / 100.0) * v
		if need < power_w:
			lo = v
		else:
			hi = v
	return (lo + hi) * 0.5
