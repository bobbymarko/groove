class_name Noodle
extends MeshInstance3D
## A faceted tube through a few points: monster arms and legs. Rebuilt every
## frame so any limb length and thickness bends to reach the pedals and bars.

var sides := 6
var colour_material: Material

var _im := ImmediateMesh.new()


func _init() -> void:
	mesh = _im


## points and radii are the same length. Extra rings either side of each
## joint keep bends chunky instead of pinched.
func build(points: Array[Vector3], radii: Array[float], side_axis := Vector3(0, 0, 1)) -> void:
	var rings: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var r: float = radii[i]
		if i == 0:
			rings.append(_ring(p, (points[1] - p).normalized(), r, side_axis))
		elif i == points.size() - 1:
			rings.append(_ring(p, (p - points[i - 1]).normalized(), r, side_axis))
		else:
			var d_in := (p - points[i - 1]).normalized()
			var d_out := (points[i + 1] - p).normalized()
			rings.append(_ring(p - d_in * r * 0.7, d_in, r, side_axis))
			rings.append(_ring(p, (d_in + d_out).normalized(), r * 1.04, side_axis))
			rings.append(_ring(p + d_out * r * 0.7, d_out, r, side_axis))
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, colour_material)
	for k in rings.size() - 1:
		var a: Array = rings[k]
		var b: Array = rings[k + 1]
		for s in sides:
			var s2 := (s + 1) % sides
			_tri(a[s], b[s], b[s2])
			_tri(a[s], b[s2], a[s2])
	_cap(rings[0], points[0], true)
	_cap(rings[-1], points[-1], false)
	_im.surface_end()


func _ring(c: Vector3, t: Vector3, r: float, side_axis: Vector3) -> Array:
	var b := side_axis - t * side_axis.dot(t)
	if b.length() < 0.01:
		b = Vector3.UP - t * t.y
	b = b.normalized()
	var u := t.cross(b)
	var out := []
	for s in sides:
		var a := TAU * (float(s) + 0.5) / sides
		out.append(c + (b * cos(a) + u * sin(a)) * r)
	return out


func _cap(ring: Array, centre: Vector3, start: bool) -> void:
	for s in sides:
		var s2 := (s + 1) % sides
		if start:
			_tri(centre, ring[s2], ring[s])
		else:
			_tri(centre, ring[s], ring[s2])


func _tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	_im.surface_add_vertex(a)
	_im.surface_add_vertex(b)
	_im.surface_add_vertex(c)
