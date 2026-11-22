class_name FarRange
extends MeshInstance3D
## The horizon for the realistic look: a ring of mountains 2.5-9 km out,
## built once from ridged noise, travelling with the rider (so it never gets
## nearer), set low enough that the near terrain always hides its foot.

const RINGS := [2400.0, 2700.0, 3000.0, 3350.0, 3750.0, 4200.0, 4700.0, 5250.0, 5900.0, 6600.0, 7400.0, 8300.0, 9300.0]
const AROUND := 480

var _mat := ShaderMaterial.new()


## height: tallest peaks (m); look: the biome's colours and snow line.
func build(height: float, biome: Dictionary) -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 31
	fn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	fn.fractal_octaves = 5
	fn.frequency = 0.00045
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for ri in RINGS.size():
		var r: float = RINGS[ri]
		var rise := smoothstep(2400.0, 4200.0, r)
		for a in AROUND + 1:
			var ang := TAU * float(a) / AROUND
			var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			var v := fn.get_noise_2d(p.x, p.z) * 0.5 + 0.5
			p.y = -60.0 + rise * pow(v, 1.6) * height * (0.55 + 0.45 * fn.get_noise_1d(ang * 300.0) * 0.5 + 0.225)
			verts.append(p)
	for ri in RINGS.size() - 1:
		for a in AROUND:
			var i0 := ri * (AROUND + 1) + a
			var i1 := i0 + AROUND + 1
			idx.append_array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1])
	# Smooth normals: each vertex takes the area-weighted normals of its faces.
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var fnrm := (verts[idx[t + 2]] - verts[idx[t]]).cross(verts[idx[t + 1]] - verts[idx[t]])
		for k in 3:
			norms[idx[t + k]] += fnrm
	for i in norms.size():
		norms[i] = norms[i].normalized()
		if norms[i].y < 0.0:
			norms[i] = -norms[i]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = am
	_mat.shader = load("res://scene/real/far_range.gdshader")
	if biome.has("range_rock"):
		_mat.set_shader_parameter("rock", biome.range_rock)
	if biome.has("range_scrub"):
		_mat.set_shader_parameter("scrub", biome.range_scrub)
	_mat.set_shader_parameter("snow_line", float(biome.get("snow_line", 9999.0)))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Lit by hand the way the terrain is lit by the engine: the sun (or moon) as
## RideScene set it, plus the sky's light in shade, so the range matches the
## near land at every hour.
func set_light(sun_light: Color, daylight: float, rain: float) -> void:
	_mat.set_shader_parameter("sun_light", Vector3(sun_light.r, sun_light.g, sun_light.b))
	var sky := Color(0.32, 0.38, 0.5).lerp(Color(0.42, 0.44, 0.48), rain) * lerpf(0.03, 1.0, daylight)
	_mat.set_shader_parameter("sky_light", Vector3(sky.r, sky.g, sky.b))


func follow(pos: Vector3) -> void:
	global_position = Vector3(pos.x, pos.y - 20.0, pos.z)
