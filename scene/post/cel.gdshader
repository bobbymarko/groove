shader_type spatial;
render_mode cull_back, specular_disabled;
// Two-band cel shading. Albedo comes from vertex colour (baked by the mesh
// builders) or a uniform for simple props.

uniform vec3 albedo : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform float shade_band = 0.72;
uniform float dark_band = 0.5;
// Snow settles on surfaces that face up: world-normal Y above the threshold.
uniform float snow_threshold = 2.0;   // > 1 disables
uniform vec3 snow_color : source_color = vec3(0.93, 0.94, 0.97);

varying vec3 vcol;
varying vec3 world_normal;

void vertex() {
	vcol = COLOR.rgb;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 base = use_vertex_color ? vcol : albedo;
	float up = normalize(world_normal).y;
	ALBEDO = up > snow_threshold ? snow_color : base;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = ndl > 0.3 ? 1.0 : (ndl > -0.15 ? shade_band : dark_band);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band;
}
