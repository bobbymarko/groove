class_name Backdrop
extends Node3D
## Far mountain ridges that follow the rider so they read as distant. Three
## strips at increasing distance and lighter, pinker colour, like the reference.

var _layers: Array[Node3D] = []


func _ready() -> void:
	_layers.append(_ridge(220.0, 900.0, 160.0, 55.0, 21, Palette.MOUNTAIN_NEAR, Palette.SNOW_SHADE))
	_layers.append(_ridge(420.0, 1400.0, 260.0, 95.0, 31, Palette.MOUNTAIN_MID, Palette.SNOW))
	_layers.append(_ridge(700.0, 2200.0, 420.0, 160.0, 41, Palette.MOUNTAIN_FAR, Palette.SNOW))


func follow(pos: Vector3) -> void:
	# Lock to the rider on X and Z (infinitely far), keep the base below the horizon.
	global_position = Vector3(pos.x, pos.y - 30.0, pos.z)


func _ridge(dist: float, width: float, base_h: float, amp: float, seed_value: int, col: Color, snow: Color) -> Node3D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.004
	var st := MeshLib.begin()
	var steps := 40
	var prev := Vector3.ZERO
	for i in steps + 1:
		var t := float(i) / steps
		var x := -width * 0.5 + width * t
		var peak := base_h + absf(n.get_noise_2d(x, dist)) * amp + absf(n.get_noise_2d(x * 3.0, dist)) * amp * 0.3
		var p := Vector3(x, peak, dist)
		if i > 0:
			var a := Vector3(prev.x, -40.0, dist)
			var b := Vector3(p.x, -40.0, dist)
			MeshLib.quad(st, a, b, p, prev, col)
			# Snow caps on the upper third.
			if peak > base_h + amp * 0.35:
				var off := Vector3(0.0, 0.0, -1.5)
				var cap_a := prev.lerp(Vector3(prev.x, -40.0, dist), 0.3) + off
				var cap_b := p.lerp(Vector3(p.x, -40.0, dist), 0.3) + off
				MeshLib.quad(st, cap_a, cap_b, p + off, prev + off, snow)
		prev = p
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st)
	mi.material_override = MeshLib.cel_material(true)
	add_child(mi)
	return mi
