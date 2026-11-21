shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
// Distant mountains: lit by the sun (global sun_dir) and the sky, coloured by
// height and slope (rock, scrub, snow above the snow line), then hazed toward
// the sky's colour with distance the way far ranges turn blue-violet.
#include "res://scene/real/wind.gdshaderinc"

uniform vec3 rock = vec3(0.36, 0.3, 0.27);
uniform vec3 scrub = vec3(0.22, 0.24, 0.14);
uniform float snow_line = 9999.0;
uniform float haze = 0.5;
uniform float light = 1.0;   // set by RealLook with the time of day
global uniform vec3 water_sky;
global uniform vec3 sun_dir;

varying vec3 wp;
varying vec3 wn;
varying float h;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	h = VERTEX.y;
}

void fragment() {
	float n = vnoise(wp.xz * 0.004) * 0.6 + vnoise(wp.xz * 0.02) * 0.4;
	float steep = 1.0 - wn.y;
	vec3 alb = mix(scrub, rock, smoothstep(0.25, 0.55, steep + (n - 0.5) * 0.3));
	alb = mix(alb, vec3(0.9, 0.92, 0.96), smoothstep(snow_line, snow_line + 120.0, h + (n - 0.5) * 220.0) * (1.0 - smoothstep(0.55, 0.8, steep)));
	float lit = max(dot(wn, sun_dir), 0.0) * smoothstep(-0.05, 0.1, sun_dir.y);
	vec3 col = alb * (lit * 2.6 + 0.45) * light;
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float k = haze * smoothstep(1500.0, 9000.0, d) + 0.15;
	ALBEDO = mix(col, water_sky * 1.05, clamp(k, 0.0, 0.9));
}
