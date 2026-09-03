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
global uniform float cel_shade_band;
global uniform float cel_dark_band;
// Snow settles on surfaces that face up: world-normal Y above the threshold.
uniform float snow_threshold = 2.0;   // > 1 disables
uniform vec3 snow_color : source_color = vec3(0.93, 0.94, 0.97);

global uniform float cel_speckle;    // pixel texture on flat surfaces
global uniform float cel_bands;      // number of lighting steps (3 = 8-bit look, 6 = 16-bit)
global uniform float cel_colorize_steps;  // tonal steps for colourized textures
global uniform float cel_highlight;  // extra brightness where the sun hits squarely
uniform bool speckle = false;

varying vec3 vcol;
varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	vcol = COLOR.rgb;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 base = use_vertex_color ? vcol : albedo;
	if (use_texture) {
		vec4 t = texture(albedo_tex, UV);
		if (colorize) {
			float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
			// Hard tonal steps between the two shades: more internal detail than a blend.
			float steps = max(cel_colorize_steps, 2.0);
			float l = floor(smoothstep(0.1, 0.75, lum) * (steps - 0.001)) / (steps - 1.0);
			base = mix(shade_dark, shade_light, l);
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
	if (speckle && cel_speckle > 0.0) {
		// World-anchored so it does not swim with the camera; the palette snap
		// turns the modulation into scattered single-pixel tone changes.
		float n = hash3(floor(world_pos * 9.0));
		ALBEDO *= 1.0 + (n - 0.5) * cel_speckle;
	}
}

// In shadow the surface keeps shadow_band of the sun instead of dropping to
// ambient alone, so shadowed snow lands on the palette's blue snow-shadow
// rather than the dark pine tones.
global uniform float cel_shadow_band;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Quantize the lambert term into cel_bands steps from the dark band to full
	// light; squarely lit surfaces get the highlight on top.
	float bands = max(cel_bands, 2.0);
	float lit01 = clamp((ndl + 0.15) / 1.15, 0.0, 1.0);
	float q = floor(lit01 * (bands - 0.001)) / (bands - 1.0);
	float band = mix(cel_dark_band, 1.0, q) + (ndl > 0.82 ? cel_highlight : 0.0);
	float lit = mix(cel_shadow_band, band, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * lit;
}
