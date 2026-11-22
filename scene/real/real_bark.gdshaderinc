// Bark, from a scanned set (bark_pine, bark_oak or bark_birch; SurfaceTex),
// on the tube's own UV: x metres around, y metres along (PlantGen.tube), so
// a repeat is its real size on any trunk or limb. Colour, normal and
// roughness from the set, darkened in its crevices; a birch is the pale set
// brightened to white with dark lenticels and a black fissured foot. Snow on
// top of limbs, darker and glossier in rain, baked AO from COLOR.a. The live
// tree and its baked far picture (real_bark_bake) both come from here, so they
// match. Without the set (before tools/fetch-textures.sh) it falls back to noise.
#include "res://scene/real/wind.gdshaderinc"
#include "res://scene/real/bake.gdshaderinc"

uniform float birch = 0.0;
uniform float snow = 0.0;
uniform float moss = 0.0;          // deadwood: moss in patches on what faces up (logs, stumps)
uniform bool bark_tex = false;
uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 bark_tile = vec2(0.8, 0.8);         // metres around, along one repeat
uniform vec3 bark_ref = vec3(0.26, 0.21, 0.16);  // the vertex colour the set is shown untinted at

varying vec3 wn;
varying float circ;
varying float plant_d;
varying float gone;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The trunk's girth here, for hiding the seam where the UV's way round
	// meets its start (trunks stand on the model's origin; limbs never match it).
	circ = TAU * length(VERTEX.xz);
#ifndef BAKE
	plant_d = plant_distance(MODEL_MATRIX);
	vec3 origin = MODEL_MATRIX[3].xyz;
	gone = far_gone(origin, plant_d);
	if (lod_gone(plant_d, gone)) {
		VERTEX = vec3(0.0);
	} else {
#ifndef STILL
		VERTEX += wind_offset(origin, UV2.x, UV2.y, TIME) * sway_at(plant_d);
#endif
	}
#endif
}

void fragment() {
#ifndef BAKE
	if (lod_drop(plant_d, gone, dither_moving(FRAGCOORD.xy, TIME, PROJECTION_MATRIX[3][3] > 0.5))) {
		discard;
	}
#endif
	vec2 p = UV;
	vec3 alb;
	float rough = 0.9;
	vec3 tn = vec3(0.0, 0.0, 1.0);    // tangent-space normal (x around, y along)
	float s = snow * smoothstep(0.45, 0.85, wn.y);
	if (bark_tex) {
		vec2 uv = p / bark_tile;
		vec4 a = texture(bark_albedo, uv);
		vec4 nm = texture(bark_normal, uv);
		vec4 arm = texture(bark_arm, uv);
		float h = texture(bark_height, uv).r;
		// Near the end of the way round, fade into the texture as it carries on from the start.
		float k = smoothstep(0.82, 1.0, p.x / max(circ, 1e-3)) * step(p.x, circ * 1.08);
		if (k > 0.0) {
			vec2 uv2 = vec2(p.x - circ, p.y) / bark_tile;
			a = mix(a, texture(bark_albedo, uv2), k);
			nm = mix(nm, texture(bark_normal, uv2), k);
			arm = mix(arm, texture(bark_arm, uv2), k);
			h = mix(h, texture(bark_height, uv2).r, k);
		}
		tn = vec3(nm.xy * 2.0 - 1.0, 0.0);
		tn.z = sqrt(max(1.0 - dot(tn.xy, tn.xy), 0.0));
		rough = arm.g;
		if (birch > 0.5) {
			// Paper-white bark: the scan's cracks, brightened and its green cast taken out.
			float l = dot(a.rgb, vec3(0.3, 0.55, 0.15));
			alb = vec3(0.74, 0.73, 0.69) * pow(clamp(l / 0.32, 0.0, 1.6), 0.6) * mix(0.75, 1.0, h);
			// Lenticels: thin dark dashes running round the trunk, in loose groups.
			float group = smoothstep(0.35, 0.7, vnoise(vec2(p.x * 2.6, p.y * 5.0)));
			float dash = smoothstep(0.74, 0.84, vnoise(vec2(p.x * 9.0, p.y * 64.0) + 3.0)) * group;
			// Big dark scars and the black fissured foot of an old birch.
			float scar = smoothstep(0.8, 0.86, vnoise(vec2(p.x * 1.6, p.y * 3.2) + 11.0));
			float foot = smoothstep(1.5, 0.3, UV2.x + (vnoise(vec2(p.x * 3.0, 0.5)) - 0.5) * 0.7);
			float dark = max(max(dash * 0.9, scar * 0.85), foot * smoothstep(0.62, 0.38, h));
			alb = mix(alb, vec3(0.05, 0.045, 0.04) * (0.7 + 0.6 * h), dark);
			rough = mix(0.55, 0.95, dark);
			tn.xy *= mix(0.45, 1.3, dark);
		} else {
			alb = a.rgb * (COLOR.rgb / bark_ref) * vec3(1.08, 1.0, 0.88) * mix(0.5, 1.12, h) * mix(0.55, 1.0, arm.r);
		}
		tn.xy *= 1.0 - s * 0.8;
	} else {
		float furrow = vnoise(vec2(p.x * 14.0, p.y * 1.6));
		float fine = vnoise(p * vec2(40.0, 9.0));
		alb = COLOR.rgb * (0.55 + 0.6 * furrow) * (0.8 + 0.35 * fine);
		if (birch > 0.5) {
			float band = smoothstep(0.72, 0.8, vnoise(vec2(p.x * 5.0, p.y * 9.0)));
			float base = smoothstep(1.8, 0.4, UV2.x);
			alb = mix(vec3(0.82, 0.8, 0.76) * (0.9 + 0.15 * fine), vec3(0.08, 0.07, 0.06), max(band, base * 0.8));
		}
		tn = normalize(vec3((furrow - 0.5) * 0.6, 0.0, 1.0));
	}
	if (moss > 0.0) {
		float mp = vnoise(p * vec2(3.1, 1.3)) * 0.65 + vnoise(p * vec2(11.0, 7.0) + 4.0) * 0.35;
		float mk = smoothstep(0.42, 0.58, wn.y * 0.55 + mp * 0.75 + (moss - 0.6) * 0.4 - 0.22);
		alb = mix(alb, vec3(0.07, 0.115, 0.03) * (0.6 + 0.8 * mp), mk * 0.9);
		rough = mix(rough, 0.95, mk);
		tn.xy *= 1.0 - mk * 0.6;
	}
	alb = mix(alb, vec3(0.88, 0.9, 0.95), s);
	ALBEDO = alb * mix(0.35, 1.0, COLOR.a);
#ifdef BAKE
	ALBEDO = bake_out(ALBEDO, normalize(NORMAL), COLOR.a, 0.0);
#else
	ALBEDO *= mix(1.0, 0.62, rain_wet);
	ROUGHNESS = mix(mix(rough, 0.7, s), 0.4, rain_wet);
	SPECULAR = 0.3;
	// A tangent frame from the screen derivatives (the tubes carry no tangents):
	// x along increasing UV.x (round), y along increasing UV.y (along).
	vec3 n = normalize(NORMAL);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 du1 = dFdx(p);
	vec2 du2 = dFdy(p);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 T = dp2perp * du1.x + dp1perp * du2.x;
	vec3 B = dp2perp * du1.y + dp1perp * du2.y;
	float inv = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
	// The scans are OpenGL normal maps (green up the picture, i.e. toward lower UV.y).
	NORMAL = normalize(T * inv * tn.x - B * inv * tn.y + n * tn.z);
	// UV2.x: metres above the root; the foot of the trunk darkens into the soil.
	Shade sh = shade_plant((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, length(VERTEX), UV2.x, 0.4, 0.4, 1.2);
	SHADE_APPLY(sh)
#endif
}
