shader_type spatial;
// Rock: layered noise on the rock's own coordinates (so each instance differs
// by where it sits), cavities darker from the baked AO, snow caps.
#include "res://scene/real/wind.gdshaderinc"

uniform float snow = 0.0;
uniform vec3 moss = vec3(0.12, 0.16, 0.06);
uniform float moss_amount = 0.0;

varying vec3 lp;
varying vec3 wn;

void vertex() {
	lp = VERTEX + MODEL_MATRIX[3].xyz * 0.37;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = abs(wn);
	w = pow(w, vec3(4.0));
	w /= (w.x + w.y + w.z);
	float n1 = vnoise(lp.yz * 3.0) * w.x + vnoise(lp.xz * 3.0) * w.y + vnoise(lp.xy * 3.0) * w.z;
	float n2 = vnoise(lp.yz * 13.0) * w.x + vnoise(lp.xz * 13.0) * w.y + vnoise(lp.xy * 13.0) * w.z;
	float strata = vnoise(vec2(lp.y * 6.0 + n1 * 2.0, 0.5));
	vec3 alb = COLOR.rgb * (0.6 + 0.5 * n1) * (0.8 + 0.35 * n2) * (0.85 + 0.25 * strata);
	float up = smoothstep(0.5, 0.85, wn.y);
	alb = mix(alb, moss * (0.7 + 0.6 * n2), moss_amount * up * smoothstep(0.4, 0.6, n1));
	alb = mix(alb, vec3(0.88, 0.9, 0.95), snow * smoothstep(0.35, 0.7, wn.y + (n2 - 0.5) * 0.4));
	ALBEDO = alb * mix(0.3, 1.0, COLOR.a);
	ALBEDO *= mix(1.0, 0.65, rain_wet);
	ROUGHNESS = mix(0.85, 0.25, rain_wet);
	SPECULAR = 0.3;
	NORMAL_MAP = normalize(vec3(0.5 + (n2 - 0.5) * 0.5, 0.5 + (n1 - 0.5) * 0.3, 1.0));
	NORMAL_MAP_DEPTH = 2.0;
}
