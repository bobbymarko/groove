class_name Backdrop
extends Node3D
## Far mountain ridges that follow the rider so they read as distant. Three
## strips at increasing distance and lighter, pinker colour, like the reference.

var _layers: Array[Node3D] = []


func _ready() -> void:
	# distance, width, base height, peak amplitude: real mountain proportions so
	# the ridges sit on the horizon instead of filling the sky.
	_layers.append(_ridge(260.0, 900.0, 18.0, 30.0, 21, Palette.MOUNTAIN_NEAR, Palette.SNOW_SHADE))
	_layers.append(_ridge(480.0, 1500.0, 40.0, 55.0, 31, Palette.MOUNTAIN_MID, Palette.SNOW))
	_layers.append(_ridge(800.0, 2400.0, 70.0, 90.0, 41, Palette.MOUNTAIN_FAR, Palette.SNOW))


func follow(pos: Vector3) -> void:
	# Lock to the rider on X and Z (infinitely far), base a little below the rider.
	global_position = Vector3(pos.x, pos.y - 8.0, pos.z)


func _ridge(dist: float, width: float, base_h: float, amp: float, seed_value: int, col: Color, snow: Color) -> Node3D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.0
	var st := MeshLib.begin()
	var steps := 180
	var prev := Vector3.ZERO
	var prev_cap := 0.0
	var floor_y := -40.0
	for i in steps + 1:
		var t := float(i) / steps
		var x := -width * 0.5 + width * t
		# Ridged noise: sharp peaks, broad valleys. Frequencies in cycles per ridge width.
		var u := t * 14.0
		var ridged := 1.0 - absf(n.get_noise_2d(u, dist * 0.01))
		var detail := 1.0 - absf(n.get_noise_2d(u * 3.7, dist * 0.01 + 7.0))
		var peak := base_h + pow(ridged, 2.2) * amp + pow(detail, 3.0) * amp * 0.25
		var p := Vector3(x, peak, dist)
		var cap := peak - amp * 0.22   # snow line relative to this peak
		if i > 0:
			MeshLib.quad(st, Vector3(prev.x, floor_y, dist), Vector3(p.x, floor_y, dist), p, prev, col)
			# Snow on the upper part of the ridge, drawn a touch nearer so it wins the depth test.
			var off := Vector3(0.0, 0.0, -2.0)
			MeshLib.quad(st, Vector3(prev.x, prev_cap, dist) + off, Vector3(p.x, cap, dist) + off, p + off, prev + off, snow)
		prev = p
		prev_cap = cap
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st)
	mi.material_override = MeshLib.cel_material(true)
	add_child(mi)
	return mi
