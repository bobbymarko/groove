shader_type spatial;
// Bark: vertical furrows (or a birch's white with dark bands) from the tube's
// UV, metres around and along; baked AO from COLOR.a; snow on top of limbs.
#include "res://scene/real/wind.gdshaderinc"

uniform float birch = 0.0;
uniform float snow = 0.0;

varying vec3 wn;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	VERTEX += wind_offset(origin, UV2.x, UV2.y, TIME);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = UV;
	float furrow = vnoise(vec2(p.x * 14.0, p.y * 1.6));
	float fine = vnoise(p * vec2(40.0, 9.0));
	vec3 alb = COLOR.rgb * (0.55 + 0.6 * furrow) * (0.8 + 0.35 * fine);
	if (birch > 0.5) {
		float band = smoothstep(0.72, 0.8, vnoise(vec2(p.x * 5.0, p.y * 9.0)));
		float base = smoothstep(1.8, 0.4, p.y);
		alb = mix(vec3(0.82, 0.8, 0.76) * (0.9 + 0.15 * fine), vec3(0.08, 0.07, 0.06), max(band, base * 0.8));
	}
	float s = snow * smoothstep(0.45, 0.85, wn.y);
	alb = mix(alb, vec3(0.88, 0.9, 0.95), s);
	ALBEDO = alb * mix(0.35, 1.0, COLOR.a);
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	NORMAL_MAP = normalize(vec3(0.5 + (furrow - 0.5) * 0.6, 0.5, 1.0));
	NORMAL_MAP_DEPTH = 1.5;
}
