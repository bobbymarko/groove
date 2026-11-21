shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;
// River and lake water for the realistic look. Drawn whole by this shader:
// the bed seen through the water (bent by the ripples, sinking into the deep
// colour with depth), reflections traced across the screen (trees, hills,
// clouds; the sky colour where the ray finds nothing), Fresnel between the
// two, a sun glint, ripples drifting with the current, foam where it is shallow.
#include "res://scene/real/wind.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep = vec3(0.012, 0.045, 0.05);
uniform vec3 shallow = vec3(0.62, 0.78, 0.72);   // what the water does to the bed's colour
uniform float flow = 0.35;
global uniform vec3 water_sky;   // sky colour for reflections that leave the screen (RealLook, by time of day)
global uniform vec3 sun_dir;     // toward the sun or moon

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scene_dist(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 p = wp.xz;
	vec3 n1 = texture(ripples, p * 0.07 + vec2(0.0, TIME * flow * 0.07)).xyz * 2.0 - 1.0;
	vec3 n2 = texture(ripples, p * 0.19 + vec2(TIME * 0.012, TIME * flow * 0.19)).xyz * 2.0 - 1.0;
	vec3 nw = normalize(vec3((n1.x + n2.x) * 0.16, 1.0, (n1.y + n2.y) * 0.16));
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 vdir = normalize(VERTEX);
	float water_d = -VERTEX.z;
	float thick = max(scene_dist(SCREEN_UV, INV_PROJECTION_MATRIX) - water_d, 0.0);

	// The bed, bent by the surface (never pulling in what stands in front of the water).
	vec2 ruv = SCREEN_UV + nv.xy * 0.025 * clamp(thick, 0.0, 1.0);
	if (scene_dist(ruv, INV_PROJECTION_MATRIX) < water_d) {
		ruv = SCREEN_UV;
	}
	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 body = mix(below * shallow, deep, 1.0 - exp(-thick * 0.6));

	// Reflection: march the mirrored ray across the screen.
	vec3 r = reflect(vdir, nv);
	vec3 rw = (INV_VIEW_MATRIX * vec4(r, 0.0)).xyz;
	vec3 refl = water_sky * mix(0.75, 1.15, clamp(rw.y, 0.0, 1.0));
	vec3 pos = VERTEX;
	float stepl = 0.35;
	for (int i = 0; i < 30; i++) {
		pos += r * stepl;
		stepl *= 1.22;
		vec4 c = PROJECTION_MATRIX * vec4(pos, 1.0);
		if (c.w <= 0.0) {
			break;
		}
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		float sd = scene_dist(uv, INV_PROJECTION_MATRIX);
		if (-pos.z > sd && -pos.z - sd < stepl * 1.5 + 0.4) {
			float edge = smoothstep(0.0, 0.08, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
			refl = mix(refl, textureLod(screen_tex, uv, 0.0).rgb, edge);
			break;
		}
	}
	float fres = 0.02 + 0.98 * pow(1.0 - max(dot(-vdir, nv), 0.0), 5.0);
	vec3 col = mix(body, refl, clamp(fres, 0.0, 1.0));
	vec3 lv = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	col += vec3(1.0, 0.95, 0.85) * pow(max(dot(r, lv), 0.0), 700.0) * 5.0 * smoothstep(-0.05, 0.1, sun_dir.y);
	float foam = (1.0 - smoothstep(0.0, 0.3, thick)) * (0.4 + 0.6 * vnoise(p * 4.0 + vec2(0.0, TIME * flow)));
	col = mix(col, vec3(0.8, 0.83, 0.82) * length(water_sky), foam * 0.45);
	ALBEDO = col;
	ALPHA = 1.0;
}
