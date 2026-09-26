class_name PartKit
extends RefCounted
## Loads the Blender-built model files once and hands out copies of single
## parts, with their attachment points.

const FILES := {
	"monster": "res://camp/art/models/monster_kit.glb",
	"bike": "res://camp/art/models/bike.glb",
	"nature": "res://camp/art/models/nature.glb",
	"camp": "res://camp/art/models/camp.glb",
}

static var _templates: Dictionary = {}


static func _template(file: String) -> Node:
	if not _templates.has(file):
		var packed: PackedScene = load(FILES[file])
		_templates[file] = packed.instantiate()
	return _templates[file]


static func has_part(file: String, part: String) -> bool:
	return _template(file).find_child(part, true, false) != null


## A fresh copy of one part: a MeshInstance3D whose socket children were
## stripped and returned separately as local transforms.
static func part(file: String, part_name: String) -> Dictionary:
	var src := _template(file).find_child(part_name, true, false)
	if src == null:
		push_error("PartKit: no part %s in %s" % [part_name, file])
		return {"node": Node3D.new(), "sockets": {}}
	var copy: Node3D = src.duplicate()
	copy.transform = Transform3D.IDENTITY
	var sockets := {}
	for child in copy.get_children():
		var n := String(child.name)
		var cut := n.rfind("__")
		if cut >= 0:
			sockets[n.substr(cut + 2)] = (child as Node3D).transform
			copy.remove_child(child)
			child.free()
	return {"node": copy, "sockets": sockets}


## Convenience for static props: node only.
static func prop(file: String, part_name: String) -> Node3D:
	return part(file, part_name).node
