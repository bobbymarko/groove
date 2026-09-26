class_name CampWorld
extends RefCounted
## Shared dusk sky, fog and sun for anything that shows Camp in 3D.

const SKY_TOP := Color("3a3f96")
const SKY_MID := Color("9a6cc4")
const SKY_LOW := Color("ffa27a")


## Adds a WorldEnvironment and a sun to parent; returns the sun.
static func dusk(parent: Node, fog := true) -> DirectionalLight3D:
	var sky_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform vec3 top : source_color;
uniform vec3 mid : source_color;
uniform vec3 low : source_color;
void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(low, mid, smoothstep(0.0, 0.10, y));
	c = mix(c, top, smoothstep(0.10, 0.32, y));
	COLOR = c;
}
"""
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("top", SKY_TOP)
	sky_mat.set_shader_parameter("mid", SKY_MID)
	sky_mat.set_shader_parameter("low", SKY_LOW)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	if fog:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color("b39ad8")
		env.fog_density = 0.8
		env.fog_depth_begin = 6.0
		env.fog_depth_end = 140.0
		env.fog_depth_curve = 0.6
		env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffd2a0")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_bias = 0.6
	sun.shadow_normal_bias = 6.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.rotation_degrees = Vector3(-38, -35, 0)
	parent.add_child(sun)
	return sun
