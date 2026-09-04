class_name Pickup
extends Node3D
## A weapon floating over the trail, spinning, waiting to be ridden through.

var tier := 1
var _t := 0.0


func _ready() -> void:
	var w := Weapon.build(tier)
	w.scale = Vector3.ONE * 1.6   # readable from the follow camera
	add_child(w)
	var glow := OmniLight3D.new()
	glow.light_color = HudStyle.YELLOW
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.shadow_enabled = false
	add_child(glow)


func spin(delta: float) -> void:
	_t += delta
	rotation.y += delta * 2.2
	position.y += sin(_t * 3.0) * delta * 0.25
