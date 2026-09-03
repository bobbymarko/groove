extends SceneTree
## Print the node tree of an imported scene:  godot --headless --path . -s tools/inspect_scene.gd -- res://path.fbx

func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var packed: PackedScene = load(path)
	if packed == null:
		print("failed to load ", path)
		quit(1)
		return
	var root := packed.instantiate()
	_dump(root, 0)
	quit(0)


func _dump(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + "%s (%s)" % [n.name, n.get_class()]
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		line += "  surfaces=%d" % m.get_surface_count()
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			var arrays := m.surface_get_arrays(i)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			line += "\n" + "  ".repeat(depth + 2) + "surface %d: %s tris=%d tex=%s skin=%s" % [
				i, mat.resource_name if mat else "-", idx.size() / 3 if idx else 0,
				str(mat.albedo_texture) if mat is BaseMaterial3D and mat.albedo_texture else "none",
				"yes" if arrays[Mesh.ARRAY_BONES] else "no"]
		if n.skeleton != NodePath():
			line += "\n" + "  ".repeat(depth + 2) + "skeleton=" + str(n.skeleton)
	if n is Skeleton3D:
		line += "  bones=%d" % n.get_bone_count()
		var names := []
		for b in n.get_bone_count():
			names.append(n.get_bone_name(b))
		line += "\n" + "  ".repeat(depth + 2) + ", ".join(names.slice(0, 70))
		var aabb_hint: Vector3 = n.get_bone_global_rest(n.find_bone("mixamorig_Head") if n.find_bone("mixamorig_Head") >= 0 else 0).origin
		line += "\n" + "  ".repeat(depth + 2) + "head rest origin=%s" % aabb_hint
	if n is AnimationPlayer:
		line += "  anims=%s" % str(n.get_animation_list())
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1)
