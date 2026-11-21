shader_type spatial;
render_mode cull_disabled;
// Frozen river and lake (winter): blue-grey ice with dark cracks, glossy
// where it is bare, drifted over with snow in patches.
#include "res://scene/real/wind.gdshaderinc"

uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float crack = 1.0 - smoothstep(0.0, 0.025, abs(vnoise(p * 0.45) - 0.5));
	crack = max(crack, 1.0 - smoothstep(0.0, 0.02, abs(vnoise(p * 1.3 + 7.0) - 0.5)) * 0.6);
	float drift = smoothstep(0.55, 0.78, vnoise(p * 0.08) * 0.7 + vnoise(p * 0.6) * 0.3);
	vec3 ice = vec3(0.3, 0.47, 0.6) * (0.85 + 0.25 * vnoise(p * 2.0)) * (1.0 - 0.45 * crack);
	ALBEDO = mix(ice, vec3(0.86, 0.89, 0.94), drift);
	ROUGHNESS = mix(0.08, 0.65, drift);
	SPECULAR = 0.6;
	NORMAL_MAP = texture(ripples, p * 0.04).xyz;
	NORMAL_MAP_DEPTH = mix(0.1, 0.5, drift);
}
