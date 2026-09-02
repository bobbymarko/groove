shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Two-band cel shading. Albedo comes from vertex colour (baked by the mesh
// builders) or a uniform for simple props.

uniform vec3 albedo : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform bool use_texture = false;
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform bool alpha_cutout = false;
// Colourize: texture brightness picks between two palette shades instead of
// using the texture's own hues, so imported props stay inside the palette.
uniform bool colorize = false;
uniform vec3 shade_dark : source_color = vec3(0.12, 0.23, 0.27);
uniform vec3 shade_light : source_color = vec3(0.30, 0.49, 0.55);
uniform float shade_band = 0.66;
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
	if (use_texture) {
		vec4 t = texture(albedo_tex, UV);
		if (colorize) {
			float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
			base = mix(shade_dark, shade_light, smoothstep(0.12, 0.7, lum));
		} else {
			base = t.rgb * albedo;
		}
		if (alpha_cutout) {
			ALPHA = t.a;
			ALPHA_SCISSOR_THRESHOLD = 0.5;
		}
	}
	float up = normalize(world_normal).y;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = up > snow_threshold ? snow_color : base;
}

// In shadow the surface keeps shadow_band of the sun instead of dropping to
// ambient alone, so shadowed snow lands on the palette's blue snow-shadow
// rather than the dark pine tones.
uniform float shadow_band = 0.58;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = ndl > 0.3 ? 1.0 : (ndl > -0.15 ? shade_band : dark_band);
	float lit = mix(shadow_band, band, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * lit;
}
