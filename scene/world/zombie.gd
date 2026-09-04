class_name Zombie
extends Node3D
## One shambler. Walks toward the rider; on contact it is flung with a simple
## ballistic tumble (bouncing on the terrain) and dissolves. Model: "Animated
## Zombie" by Quaternius (CC BY 3.0), see assets/zombie/ATTRIBUTION.txt.

const SCENE := "res://assets/zombie/animated_zombie.glb"
const HEIGHT := 1.8
const WALK := "Zombie|ZombieWalk"
const RUN := "Zombie|ZombieRun"
const FLING_LIFE := 1.3

static var _packed: PackedScene

var speed := 1.4                 # m/s toward the rider
var flung := false
var _vel := Vector3.ZERO
var _spin := Vector3.ZERO
var _life := 0.0
var _anim: AnimationPlayer
var _mats: Array[StandardMaterial3D] = []
var _model: Node3D


func _ready() -> void:
	if _packed == null:
		_packed = load(SCENE)
	_model = _packed.instantiate()
	add_child(_model)
	# Scale the rig to a person's height whatever units it was authored in.
	var aabb := _bounds(_model)
	if aabb.size.y > 0.001:
		_model.scale = Vector3.ONE * (HEIGHT / aabb.size.y)
		_model.position.y = -aabb.position.y * _model.scale.y
	_model.rotation.y = PI   # the rig faces +Z; look_at points -Z at the rider
	if OS.is_debug_build() and _packed.get_meta("logged", false) == false:
		_packed.set_meta("logged", true)
		print("[zombie] model bounds %s -> scale %.2f" % [aabb, _model.scale.x])
	_anim = _model.find_child("AnimationPlayer", true, false)
	if _anim:
		_anim.play(WALK)
		_anim.speed_scale = randf_range(0.85, 1.15)
	for mi in _meshes(_model):
		for i in mi.get_surface_override_material_count():
			var m := mi.mesh.surface_get_material(i) if mi.get_surface_override_material(i) == null else mi.get_surface_override_material(i)
			if m is StandardMaterial3D:
				var d: StandardMaterial3D = m.duplicate()
				mi.set_surface_override_material(i, d)
				_mats.append(d)


func run(fast: bool) -> void:
	if _anim and not flung:
		var want := RUN if fast else WALK
		if _anim.current_animation != want:
			_anim.play(want)
	speed = 2.6 if fast else 1.4


## Knocked away from `from` (the rider) with this much oomph.
func fling(from: Vector3, oomph: float) -> void:
	if flung:
		return
	flung = true
	var away := (global_position - from)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
	_vel = away * oomph + Vector3.UP * (oomph * 0.7 + 2.5) + Vector3(0, 0, oomph * 0.4)
	_spin = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))
	if _anim:
		_anim.pause()
	for m in _mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


## Called by the horde each frame. Returns false when the zombie is spent.
func step(delta: float, rider_pos: Vector3, height_fn: Callable) -> bool:
	if flung:
		_life += delta
		_vel.y -= 9.81 * delta
		global_position += _vel * delta
		rotation += _spin * delta
		var ground: float = float(height_fn.call(global_position.x, global_position.z))
		if global_position.y < ground:
			global_position.y = ground
			_vel.y = absf(_vel.y) * 0.35
			_vel.x *= 0.6
			_vel.z *= 0.6
		var a := clampf(1.0 - _life / FLING_LIFE, 0.0, 1.0)
		for m in _mats:
			m.albedo_color.a = a
		return _life < FLING_LIFE
	# Shamble toward the rider, feet on the ground, facing them.
	var to := rider_pos - global_position
	to.y = 0.0
	if to.length() > 0.05:
		global_position += to.normalized() * speed * delta
		look_at(Vector3(rider_pos.x, global_position.y, rider_pos.z), Vector3.UP)
	global_position.y = float(height_fn.call(global_position.x, global_position.z))
	return true


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(n):
		var b := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
