class_name Weapon
extends RefCounted
## Melee weapons the rider collects in the Apocalypse. Tier 0 is the boot;
## higher tiers are built from primitives in palette colours and ride in the
## rider's right hand. Fling force and swing grow with the tier.

const NAMES := ["boot", "baseball bat", "machete", "chainsaw"]
const MAX_TIER := 3


static func name_for(tier: int) -> String:
	return NAMES[clampi(tier, 0, MAX_TIER)]


## Extra knock-back per tier on top of speed and power.
static func oomph_for(tier: int) -> float:
	return [0.0, 2.5, 4.0, 6.5][clampi(tier, 0, MAX_TIER)]


## Weapon mesh with its handle at the origin and the business end along +Y.
static func build(tier: int) -> Node3D:
	var root := Node3D.new()
	match clampi(tier, 0, MAX_TIER):
		1:
			var bat := CylinderMesh.new()
			bat.bottom_radius = 0.02
			bat.top_radius = 0.045
			bat.height = 0.8
			_part(root, bat, Vector3(0, 0.4, 0), Palette.BRANCH)
			var knob := CylinderMesh.new()
			knob.bottom_radius = 0.035
			knob.top_radius = 0.035
			knob.height = 0.03
			_part(root, knob, Vector3(0, 0.0, 0), Palette.TRUNK)
		2:
			var grip := BoxMesh.new()
			grip.size = Vector3(0.035, 0.16, 0.05)
			_part(root, grip, Vector3(0, 0.08, 0), Palette.TRUNK)
			var blade := BoxMesh.new()
			blade.size = Vector3(0.012, 0.55, 0.09)
			_part(root, blade, Vector3(0, 0.16 + 0.275, 0.02), Color("b9bec6"))
		3:
			var body := BoxMesh.new()
			body.size = Vector3(0.14, 0.26, 0.2)
			_part(root, body, Vector3(0, 0.2, 0), HudStyle.ORANGE)
			var handle := BoxMesh.new()
			handle.size = Vector3(0.03, 0.12, 0.03)
			_part(root, handle, Vector3(0, 0.06, 0), Palette.TRUNK)
			var bar := BoxMesh.new()
			bar.size = Vector3(0.02, 0.62, 0.11)
			_part(root, bar, Vector3(0, 0.33 + 0.31, 0.0), Color("8e949c"))
			var teeth := BoxMesh.new()
			teeth.size = Vector3(0.03, 0.62, 0.02)
			_part(root, teeth, Vector3(0, 0.33 + 0.31, 0.065), Color("50555c"))
	return root


static func _part(root: Node3D, mesh: Mesh, at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshLib.cel_material(false, color)
	mi.position = at
	root.add_child(mi)
