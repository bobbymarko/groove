class_name MeshLib
extends RefCounted
## Builds flat-shaded, vertex-coloured low-poly meshes for props. Every face
## gets its own vertices so normals stay hard, which is what the pixel look wants.

static func cel_material(vertex_color := true, albedo := Color.WHITE, snow_threshold := 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scene/post/cel.gdshader")
	m.set_shader_parameter("use_vertex_color", vertex_color)
	m.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
	m.set_shader_parameter("snow_threshold", snow_threshold)
	m.set_shader_parameter("snow_color", Vector3(Palette.PINE_SNOW.r, Palette.PINE_SNOW.g, Palette.PINE_SNOW.b))
	return m


## Palette colour for an untextured surface. Quaternius's MegaKit names
## materials by what they are (Leaves, Bark); the Ultimate Nature Pack names
## them by colour (Green, Wood, White). Unknown names keep their own albedo.
static func palette_for_material(mat_name: String, albedo := Color.WHITE) -> Color:
	var n := mat_name.to_lower()
	match n:
		"green": return Palette.PINE
		"darkgreen": return Palette.PINE_DARK
		"wood", "black": return Palette.TRUNK
		"lightwood": return Palette.BRANCH
		"rock": return Palette.ROCK
		"white": return Color("e9e7e2")
		"pink": return Palette.FLOWER
		"yellow": return Color("e8c85a")
		"cyan": return Color("7fd0d8")
		"lightorange": return Color("e08a3a")
	if "leaves" in n or "leaf" in n or "bush" in n or "grass" in n or "bark" in n or "trunk" in n or "rock" in n or "stone" in n or "flower" in n:
		return shades_for_material(mat_name)[1]
	return albedo if albedo != Color.WHITE else Palette.ROCK


## Dark and light palette shades a textured surface blends between.
static func shades_for_material(mat_name: String) -> Array[Color]:
	var n := mat_name.to_lower()
	if "flower" in n or "petal" in n:
		return [Palette.FLOWER_DARK, Palette.FLOWER]
	if "leaves" in n or "leaf" in n or "bush" in n or "grass" in n or "clover" in n or "fern" in n or "plant" in n:
		return [Palette.PINE_DARK, Palette.PINE_LIGHT]
	if "bark" in n or "trunk" in n or "wood" in n:
		return [Palette.TRUNK, Palette.BRANCH]
	return [Palette.ROCK_DARK, Palette.ROCK]


## Load an imported glTF prop as a single mesh with palette cel materials
## baked per surface. Snow lands on upward faces of foliage and rock.
## Returns null if the asset is missing so callers can fall back.
static func load_prop(path: String, snow := true) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res == null:
		return null
	var root: Node = null
	var mesh: Mesh
	var xform := Transform3D.IDENTITY
	if res is Mesh:
		mesh = (res as Mesh).duplicate()          # .obj imports straight to a mesh
	elif res is PackedScene:
		root = (res as PackedScene).instantiate()
		var mi := _find_mesh_instance(root)
		if mi == null:
			root.free()
			return null
		mesh = mi.mesh.duplicate()
		xform = mi.transform
	else:
		return null
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var mat_name := src.resource_name if src else ""
		var src_albedo: Color = src.albedo_color if src is BaseMaterial3D else Color.WHITE
		var col := palette_for_material(mat_name, src_albedo)
		var is_bark := col == Palette.TRUNK or col == Palette.BRANCH
		# Textured surfaces keep their own colours (the post-process quantizes
		# them to the palette); untextured ones take the palette colour.
		var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
		var m := cel_material(false, col, 0.74 if (snow and not is_bark) else 2.0)
		m.set_shader_parameter("prop", true)
		if tex:
			var shades := shades_for_material(mat_name)
			m.set_shader_parameter("use_texture", true)
			m.set_shader_parameter("albedo_tex", tex)
			m.set_shader_parameter("colorize", true)
			m.set_shader_parameter("shade_dark", Vector3(shades[0].r, shades[0].g, shades[0].b))
			m.set_shader_parameter("shade_light", Vector3(shades[1].r, shades[1].g, shades[1].b))
			m.set_shader_parameter("alpha_cutout", src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
		mesh.surface_set_material(i, m)
	if root:
		root.free()
	# Bake the node transform (Quaternius models are Y-up, metres) if it is not identity.
	if not xform.is_equal_approx(Transform3D.IDENTITY):
		var st := SurfaceTool.new()
		var out := ArrayMesh.new()
		for i in mesh.get_surface_count():
			st.clear()
			st.create_from(mesh, i)
			var arrays := st.commit_to_arrays()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts.size():
				verts[v] = xform * verts[v]
			arrays[Mesh.ARRAY_VERTEX] = verts
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(i, mesh.surface_get_material(i))
		return out
	return mesh


static func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null


## Add a triangle with a flat normal and one colour. a, b, c are given
## counter-clockwise as seen from the front (right-hand rule gives the normal);
## Godot's front faces are clockwise, so vertices are emitted as a, c, b.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(c)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(b)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(st, a, b, c, col)
	tri(st, a, c, d, col)


## Cone (or frustum) around the Y axis from y0 (radius r0) to y1 (radius r1).
## The part above `split` (fraction of the height) takes col_top, so a tier
## of foliage can carry snow on its shoulders.
static func cone(st: SurfaceTool, y0: float, r0: float, y1: float, r1: float, sides: int, col: Color, col_top := Color.TRANSPARENT, split := 0.5) -> void:
	var top_col := col if col_top == Color.TRANSPARENT else col_top
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		if top_col == col:
			if r1 <= 0.001:
				tri(st, p0, q0, p1, col)
			else:
				quad(st, p0, q0, q1, p1, col)
			continue
		var m0 := p0.lerp(q0, split)
		var m1 := p1.lerp(q1, split)
		quad(st, p0, m0, m1, p1, col)
		if r1 <= 0.001:
			tri(st, m0, q0, m1, top_col)
		else:
			quad(st, m0, q0, q1, m1, top_col)


static func box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := center
	var v := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	quad(st, v[0], v[1], v[2], v[3], col)   # bottom
	quad(st, v[7], v[6], v[5], v[4], col)   # top
	quad(st, v[4], v[5], v[1], v[0], col)   # -z
	quad(st, v[6], v[7], v[3], v[2], col)   # +z
	quad(st, v[7], v[4], v[0], v[3], col)   # -x
	quad(st, v[5], v[6], v[2], v[1], col)   # +x


static func finish(st: SurfaceTool) -> ArrayMesh:
	return st.commit()


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## A snow-laden pine like the reference: a slim trunk and five tiers of
## foliage that narrow toward the tip, each tier dark teal below and snow
## on its upper shoulder.
static func pine() -> ArrayMesh:
	var st := begin()
	cone(st, 0.0, 0.16, 1.4, 0.12, 6, Palette.TRUNK)
	var tiers := [[1.0, 1.55, 2.3], [1.9, 1.3, 3.2], [2.8, 1.05, 4.0], [3.6, 0.78, 4.7], [4.3, 0.5, 5.4]]
	for i in tiers.size():
		var t: Array = tiers[i]
		var base_y: float = t[0]
		var r: float = t[1]
		var top_y: float = t[2]
		var col := Palette.PINE_DARK if i % 2 == 0 else Palette.PINE
		# Snow rests on the outer edge of each branch layer: white lower rim,
		# dark foliage above it. The tip of the tree is white too.
		var is_tip := i == tiers.size() - 1
		cone(st, base_y, r, top_y, 0.0, 7, Palette.PINE_SNOW, Palette.PINE_SNOW if is_tip else col, 0.28)
	return finish(st)


## A bare shrub with red berries, like the ones beside the trail in the reference.
static func shrub() -> ArrayMesh:
	var st := begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	cone(st, 0.0, 0.08, 0.8, 0.05, 5, Palette.BRANCH)
	for i in 7:
		var a := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(0.5, 1.1)
		var base := Vector3(0, 0.5 + rng.randf_range(0.0, 0.3), 0)
		var tip := base + Vector3(cos(a) * tilt, rng.randf_range(0.3, 0.7), sin(a) * tilt)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		quad(st, base - side, tip - side, tip + side, base + side, Palette.BRANCH)
		quad(st, base + side, tip + side, tip - side, base - side, Palette.BRANCH)
		box(st, tip, Vector3(0.14, 0.14, 0.14), Palette.BERRY if i % 2 == 0 else Palette.PINE_SNOW)
	return finish(st)


static func rock() -> ArrayMesh:
	var st := begin()
	cone(st, 0.0, 0.9, 0.5, 0.55, 6, Palette.ROCK_DARK, Palette.ROCK)
	cone(st, 0.5, 0.55, 0.85, 0.0, 6, Palette.ROCK, Palette.SNOW_SHADE)
	return finish(st)
