shader_type spatial;
render_mode cull_disabled;
// Bridges: weathered timber from the plank scan (SurfaceTex "wood_planks"),
// the grain along each piece (UV.x runs along it, in metres). Each piece shows
// one board of the scan (UV2.y picks which; UV2.x runs across it, kept clear of
// the gaps between boards), so a deck board never shows a seam down its
// middle. Stone where COLOR.a is 0. Darkens in rain, takes snow on top in winter.
// Without the scan (before tools/fetch-textures.sh) the grain is noise.

#include "res://scene/real/wind.gdshaderinc"

uniform float snow = 0.0;
uniform bool wood_tex = false;
uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wood_gain = 1.0;          // brings the scan to the timber's albedo
const float BOARDS = 13.0;              // boards across one repeat of the scan
const float TILE = 1.8;                 // metres one repeat covers

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 col = COLOR.rgb;
	float rough;
	vec3 tn = vec3(0.0, 0.0, 1.0);
	vec2 uv = vec2(UV.x / TILE, (floor(UV2.y * BOARDS) + UV2.x * 0.34) / BOARDS);
	if (COLOR.a > 0.5) {
		if (wood_tex) {
			vec3 a = texture(wood_albedo, uv).rgb;
			vec2 nm = texture(wood_normal, uv).rg * 2.0 - 1.0;
			vec3 arm = texture(wood_arm, uv).rgb;
			col = a * wood_gain * (COLOR.rgb / vec3(0.42, 0.3, 0.2)) * mix(0.6, 1.0, arm.r);
			col = mix(col, vec3(0.3, 0.3, 0.28) * dot(a, vec3(0.33)) * 2.5 * wood_gain, 0.25 * vnoise(UV * 0.7));   // silvered by weather
			rough = arm.g;
			tn = vec3(nm, sqrt(max(1.0 - dot(nm, nm), 0.0)));
		} else {
			float grain = vnoise(vec2(UV.x * 0.9, UV.y * 38.0)) * 0.6 + vnoise(vec2(UV.x * 3.1, UV.y * 90.0)) * 0.4;
			float knots = smoothstep(0.82, 0.9, vnoise(UV * vec2(2.3, 9.0) + 4.0));
			col *= (0.72 + 0.45 * grain) * (1.0 - 0.35 * knots);
			col = mix(col, vec3(0.32, 0.33, 0.3) * (0.8 + 0.3 * grain), 0.25 * vnoise(UV * 0.7));   // silvered by weather
			rough = 0.88;
		}
	} else {
		float sp = vnoise(UV * 5.0) * 0.5 + vnoise(UV * 17.0) * 0.5;
		col *= 0.7 + 0.5 * sp;
		col = mix(col, vec3(0.16, 0.2, 0.1), smoothstep(0.62, 0.8, vnoise(UV * 1.3 + 7.0)) * 0.5);  // moss
		rough = 0.92;
	}
	col *= mix(1.0, 0.6, rain_wet);
	rough = mix(rough, 0.4, rain_wet);
	float cover = snow * smoothstep(0.5, 0.8, wn.y) * (0.75 + 0.25 * vnoise(UV * 4.0));
	col = mix(col, vec3(0.88, 0.9, 0.95), cover);
	rough = mix(rough, 0.6, cover);
	tn.xy *= 1.0 - cover;
	ALBEDO = col;
	ROUGHNESS = rough;
	if (wood_tex) {
		// Tangent frame from the screen derivatives of the scan's own coordinates.
		vec3 n = normalize(NORMAL);
		vec3 dp1 = dFdx(VERTEX);
		vec3 dp2 = dFdy(VERTEX);
		vec2 du1 = dFdx(uv);
		vec2 du2 = dFdy(uv);
		vec3 dp2perp = cross(dp2, n);
		vec3 dp1perp = cross(n, dp1);
		vec3 T = dp2perp * du1.x + dp1perp * du2.x;
		vec3 B = dp2perp * du1.y + dp1perp * du2.y;
		float inv = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
		NORMAL = normalize(T * inv * tn.x - B * inv * tn.y + n * tn.z);
	}
}
