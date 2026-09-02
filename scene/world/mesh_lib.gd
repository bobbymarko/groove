class_name MeshLib
extends RefCounted
## Builds flat-shaded, vertex-coloured low-poly meshes for props. Every face
## gets its own vertices so normals stay hard, which is what the pixel look wants.

static func cel_material(vertex_color := true, albedo := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scene/post/cel.gdshader")
	m.set_shader_parameter("use_vertex_color", vertex_color)
	m.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
	return m


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
static func cone(st: SurfaceTool, y0: float, r0: float, y1: float, r1: float, sides: int, col: Color, col_top := Color.TRANSPARENT) -> void:
	var top_col := col if col_top == Color.TRANSPARENT else col_top
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		if r1 <= 0.001:
			tri(st, p0, q0, p1, col)
		else:
			# Split so the upper half can carry snow colour.
			var m0 := (p0 + q0) * 0.5
			var m1 := (p1 + q1) * 0.5
			quad(st, p0, m0, m1, p1, col)
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


## A snow-laden pine: trunk plus three stacked cones, snow on the upper half of each tier.
static func pine() -> ArrayMesh:
	var st := begin()
	cone(st, 0.0, 0.18, 1.2, 0.14, 6, Palette.TRUNK)
	cone(st, 0.9, 1.5, 2.6, 0.0, 7, Palette.PINE_DARK, Palette.PINE_SNOW)
	cone(st, 2.1, 1.15, 3.6, 0.0, 7, Palette.PINE, Palette.PINE_SNOW)
	cone(st, 3.2, 0.75, 4.6, 0.0, 6, Palette.PINE, Palette.PINE_SNOW)
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
