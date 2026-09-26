class_name CampLook
extends RefCounted
## Materials and lighting mood for everything in Camp. One shader, one
## material per colour, shared lighting uniforms so a time-of-day change
## reaches every surface.

const SHADER := preload("res://camp/shaders/lowpoly.gdshader")
const GLOW_ROLES := ["glow", "lamp", "flame", "flame2", "flame3", "ember"]

## Default role colours; riders override the ones they care about.
const ROLES := {
	"primary": Color("7a45c8"), "secondary": Color("4d2a8c"), "accent": Color("ef6a01"),
	"eye": Color("f2eee4"), "pupil": Color("141214"), "mouth": Color("2b0d20"),
	"teeth": Color("f5eeda"), "horn": Color("e6d0a2"), "dark": Color("222326"),
	"sole": Color("ece6d8"), "metal": Color("8b98a6"), "screen": Color("0a1a22"),
	"glow": Color("33f0ff"), "cap": Color("d93a2e"), "cloth": Color("233459"),
	"frame": Color("ef6a01"), "tyre": Color("1b1b1d"), "rim": Color("3a3a40"),
	"chrome": Color("b4b8be"), "saddle": Color("222024"), "grip": Color("1e1e1e"),
	"leaf": Color("2f6b45"), "leaf_dark": Color("1f4a3a"), "bark": Color("5c3a28"),
	"rock": Color("77778a"), "snow": Color("eeeef6"), "mountain": Color("5b5486"),
	"berry": Color("c0184a"), "grass": Color("6a9444"), "cloud": Color("f7b7a8"),
	"dirt": Color("8c5a36"), "limb": Color("7a45c8"),
	"beard": Color("f0ece2"), "ember": Color("ff7a1a"), "flame": Color("ff6a14"),
	"flame2": Color("ffb62e"), "flame3": Color("fff0b0"), "lamp": Color("ffcf7a"),
	"paint": Color("5d8a62"), "paint2": Color("efe6cf"), "glass": Color("2a3550"),
	"trim": Color("2a2a2e"), "wood": Color("a8764c"), "wood_dark": Color("664430"),
	"canvas": Color("d9a35a"), "blanket": Color("c0392e"), "blanket2": Color("efe2c4"),
	"box1": Color("4d6b4d"), "box2": Color("c8573a"), "jam": Color("8c1640"),
	"stone": Color("80808c"), "mug": Color("eee6d6"), "water": Color("6674c0"),
}

## Dusk, as on the camp title board.
static var mood := {
	"sky": Color("7466d0"), "ground": Color("6a3a58"), "ambient": 0.42,
	"rim_color": Color("ff9a66"), "rim": 0.55,
}

static var _cache: Dictionary = {}
static var _double: Shader


## Two-sided variant for generated meshes (limbs), whose winding varies.
static func limb_material(c: Color) -> ShaderMaterial:
	var key := "limb/" + c.to_html(false)
	if _cache.has(key):
		return _cache[key]
	if _double == null:
		_double = Shader.new()
		_double.code = SHADER.code.replace("specular_disabled;", "specular_disabled, cull_disabled;")
	var m := ShaderMaterial.new()
	m.shader = _double
	m.set_shader_parameter("albedo", c)
	_apply_mood(m)
	_cache[key] = m
	return m


static func material(c: Color, glow := 0.0) -> ShaderMaterial:
	var key := "%s/%.2f" % [c.to_html(false), glow]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("glow", glow)
	_apply_mood(m)
	_cache[key] = m
	return m


static func set_mood(values: Dictionary) -> void:
	mood.merge(values, true)
	for m in _cache.values():
		_apply_mood(m)


static func _apply_mood(m: ShaderMaterial) -> void:
	for k in mood:
		m.set_shader_parameter(k, mood[k])


## Recolour every surface of a mesh instance (and its mesh children) by the
## role name its Blender material carried.
static func paint(node: Node, colours: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var role := src.resource_name if src else "primary"
			var c: Color = colours.get(role, ROLES.get(role, Color.MAGENTA))
			mi.set_surface_override_material(i, material(c, 1.0 if role in GLOW_ROLES else 0.0))
	for child in node.get_children():
		paint(child, colours)
