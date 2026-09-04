class_name TreadMarks
extends MeshInstance3D
## The tyre track the rear wheel leaves behind: a ribbon of quads laid just
## above the terrain along the rider's path, alternating lug and gap so it
## reads as tread, fading back into the ground colour with age.

const MAX_POINTS := 360        # about 50 m of track
const SPACING := 0.14          # metres between samples, one lug each
const WIDTH := 0.11            # fat-bike contact patch
const LIFT := 0.02             # above the terrain so it does not z-fight

var _pts: Array[Vector3] = []
var _rights: Array[Vector3] = []
var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := MeshLib.cel_material(true)
	m.set_shader_parameter("smooth_lighting", true)
	material_override = m


## Call every frame with the rear-wheel contact point (global), the bike's
## right vector and a height function; samples are spaced SPACING apart.
func add(pos: Vector3, right: Vector3, height_fn: Callable) -> void:
	if not _pts.is_empty() and Vector2(_pts[-1].x, _pts[-1].z).distance_to(Vector2(pos.x, pos.z)) < SPACING:
		return
	pos.y = float(height_fn.call(pos.x, pos.z)) + LIFT
	var r := Vector3(right.x, 0.0, right.z).normalized()
	if r.length() < 0.5:
		r = Vector3.RIGHT
	_pts.append(pos)
	_rights.append(r)
	if _pts.size() > MAX_POINTS:
		_pts.pop_front()
		_rights.pop_front()
	_rebuild()


func clear() -> void:
	_pts.clear()
	_rights.clear()
	_mesh.clear_surfaces()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _pts.size() < 2:
		return
	var ground := Palette.TRAIL_DARK
	var lug := ground.darkened(0.3)
	var gap := ground.darkened(0.12)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _pts.size()
	for i in range(1, n):
		var age := 1.0 - float(i) / float(n)          # 0 = freshest, 1 = about to vanish
		var col := (lug if i % 2 == 0 else gap).lerp(ground, age * age)
		var half := WIDTH * 0.5 * (1.0 if i % 2 == 0 else 0.8)
		var a := _pts[i - 1]
		var b := _pts[i]
		var ra := _rights[i - 1] * half
		var rb := _rights[i] * half
		_quad(a - ra, a + ra, b + rb, b - rb, col)
	_mesh.surface_end()


## Upward-facing quad, emitted in both windings so it shows from either side.
func _quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	for tri in [[p0, p1, p2], [p0, p2, p3], [p0, p2, p1], [p0, p3, p2]]:
		for v in tri:
			_mesh.surface_set_normal(Vector3.UP)
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(v)
