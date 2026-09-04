class_name Backdrop
extends Node3D
## Stylized layered mountains on the horizon, in the manner of the reference
## art: five silhouette layers from deep blue (near) to pale pink (far), each a
## jagged ridge with sunlit and shaded facets and a ragged snow line. Unlit, so
## the colours stay poster-flat; they follow the rider so they never get nearer.

const LAYERS := [
	# distance, width, base height, amplitude, seed
	[420.0, 1400.0, 28.0, 70.0, 21],
	[640.0, 2000.0, 55.0, 105.0, 26],
	[900.0, 2800.0, 85.0, 140.0, 31],
	[1250.0, 3800.0, 120.0, 175.0, 36],
	[1700.0, 5200.0, 150.0, 210.0, 41],
]

var _layers: Array[Node3D] = []
var _mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	# Near to far: the palette's mountain tones, shaded facets a step darker,
	# and a snow line that whitens with distance.
	var lit := [Palette.MOUNTAIN_NEAR, Palette.MOUNTAIN_MID2, Palette.MOUNTAIN_MID, Palette.MOUNTAIN_FAR2, Palette.MOUNTAIN_FAR]
	for i in LAYERS.size():
		var l: Array = LAYERS[i]
		var c: Color = lit[i]
		_layers.append(_ridge(l[0], l[1], l[2], l[3], l[4], c, c.darkened(0.2), Palette.MOUNTAIN_SNOW.lerp(c, 0.25 - 0.06 * i)))


func follow(pos: Vector3) -> void:
	global_position = Vector3(pos.x, pos.y - 12.0, pos.z)


func _ridge(dist: float, width: float, base_h: float, amp: float, seed_value: int, lit: Color, shade: Color, snow: Color) -> Node3D:
	var st := MeshLib.begin()
	# Main silhouette, then two inner ridges in front of it: lower, shifted, in
	# the shaded tone, so spurs appear to run down inside the mass.
	_profile(st, dist, width, base_h, amp, seed_value, lit, shade, snow, 1.0, 0.0)
	_profile(st, dist - 4.0, width, base_h * 0.55, amp * 0.72, seed_value + 3, shade.lerp(lit, 0.35), shade.darkened(0.12), snow.lerp(shade, 0.25), 0.75, 0.31)
	_profile(st, dist - 8.0, width, base_h * 0.25, amp * 0.5, seed_value + 5, shade.lerp(lit, 0.15), shade.darkened(0.22), snow.lerp(shade, 0.4), 0.6, 0.67)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	_mats.append(m)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## One jagged profile as a wall from floor to ridgeline with lit/shaded facets
## and a ragged snow band. `phase` shifts the noise so inner ridges do not
## echo the outer one; `snow_frac` scales how deep the snow band reaches.
func _profile(st: SurfaceTool, dist: float, width: float, base_h: float, amp: float, seed_value: int, lit: Color, shade: Color, snow: Color, snow_frac: float, phase: float) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.0
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var steps := 420
	var floor_y := -80.0
	var xs := PackedFloat64Array()
	var peaks := PackedFloat64Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := t * width / 520.0 + phase * 7.0   # one major peak every ~500 m, whatever the layer width
		var ridged := 1.0 - absf(n.get_noise_2d(u, 1.0))
		var sub := 1.0 - absf(n.get_noise_2d(u * 2.7, 9.0))
		var peak := base_h + pow(ridged, 2.0) * amp + pow(sub, 3.0) * amp * 0.2
		xs.append(-width * 0.5 + width * t)
		peaks.append(peak)
	for i in steps:
		var a := Vector3(xs[i], peaks[i], dist)
		var b := Vector3(xs[i + 1], peaks[i + 1], dist)
		# Facet shading: slopes rising to the right face the sun (front-left), others are shaded.
		var rising := peaks[i + 1] > peaks[i]
		var col := lit if rising else shade
		MeshLib.quad(st, Vector3(a.x, floor_y, dist), Vector3(b.x, floor_y, dist), b, a, col)
		# Snow: the top band of the ridge, its lower edge ragged and lower on lit faces.
		var line_jitter := n.get_noise_2d(float(i) * 0.25, 33.0) * amp * 0.1
		var snow_a := peaks[i] - amp * (0.22 if rising else 0.15) * snow_frac + line_jitter
		var snow_b := peaks[i + 1] - amp * (0.22 if rising else 0.15) * snow_frac + line_jitter
		var off := Vector3(0.0, 0.0, -2.0)
		var cap_col := snow if rising else snow.lerp(shade, 0.35)
		MeshLib.quad(st, Vector3(a.x, snow_a, dist) + off, Vector3(b.x, snow_b, dist) + off, b + off, a + off, cap_col)


## Unshaded ridges take the time of day as a multiplier (night blue, dusk warm).
func set_tint(c: Color) -> void:
	for m in _mats:
		m.albedo_color = c
