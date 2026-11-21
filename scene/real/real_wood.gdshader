shader_type spatial;
render_mode cull_disabled;
// Bridges: weathered timber with grain along each piece's length (UV.x runs
// along it, in metres), stone where COLOR.a is 0. Darkens in rain, takes
// snow on top in winter.

#include "res://scene/real/wind.gdshaderinc"

uniform float snow = 0.0;

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 col = COLOR.rgb;
	float rough;
	if (COLOR.a > 0.5) {
		float grain = vnoise(vec2(UV.x * 0.9, UV.y * 38.0)) * 0.6 + vnoise(vec2(UV.x * 3.1, UV.y * 90.0)) * 0.4;
		float knots = smoothstep(0.82, 0.9, vnoise(UV * vec2(2.3, 9.0) + 4.0));
		col *= (0.72 + 0.45 * grain) * (1.0 - 0.35 * knots);
		col = mix(col, vec3(0.32, 0.33, 0.3) * (0.8 + 0.3 * grain), 0.25 * vnoise(UV * 0.7));   // silvered by weather
		rough = 0.88;
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
	ALBEDO = col;
	ROUGHNESS = rough;
}
