class_name Backdrop
extends Node3D
## Mountain range on the horizon: a coarse lit heightfield a few hundred metres
## out that follows the rider (so it reads as distant), plus a pale unlit
## silhouette wall far behind it for depth. Faces catch the sun, steep ground is
## rock, gentle ground is snow, and the cel shader adds grain and shadows.

const NEAR := 520.0        # metres ahead the range begins
const DEPTH := 1100.0      # how deep the range extends
const WIDTH := 4200.0
const CELL := 40.0

var _range: MeshInstance3D
var _far: MeshInstance3D


func _ready() -> void:
	_range = _build_range(31)
	add_child(_range)
	_far = _build_far_wall(1900.0, 7000.0, 120.0, 220.0, 41)
	add_child(_far)


func follow(pos: Vector3) -> void:
	# Lock to the rider on X and Z so the range never gets nearer; sit a little
	# below the rider so the foot of the range hides behind the local terrain.
	global_position = Vector3(pos.x, pos.y - 10.0, pos.z)


func _height(n: FastNoiseLite, n2: FastNoiseLite, x: float, z: float) -> float:
	# Ridged multi-octave noise: sharp peaks, broad shoulders.
	var u := x * 0.0011
	var v := z * 0.0011
	var ridged := 1.0 - absf(n.get_noise_2d(u * 10.0, v * 10.0))
	var ridged2 := 1.0 - absf(n2.get_noise_2d(u * 23.0, v * 23.0))
	var broad := (n.get_noise_2d(u * 3.0, v * 3.0) + 1.0) * 0.5
	var h := pow(ridged, 2.4) * 170.0 * (0.5 + broad) + pow(ridged2, 3.0) * 40.0
	# Taper toward the near edge so the range rises out of the ground.
	var depth_t := clampf((z - NEAR) / 300.0, 0.0, 1.0)
	return h * smoothstep(0.0, 1.0, depth_t) - 20.0


func _build_range(seed_value: int) -> MeshInstance3D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var n2 := FastNoiseLite.new()
	n2.seed = seed_value + 7
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var nx := int(WIDTH / CELL)
	var nz := int(DEPTH / CELL)
	var hs := PackedFloat64Array()
	hs.resize((nx + 1) * (nz + 1))
	for iz in nz + 1:
		for ix in nx + 1:
			var x := -WIDTH * 0.5 + ix * CELL
			var z := NEAR + iz * CELL
			hs[iz * (nx + 1) + ix] = _height(n, n2, x, z)
	var st := MeshLib.begin()
	for iz in nz:
		for ix in nx:
			var p := func(i: int, j: int) -> Vector3:
				return Vector3(-WIDTH * 0.5 + i * CELL, hs[j * (nx + 1) + i], NEAR + j * CELL)
			var p00: Vector3 = p.call(ix, iz)
			var p10: Vector3 = p.call(ix + 1, iz)
			var p01: Vector3 = p.call(ix, iz + 1)
			var p11: Vector3 = p.call(ix + 1, iz + 1)
			_tri(st, p00, p11, p10)
			_tri(st, p00, p01, p11)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st)
	var m := MeshLib.cel_material(true, Color.WHITE, 0.93)   # snow only on the flattest faces; colour carries the rest
	m.set_shader_parameter("speckle", true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flat-shaded triangle coloured by slope and height: rock on steep faces,
## blue-mauve mid slopes, snow-shade high up (the shader adds bright snow on top).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	var h := (a.y + b.y + c.y) / 3.0
	var steep := 1.0 - nrm.y
	# Mauve foothills, blue-grey flanks, snow-shade near the peaks, dark rock on cliffs.
	var col := Palette.MOUNTAIN_MID
	if steep > 0.6:
		col = Palette.ROCK_DARK
	elif h > 120.0:
		col = Palette.SNOW_SHADE if steep < 0.35 else Palette.MOUNTAIN_NEAR
	elif h > 55.0:
		col = Palette.MOUNTAIN_NEAR if steep > 0.3 else Palette.MOUNTAIN_MID2
	MeshLib.tri(st, a, b, c, col)


## Distant unlit silhouette for depth, with a snow line.
func _build_far_wall(dist: float, width: float, base_h: float, amp: float, seed_value: int) -> MeshInstance3D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.0
	var st := MeshLib.begin()
	var steps := 160
	var prev := Vector3.ZERO
	var prev_cap := 0.0
	var floor_y := -60.0
	for i in steps + 1:
		var t := float(i) / steps
		var x := -width * 0.5 + width * t
		var u := t * 12.0
		var ridged := 1.0 - absf(n.get_noise_2d(u, 3.0))
		var peak := base_h + pow(ridged, 2.0) * amp
		var p := Vector3(x, peak, dist)
		var cap := peak - amp * 0.25
		if i > 0:
			MeshLib.quad(st, Vector3(prev.x, floor_y, dist), Vector3(p.x, floor_y, dist), p, prev, Palette.MOUNTAIN_FAR)
			var off := Vector3(0.0, 0.0, -3.0)
			MeshLib.quad(st, Vector3(prev.x, prev_cap, dist) + off, Vector3(p.x, cap, dist) + off, p + off, prev + off, Palette.SNOW)
		prev = p
		prev_cap = cap
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
