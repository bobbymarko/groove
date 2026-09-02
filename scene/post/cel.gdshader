shader_type spatial;
render_mode cull_back, specular_disabled;
// Two-band cel shading. Albedo comes from vertex colour (baked by the mesh
// builders) or a uniform for simple props.

uniform vec3 albedo : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform float shade_band = 0.72;
uniform float dark_band = 0.5;

varying vec3 vcol;

void vertex() {
	vcol = COLOR.rgb;
}

void fragment() {
	ALBEDO = use_vertex_color ? vcol : albedo;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = ndl > 0.3 ? 1.0 : (ndl > -0.15 ? shade_band : dark_band);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band;
}
