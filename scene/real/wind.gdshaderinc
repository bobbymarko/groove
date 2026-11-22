// Shared by the realistic look's plants. Whole-plant sway grows with height
// (UV2.x, metres above the root); leaves flutter on top (UV2.y, 0 wood .. 1 leaf).
// The phase comes from where the plant stands, so neighbours move out of step.
// After Abyssal Garden (MIT, Noniv/abyssal-garden).
uniform float wind_strength = 1.0;
global uniform float rain_wet;   // 0 dry .. 1 soaked, eased by RealRain
global uniform vec3 eye_pos;     // the rider's eye, for per-plant level of detail (same in shadow passes)

// Level of detail, per plant: each version of a plant (close-up, middle,
// flat picture) is drawn between lod_in and lod_out metres from the eye, and
// neighbours crossfade by dithering (each keeps the pixels the other drops, so
// nothing doubles or gaps); everything dithers away toward far_end instead of
// popping (lod_drop's h is dither_moving at the pixel). far_z (strip rides) also fades by distance along the trail, where
// the ground itself ends.
uniform float lod_in = 0.0;        // this version fades in around here (0: from the eye)
uniform float lod_in_fade = 8.0;   // metres that handover takes
uniform float lod_out = 100000.0;  // and hands over to the next around here
uniform float lod_out_fade = 20.0;
uniform float far_end = 300.0;     // beyond this the plant is gone
uniform float far_fade = 60.0;
uniform float far_z = 100000.0;    // gone this far ahead along +z as well (fades over far_fade)
uniform float sway_end = 100000.0; // wind sway dies away over the 20 m before this

float plant_distance(mat4 model) {
	return distance(model[3].xyz, eye_pos);
}

// How far past its end a plant is, 0..1 (far_end by distance, far_z along the trail).
float far_gone(vec3 origin, float d) {
	float k = (d - (far_end - far_fade)) / far_fade;
	k = max(k, (abs(origin.z - eye_pos.z) - (far_z - far_fade)) / far_fade);
	return clamp(k, 0.0, 1.0);
}

// Wholly out of its range: the vertex shader folds the plant away to nothing.
bool lod_gone(float d, float gone) {
	return d < lod_in - lod_in_fade * 0.5 || d > lod_out + lod_out_fade * 0.5 || gone >= 1.0;
}

float dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
}

// The same pattern shifted every frame, so the TAA averages a
// crossfade into a smooth blend instead of a fixed screen-door. `still` (the
// sun's shadow maps): keep it fixed, or shadows would shimmer.
float dither_moving(vec2 frag, float t, bool still) {
	return dither(frag + (still ? 0.0 : 5.588238 * floor(mod(t * 60.0, 64.0))));
}

bool lod_drop(float d, float gone, float h) {
	if (h < clamp((d - (lod_out - lod_out_fade * 0.5)) / lod_out_fade, 0.0, 1.0)) {
		return true;
	}
	if (lod_in > 0.0 && h >= clamp((d - (lod_in - lod_in_fade * 0.5)) / lod_in_fade, 0.0, 1.0)) {
		return true;
	}
	return h < gone;
}

float sway_at(float d) {
	return 1.0 - smoothstep(sway_end - 20.0, sway_end, d);
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

// Wind on a plant, as an offset for a vertex h metres above the root.
// Gusts cross the land with the wind (as over the grass, real_grass): a plant
// leans downwind as one arrives and comes back as it passes, and rocks a
// little at its own pace on top, all of it in step up the stem (a stem bends,
// it does not snake). `flutter` (0 wood .. 1 the tip of a spray): boughs bob
// and leaves shiver, small and quick. Nothing drifts in slow circles: that
// reads as weed under water.
const vec2 WIND_DIR = vec2(0.94, 0.33);

float wind_gust(vec2 at, float t) {
	return 0.6 * vnoise(at * 0.013 - t * WIND_DIR * 0.035) + 0.4 * vnoise(at * 0.05 - t * WIND_DIR * 0.2);
}

vec3 wind_offset(vec3 origin, float h, float flutter, float t) {
	float ph = dot(origin.xz, vec2(0.31, 0.17));
	float gust = wind_gust(origin.xz, t);
	float a = 0.0035 * pow(max(h, 0.0), 1.25) * wind_strength;
	float rock = 0.6 * sin(t * 1.7 + ph) + 0.4 * sin(t * 2.9 + ph * 1.7);
	vec2 lean = WIND_DIR * a * (1.2 * gust + 0.35 * rock * (0.3 + gust))
			+ vec2(-WIND_DIR.y, WIND_DIR.x) * a * 0.25 * sin(t * 1.3 + ph * 2.3) * (0.3 + gust);
	vec3 off = vec3(lean.x, 0.0, lean.y);
	float live = flutter * wind_strength * (0.3 + gust);
	float bob = sin(t * 2.6 + h * 1.9 + ph * 5.0);
	off += live * 0.016 * vec3(WIND_DIR.x * bob, 0.7 * sin(t * 3.3 + h * 2.3 + ph * 3.0), WIND_DIR.y * bob);
	off += live * 0.005 * vec3(sin(t * 9.0 + h * 7.0 + ph * 11.0), sin(t * 11.0 + h * 5.0 + ph * 7.0), cos(t * 8.0 + h * 6.0 + ph * 9.0));
	return off;
}

