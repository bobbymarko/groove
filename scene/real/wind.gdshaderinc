// Shared by the realistic look's plants. Whole-plant sway grows with height
// (UV2.x, metres above the root); leaves flutter on top (UV2.y, 0 wood .. 1 leaf).
// The phase comes from where the plant stands, so neighbours move out of step.
// After Abyssal Garden (MIT, Noniv/abyssal-garden).
uniform float wind_strength = 1.0;
global uniform float rain_wet;   // 0 dry .. 1 soaked, eased by RealRain
global uniform vec3 eye_pos;     // the rider's eye, for per-plant level of detail (same in shadow passes)

// Level of detail, per plant: a tree's close-up and distant versions crossfade
// by dithering (each keeps the pixels the other drops, so nothing doubles or
// gaps), and everything dithers away toward its far end instead of popping.
uniform int lod_role = 2;          // 0 close-up version, 1 distant version, 2 the only version
uniform float lod_range = 80.0;    // where close-up hands over to distant
uniform float lod_fade = 20.0;     // metres the handover takes
uniform float far_end = 300.0;     // beyond this the plant is gone
uniform float far_fade = 60.0;

float plant_distance(mat4 model) {
	return distance(model[3].xyz, eye_pos);
}

bool lod_drop(float d, vec2 frag) {
	float h = fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
	float k = clamp((d - (lod_range - lod_fade * 0.5)) / lod_fade, 0.0, 1.0);
	if (lod_role == 0) {
		return h < k;
	}
	if (lod_role == 1 && h >= k) {
		return true;
	}
	return h < clamp((d - (far_end - far_fade)) / far_fade, 0.0, 1.0);
}

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
