// Shared by the realistic look's plants. Whole-plant sway grows with height
// (UV2.x, metres above the root); leaves flutter on top (UV2.y, 0 wood .. 1 leaf).
// The phase comes from where the plant stands, so neighbours move out of step.
// After Abyssal Garden (MIT, Noniv/abyssal-garden).
uniform float wind_strength = 1.0;
global uniform float rain_wet;   // 0 dry .. 1 soaked, eased by RealRain

vec3 wind_offset(vec3 origin, float h, float flutter, float t) {
	float ph = dot(origin.xz, vec2(0.31, 0.17));
	float a = 0.006 * pow(max(h, 0.0), 1.25) * wind_strength;
	vec2 drift = a * (vec2(sin(t * 0.5 + ph + h * 0.09), cos(t * 0.37 + ph * 1.3 + h * 0.07))
			+ 0.35 * vec2(sin(t * 1.3 + ph * 3.0 + h * 0.3), cos(t * 1.1 + ph * 2.0 + h * 0.23)));
	vec3 off = vec3(drift.x, 0.0, drift.y);
	off += flutter * 0.012 * wind_strength * vec3(sin(t * 4.1 + h * 3.0 + ph * 7.0), sin(t * 5.3 + h * 2.1 + ph * 3.0) * 0.6, cos(t * 4.6 + h * 2.7 + ph * 5.0));
	return off;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
