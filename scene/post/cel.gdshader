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
global uniform float cel_texture_mix;     // how much of the real texture detail shows through the tint (16-bit)
uniform bool prop = false;                 // imported prop: fine speckle, mottled snow
uniform bool smooth_lighting = false;     // terrain: continuous lambert when cel_smooth_terrain is set (16-bit)
// Body mesh: recolour skin by region so the rider wears sleeves and pants.
// Zones are in model space (rider local, metres): legs below the saddle, arms
// out from the torso, hands forward on the bars, head above the shoulders.
uniform bool body_zones = false;
uniform vec3 sleeve_dark : source_color = vec3(0.56, 0.13, 0.16);
uniform vec3 sleeve_light : source_color = vec3(0.78, 0.2, 0.23);
uniform vec3 pants_dark : source_color = vec3(0.11, 0.2, 0.44);
uniform vec3 pants_light : source_color = vec3(0.17, 0.29, 0.6);
global uniform float cel_smooth_terrain;
global uniform float cel_prop_snow;         // snow threshold for props (lower = more snow)
global uniform float cel_highlight;  // extra brightness where the sun hits squarely
uniform bool speckle = false;

varying vec3 vcol;
varying vec3 world_normal;
varying vec3 world_pos;
varying vec3 model_pos;

void vertex() {
	vcol = COLOR.rgb;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	model_pos = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 base = use_vertex_color ? vcol : albedo;
	float tex_lum = 0.5;
	if (use_texture) {
		vec4 t = texture(albedo_tex, UV);
		tex_lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		if (colorize) {
			vec3 dark = shade_dark;
			vec3 light = shade_light;
			if (body_zones) {
				bool hand = model_pos.z > 0.38 && model_pos.y < 1.2 && model_pos.y > 0.9;
				bool head = model_pos.y > 1.38 && abs(model_pos.x) < 0.16;
				if (!hand && !head) {
					if (model_pos.y < 1.0) {
						dark = pants_dark; light = pants_light;
					} else {
						dark = sleeve_dark; light = sleeve_light;
					}
				}
			}
			// Hard tonal steps between the two shades: more internal detail than a blend.
			float steps = max(cel_colorize_steps, 2.0);
			float l = floor(smoothstep(0.1, 0.75, tex_lum) * (steps - 0.001)) / (steps - 1.0);
			base = mix(dark, light, l);
			// Let the texture's brightness detail through without its hue, so the
			// palette colour holds while needles and bark keep their grain.
			vec3 detail = mix(dark, light, clamp(tex_lum * 1.4, 0.0, 1.0));
			base = mix(base, detail, cel_texture_mix);
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
	// Snow on upward faces; on props the texture's bright spots catch it first,
	// so it sits in mottled patches rather than along a hard line.
	float snow_up = prop ? up + (tex_lum - 0.3) * 0.45 : up;   // bright needles catch snow first
	float thr = (prop && snow_threshold < 1.5) ? cel_prop_snow : snow_threshold;
	ALBEDO = snow_up > thr ? snow_color : base;
	if ((speckle || prop) && cel_speckle > 0.0) {
		// World-anchored so it does not swim with the camera; the palette snap
		// turns the modulation into scattered single-pixel tone changes.
		float cells = prop ? 60.0 : 24.0;   // props: ~1.7 cm cells for needle texture
		float n = hash3(floor(world_pos * cells));
		ALBEDO *= 1.0 + (n - 0.5) * cel_speckle * (prop ? 1.6 : 1.0);
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
	if (smooth_lighting && cel_smooth_terrain > 0.5) {
		q = lit01;   // no steps: the ground shades as a continuous gradient
	}
	float band = mix(cel_dark_band, 1.0, q) + (ndl > 0.82 ? cel_highlight * (smooth_lighting && cel_smooth_terrain > 0.5 ? smoothstep(0.7, 0.95, ndl) : 1.0) : 0.0);
	if (LIGHT_IS_DIRECTIONAL) {
		// Sun or moon: ATTENUATION is the shadow term; shadowed surfaces keep the shadow band.
		float lit = mix(cel_shadow_band, band, ATTENUATION);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * lit;
	} else {
		// Spot and omni lights (the bar light): cone and distance falloff apply fully.
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * ATTENUATION;
	}
}
