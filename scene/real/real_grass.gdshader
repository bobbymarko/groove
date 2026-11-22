shader_type spatial;
render_mode cull_disabled;
// The meadow (RealGrass). Every instance is one tuft's slot on a fixed grid in
// the world; the whole tuft is made here from that slot's coordinates: where
// it roots (jittered), how tall, which way it leans, whether it carries a
// flower. The ground comes from the "field" texture RealGrass keeps round the
// eye (height, distance from the trail, how thick grass grows, which biome).
// Blades take the ground's normal, not their own, so the meadow is lit like
// the land under it; their roots take the ground shader's colour at that spot,
// so gaps between tufts vanish; wind crosses the field as gusts of a
// scrolling noise. Tufts thin out with distance by shrinking away one by one
// (each has a rank), never popping.

global uniform float rain_wet;
global uniform vec3 eye_pos;

uniform sampler2D field : filter_linear, repeat_enable;       // r height, g metres from the trail's middle, b density, a biome index
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;   // the ground shader's noise
uniform float field_size = 128.0;      // texels across (one metre each)
uniform float pitch = 0.25;            // metres between tuft slots
uniform float fade_in = 0.0;           // this ring of tufts grows in over the metres before here (0: from the eye)
uniform float fade_out = 9.0;          // and has shrunk away by here
uniform float fade_width = 3.0;         // metres the shrinking away takes
uniform float fade_in_width = 3.0;
uniform float blade_width = 0.012;
uniform float tuft_radius = 0.12;
uniform float trail_half_width = 0.75;
uniform float groove_depth = 0.22;
uniform float bank_width = 0.7;
// Per biome (index from the field): blade colour, height in metres, share of
// tufts with a flower, whether the ground under is the grass ground (whose
// colour the roots take), and up to four flower colours.
uniform vec3 tip_color[8];
uniform float blade_height[8];
uniform float flower_share[8];
uniform float on_grass[8];
uniform vec3 flower_color[32];
uniform float flower_count[8];
// Per biome: the bare field's colour under it (rgb, SurfaceTex.grass_field) and
// how thick its meadow grows (a); a < 0: no scanned ground, the old noise colour.
uniform vec4 root_ground[8];
uniform float meadow_end = 56.0;       // the ground takes the meadow's colour past here (ground_tone)

#include "res://scene/real/ground_tone.gdshaderinc"

varying vec3 wpos;
varying float v_k;
varying vec3 v_tip;
varying float v_matched;
varying vec3 v_flower;      // rgb of the flower head, or -1
varying float v_var;
varying vec4 v_ground;
varying vec3 v_blades;

uint hash_u(uvec2 q) {
	q = q * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	n ^= n >> 16u;
	n *= 2246822519u;
	n ^= n >> 13u;
	return n;
}

float hf(uint n) {
	return float(n & 0xffffffu) / 16777216.0;
}

float n_at(vec2 p) {
	return textureLod(noise_tex, p, 0.0).r;
}

// The trail's groove and banks (TerrainStreamer's), which the field's height leaves out.
float groove(float a) {
	if (a < trail_half_width) {
		float q = a / trail_half_width;
		return -groove_depth * (1.0 - q * q);
	}
	if (a < trail_half_width + bank_width) {
		return 0.09 * sin(PI * (a - trail_half_width) / bank_width);
	}
	return 0.0;
}

void vertex() {
	vec3 slot = MODEL_MATRIX[3].xyz;
	ivec2 cell = ivec2(floor(slot.xz / pitch));
	uint h0 = hash_u(uvec2(cell + ivec2(1 << 20)));
	float r1 = hf(h0);
	float r2 = hf(hash_u(uvec2(h0, 1u)));
	float r3 = hf(hash_u(uvec2(h0, 2u)));
	float r4 = hf(hash_u(uvec2(h0, 3u)));
	float r5 = hf(hash_u(uvec2(h0, 4u)));
	vec2 root = (vec2(cell) + 0.5 + (vec2(r1, r2) - 0.5) * 0.95) * pitch;
	// The ground here.
	vec2 fuv = (root + 0.5) / field_size;
	vec4 f = textureLod(field, fuv, 0.0);
	float hx = textureLod(field, fuv + vec2(1.0 / field_size, 0.0), 0.0).r;
	float hz = textureLod(field, fuv + vec2(0.0, 1.0 / field_size), 0.0).r;
	vec3 gn = normalize(vec3(f.r - hx, 1.0, f.r - hz));
	int biome = int(texelFetch(field, ivec2(mod(floor(root + 0.5), field_size)), 0).a + 0.5);
	float lat = f.g;
	// The trail's ragged edge, as the ground shader draws it.
	float n2 = n_at(root * 0.07 + 0.3);
	float n3 = n_at(root * 0.45 + 0.7);
	float edge = trail_half_width + (n3 - 0.5) * 0.35 + (n2 - 0.5) * 0.25;
	float off_trail = smoothstep(edge + 0.05, edge + 0.45, lat);
	float steep = 1.0 - smoothstep(0.3, 0.45, 1.0 - gn.y + (n2 - 0.5) * 0.25);     // rock shows on steep ground
	float density = f.b * off_trail * steep;
	// Thinning: each tuft has a rank; it stands while the density and its ring's fade are over it.
	float d = distance(root, eye_pos.xz);
	float ring = 1.0 - smoothstep(fade_out - fade_width, fade_out, d);
	if (fade_in > 0.0) {
		ring *= smoothstep(fade_in - fade_in_width, fade_in, d);
	}
	float grow = clamp((density - r3 * 0.92) / 0.08, 0.0, 1.0) * clamp((ring - r4 * 0.8) / 0.2, 0.0, 1.0);
	float patchy = 0.75 + 0.5 * n_at(root * 0.13 + 3.0);          // taller and shorter stretches
	float size = grow * mix(0.7, 1.25, r5) * patchy * mix(0.45, 1.0, smoothstep(edge + 0.1, edge + 1.3, lat));
	float H = blade_height[biome] * UV2.y * size;
	// The blade (or flower) within its tuft.
	float turn = r5 * TAU * 7.0;
	mat2 rot = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn)));
	vec2 base = rot * VERTEX.xz * tuft_radius * (0.5 + r4);
	float la = UV2.x + turn;
	vec2 lean = vec2(cos(la), sin(la));
	float k = UV.y;
	float bend = COLOR.r;
	// Wind: gusts travelling across the field, a little flutter in each tuft.
	vec2 wind_dir = vec2(0.94, 0.33);
	float gust = n_at(root * 0.013 - TIME * wind_dir * 0.035);
	gust = smoothstep(0.3, 0.8, gust);
	vec2 push = wind_dir * (0.06 + 0.42 * gust) + lean * 0.05 * sin(TIME * (2.0 + 3.0 * r1) + r2 * TAU) * (0.4 + gust);
	vec3 p = vec3(root.x + base.x, f.r + groove(lat) - 0.03, root.y + base.y);
	bool flower = COLOR.b > 0.5;
	v_flower = vec3(-1.0);
	if (flower) {
		// A head on a stalk: only on the tufts chosen for one.
		float fc = flower_count[biome];
		if (grow <= 0.0 || fc < 0.5 || hf(hash_u(uvec2(h0, 5u))) >= flower_share[biome]) {
			H = 0.0;
		}
		v_flower = flower_color[biome * 4 + int(min(hf(hash_u(uvec2(h0, 6u))) * fc, fc - 1.0))];
		float stalk = H * 1.12;
		p.y += stalk;
		p.xz += push * stalk * 0.8;
		// UV.x, COLOR.g: the petal's corner, in a disc tilted a little.
		vec2 pet = rot * vec2(UV.x, COLOR.g * 2.0 - 1.0) * (H > 0.0 ? 0.038 * COLOR.a * 2.0 : 0.0);
		p += vec3(pet.x, 0.012 + dot(pet, lean) * 0.4, pet.y);
		k = 1.0;
	} else {
		p.y += H * k * (1.0 - 0.3 * bend * k);
		p.xz += (lean * bend + push) * H * k * k;
		// Width: across the lean, turned part way to face the eye so blades are never edge-on.
		vec2 side = vec2(-lean.y, lean.x);
		vec2 to_eye = normalize(eye_pos.xz - root + vec2(1e-4));
		vec2 facing = vec2(-to_eye.y, to_eye.x);
		side = normalize(mix(side, facing * sign(dot(side, facing) + 1e-4), 0.6));
		p.xz += side * UV.x * blade_width * COLOR.g * (1.0 - pow(k, 1.4) * 0.92) * min(size * 1.5, 1.0) * (0.6 + 0.8 * r2);
	}
	wpos = p;
	VERTEX = p - slot;
	NORMAL = gn;
	v_k = k;
	v_tip = tip_color[biome] * mix(0.82, 1.2, r1) * mix(vec3(1.0), vec3(1.18, 1.05, 0.8), 0.5 * r3);
	v_matched = on_grass[biome];
	v_ground = root_ground[biome];
	v_blades = tip_color[biome];
	v_var = COLOR.a;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.011).r;
	float n3 = texture(noise_tex, p * 0.45 + 0.7).r;
	float n4 = texture(noise_tex, p * 2.9 + 0.1).r;
	// The grass ground's own colour here (real_ground.gdshader, look 1).
	float dryness = smoothstep(0.35, 0.75, n1);
	vec3 ground;
	if (v_ground.a < 0.0) {
		vec3 lush = vec3(0.07, 0.13, 0.035);
		vec3 dry = vec3(0.15, 0.16, 0.06);
		ground = mix(lush, dry, dryness) * (0.75 + 0.45 * n3) * (0.85 + 0.3 * n4);
	} else {
		float n2 = texture(noise_tex, p * 0.07 + 0.3).r;
		ground = v_ground.rgb * ground_macro(1, n1, n2);
		ground = mix(ground, meadow_tone(v_blades, n3), meadow_share(length(VERTEX), v_ground.a, meadow_end));
	}
	vec3 tip = v_tip * mix(vec3(1.0), vec3(1.3, 1.08, 0.75), dryness * 0.6) * (0.8 + 0.4 * n3);
	vec3 root = mix(tip * 0.5, ground * 0.92, v_matched);
	vec3 col = mix(root, tip, smoothstep(0.0, 0.75, v_k));
	col *= mix(0.94, 1.06, v_var);
	float back = 0.35 * v_k;
	if (v_flower.r >= 0.0) {
		col = v_flower;
		back = 0.5;
	}
	NORMAL = normalize(NORMAL) * (FRONT_FACING ? 1.0 : -1.0);     // the ground's normal, whichever face shows
	ALBEDO = col * mix(1.0, 0.8, rain_wet);
	ROUGHNESS = mix(0.8, 0.4, rain_wet);
	SPECULAR = 0.25;
	BACKLIGHT = col * back;
}
