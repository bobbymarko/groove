class_name MonsterStand
extends Node3D
## A monster off the bike: standing, sitting in a camp chair, or leaning on a
## counter. Idle breathing keeps it alive. Rotate this node to face it.

enum Stance { STAND, SIT, COUNTER }

var recipe: Dictionary = {}
var stance := Stance.STAND
var seat_height := 0.46           ## SIT: top of the chair seat
var counter := Vector3(0.45, 1.0, 0.0)  ## COUNTER: where the hands rest
var hold := Vector3.ZERO          ## SIT: both hands meet here (a mug); zero = on knees

var rig: MonsterRig
var _t := 0.0


func _ready() -> void:
	rig = MonsterRig.new()
	rig.recipe = recipe
	add_child(rig)
	rig.build()
	pose()


func advance(dt: float) -> void:
	_t += dt
	pose()


func pose() -> void:
	var breathe := sin(_t * 1.7) * 0.012
	var leg := rig.size("leg")
	var arm := rig.size("arm")
	var sole_y := 0.0
	var origin: Vector3
	var ankles: Array = []
	var wrists: Array = []
	var lean := 0.0
	match stance:
		Stance.SIT:
			origin = Vector3(0, seat_height + breathe * 0.5, 0)
			lean = deg_to_rad(-6.0)
			for side in 2:
				var z := 1.0 if side == 0 else -1.0
				var h := rig.hip(side, origin, lean)
				ankles.append(rig.ankle_for(Vector3(h.x + leg * 0.55 + 0.08, sole_y, h.z * 1.2), 0.0))
				if hold != Vector3.ZERO:
					wrists.append(hold + Vector3(-0.06, 0, 0.07 * z))
				else:
					wrists.append(Vector3(h.x + leg * 0.4, seat_height + 0.08, h.z * 1.3))
		_:
			# Standing: hips at leg height above the ankles.
			var hip_local := rig.socket("hip_r")
			origin = Vector3(0, 0.10 + leg * 0.97 - hip_local.y + breathe, 0)
			lean = deg_to_rad(8.0 if stance == Stance.COUNTER else 2.0)
			for side in 2:
				var z := 1.0 if side == 0 else -1.0
				var h := rig.hip(side, origin, lean)
				ankles.append(rig.ankle_for(Vector3(h.x + 0.09, sole_y, h.z * 1.05), 0.0))
				var s := rig.shoulder(side, origin, lean)
				if stance == Stance.COUNTER:
					wrists.append(counter + Vector3(-0.05, 0.03, 0.22 * z * rig.size("girth")))
				else:
					wrists.append(s + Vector3(0.06, -arm * 0.92, 0.10 * z))
	rig.pose(origin, lean, 0.0, ankles, [0.0, 0.0], wrists,
		Vector3(1, 0.3, 0), Vector3(-0.3, -1.0, 0.8))
