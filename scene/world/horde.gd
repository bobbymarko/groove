class_name Horde
extends Node3D
## Zombies for the Apocalypse scene. Spawn rate follows the rider's target
## effort: nothing much on recovery, a crowd on the hard reps. A zombie that
## reaches the rider is kicked away and counted.

signal hit(kills: int)
signal picked_up(tier: int)

const MAX_ZOMBIES := 24
const CONTACT := 1.0             # metres from the rider that counts as contact
const AHEAD_MIN := 26.0
const AHEAD_MAX := 55.0

var effort := 0.5                ## target as a fraction of FTP, set by the ride screen
var kills := 0
var rider: Node3D
var height_fn: Callable
var trail: Trail
var weapon_tier := 0
var _budget := 0.0
var _zombies: Array[Zombie] = []
var _pickup: Pickup
const BEHIND_CULL := 14.0        # a zombie this far behind the rider will never catch up


## Spawns per second at this effort: none below 60 %, ~0.6/s at threshold, 1.6/s at VO2.
static func rate_for(effort_frac: float) -> float:
	var e := clampf((effort_frac - 0.6) / 0.6, 0.0, 1.0)
	return 1.8 * e * e


func update(delta: float, rider_pos: Vector3, rider_speed: float, rider_power: float, distance: float) -> void:
	_budget += rate_for(effort) * delta
	while _budget >= 1.0 and _zombies.size() < MAX_ZOMBIES:
		_budget -= 1.0
		spawn(distance)
	var fast := effort >= 0.9
	var i := 0
	while i < _zombies.size():
		var z := _zombies[i]
		z.run(fast)
		if not z.flung and Vector2(z.global_position.x - rider_pos.x, z.global_position.z - rider_pos.z).length() < CONTACT:
			z.fling(rider_pos, 3.0 + rider_speed * 1.2 + rider_power / 80.0 + Weapon.oomph_for(weapon_tier))
			kills += 1
			hit.emit(kills)
		# Left behind: it will never reach the rider, so free the slot for a fresh one.
		var behind := not z.flung and z.global_position.z < rider_pos.z - BEHIND_CULL
		if not behind and z.step(delta, rider_pos, height_fn):
			i += 1
		else:
			z.queue_free()
			_zombies.remove_at(i)
	if _pickup:
		_pickup.spin(delta)
		if Vector2(_pickup.global_position.x - rider_pos.x, _pickup.global_position.z - rider_pos.z).length() < 1.4:
			weapon_tier = _pickup.tier
			_pickup.queue_free()
			_pickup = null
			picked_up.emit(weapon_tier)
		elif _pickup.global_position.z < rider_pos.z - 6.0:
			_pickup.queue_free()   # missed it; the next interval brings another
			_pickup = null


## One zombie somewhere ahead on or beside the trail.
func spawn(distance: float, ahead := -1.0) -> void:
	var z := Zombie.new()
	var d := distance + (ahead if ahead > 0.0 else randf_range(AHEAD_MIN, AHEAD_MAX))
	var p := trail.position_at(d)
	var lateral := randf_range(-4.0, 4.0)
	if absf(lateral) < 1.0:
		lateral = 1.0 * signf(lateral if lateral != 0.0 else 1.0)
	p.x += lateral
	add_child(z)
	z.global_position = Vector3(p.x, float(height_fn.call(p.x, p.z)), p.z)
	_zombies.append(z)


## After a completed hard interval: the next weapon appears on the trail ahead.
func drop_pickup(distance: float) -> void:
	if _pickup != null or weapon_tier >= Weapon.MAX_TIER:
		return
	_pickup = Pickup.new()
	_pickup.tier = weapon_tier + 1
	add_child(_pickup)
	var p := trail.position_at(distance + 22.0)
	_pickup.global_position = Vector3(p.x, float(height_fn.call(p.x, p.z)) + 1.1, p.z)


func clear() -> void:
	for z in _zombies:
		z.queue_free()
	_zombies.clear()
