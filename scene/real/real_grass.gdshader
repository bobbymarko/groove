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
// scrolling noise.
// The rings of tufts are one meadow. The finest ring's grid holds every tuft;
// each coarser ring's cell (twice the size) carries one of its four finer
// cells' tufts, its "heir", made from the same numbers: so a tuft far off is
// the very tuft that stands there close up. A tuft that is no heir stands only
// in the finest ring; an heir of one level stands to the middle ring's end,
// of two to the far ring's. Each kind shrinks away one by one (each tuft has a
// rank) before its ring ends, blades grow wider with distance to cover for
// the tufts gone, and at a ring's end the tufts that live on pass to the next
// ring's mesh at one distance, drawn the same by both: nothing pops or swaps.

global uniform float rain_wet;
global uniform vec3 eye_pos;

uniform sampler2D field : filter_linear, repeat_enable;       // r height, g metres from the trail's middle, b density, a biome index
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;   // the ground shader's noise
uniform float field_size = 128.0;      // texels across (one metre each)
uniform float pitch = 0.25;            // metres between the finest ring's tuft slots
uniform int level = 0;                 // which ring this mesh is (0 the finest; its slots are pitch * 2^level apart)
uniform int levels = 3;                // how many rings there are
uniform float ring_out[3];             // where each ring ends: its own tufts are gone, the rest pass to the next ring
uniform float ring_fade[3];            // metres over which they shrink away before that
uniform float ring_width[3];           // blade width in each ring (it widens over the fade before)
uniform float ring_radius[3];          // tuft radius, by the furthest ring the tuft stands in
uniform float ring_flower[3];          // flower head size in each ring (0: none)
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
uniform vec2 meadow_thin = vec2(5.0, 9.0);   // and part of it where the finest ring thins out

#include "res://scene/real/ground_tone.gdshaderinc"
#define SHADE_BACKLIGHT
#include "res://scene/real/shade.gdshaderinc"

varying vec3 wpos;
varying float v_k;
varying vec3 v_tip;
varying float v_matched;
varying vec3 v_flower;      // rgb of the flower head, or -1
varying float v_var;
varying vec4 v_ground;
varying vec3 v_blades;
varying vec4 v_shade;      // the ground's Shade at the tuft: rgb ambient, a sun

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

// Which of a cell's four finer cells carries its tuft (l: the cell's level).
ivec2 heir(ivec2 c, int l) {
	uint h = hash_u(uvec2(c) + uvec2(uint(l) * 7919u, 104729u));
	return ivec2(int((h >> 8u) & 1u), int((h >> 9u) & 1u));
}

void vertex() {
	vec3 slot = MODEL_MATRIX[3].xyz;
	// This slot's cell on its ring's grid, then down to the finest grid by heirs.
	ivec2 cell = ivec2(floor(slot.xz / (pitch * float(1 << level)))) + ivec2(1 << (20 - level));
	for (int l = level; l > 0; l--) {
		cell = cell * 2 + heir(cell, l);
	}
	// The furthest ring this tuft stands in: how many levels up it is the heir.
	int reach = 0;
	ivec2 up = cell;
	for (int l = 1; l < levels; l++) {
		ivec2 parent = up >> 1;
		if (parent * 2 + heir(parent, l) != up) {
			break;
		}
		reach = l;
		up = parent;
	}
	uint h0 = hash_u(uvec2(cell));
	float r1 = hf(h0);
	float r2 = hf(hash_u(uvec2(h0, 1u)));
	float r3 = hf(hash_u(uvec2(h0, 2u)));
	float r4 = hf(hash_u(uvec2(h0, 3u)));
	float r5 = hf(hash_u(uvec2(h0, 4u)));
	vec2 root = (vec2(cell - ivec2(1 << 20)) + 0.5 + (vec2(r1, r2) - 0.5) * 0.95) * pitch;
	// Thinning: each tuft has a rank; it stands while its kind's fade (and, below, the density) is over
	// it, and is drawn by the one ring whose stretch it is in.
	float d = distance(root, eye_pos.xz);
	float ring = 1.0 - smoothstep(ring_out[reach] - ring_fade[reach], ring_out[reach], d);
	if (d >= ring_out[level] || (level > 0 && d < ring_out[level - 1])) {
		ring = 0.0;
	}
	float stand = clamp((ring - r4 * 0.8) / 0.2, 0.0, 1.0);
	int biome = int(texelFetch(field, ivec2(mod(floor(root + 0.5), field_size)), 0).a + 0.5);
	// A flower's stalk and head are only on the tufts chosen for one.
	if (COLOR.b > 0.25 && (flower_count[biome] < 0.5 || hf(hash_u(uvec2(h0, 5u))) >= flower_share[biome])) {
		stand = 0.0;
	}
	// Most vertices are of tufts not standing here or flowers not shown: those stop
	// now, before the costly part (the ground, the shade, the wind), as a point.
	wpos = slot;
	v_k = 0.0;
	v_tip = vec3(0.0);
	v_matched = 0.0;
	v_flower = vec3(-1.0);
	v_var = 0.0;
	v_ground = vec4(0.0);
	v_blades = vec3(0.0);
	v_shade = vec4(0.0);
	if (stand <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		// The ground here.
		vec2 fuv = (root + 0.5) / field_size;
		vec4 f = textureLod(field, fuv, 0.0);
		float hx = textureLod(field, fuv + vec2(1.0 / field_size, 0.0), 0.0).r;
		float hz = textureLod(field, fuv + vec2(0.0, 1.0 / field_size), 0.0).r;
		vec3 gn = normalize(vec3(f.r - hx, 1.0, f.r - hz));
		float lat = f.g;
		// The trail's ragged edge, as the ground shader draws it.
		float n2 = n_at(root * 0.07 + 0.3);
		float n3 = n_at(root * 0.45 + 0.7);
		float edge = trail_half_width + (n3 - 0.5) * 0.35 + (n2 - 0.5) * 0.25;
		float off_trail = smoothstep(edge + 0.05, edge + 0.45, lat);
		float steep = 1.0 - smoothstep(0.3, 0.45, 1.0 - gn.y + (n2 - 0.5) * 0.25);     // rock shows on steep ground
		// Under thick leaf cover grass grows thin, and none at a trunk's or rock's foot.
		vec2 cover = shade_cover(root);
		float density = f.b * off_trail * steep * (1.0 - 0.3 * (1.0 - exp(-cover.x))) * (1.0 - 0.3 * min(cover.y, 1.0));
		float grow = clamp((density - r3 * 0.92) / 0.08, 0.0, 1.0) * stand;
		// How far through each handover this spot is: blades widen and flowers change size with it.
		float s0 = smoothstep(ring_out[0] - ring_fade[0], ring_out[0], d);
		float s1 = smoothstep(ring_out[1] - ring_fade[1], ring_out[1], d);
		float blade_width = mix(mix(ring_width[0], ring_width[1], s0), ring_width[2], s1);
		float flower_size = mix(mix(ring_flower[0], ring_flower[1], s0), ring_flower[2], s1);
		float tuft_radius = ring_radius[reach];
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
		bool flower = COLOR.b > 0.75;
		v_flower = vec3(-1.0);
		float fc = flower_count[biome];
		if (COLOR.b > 0.25) {
			// A head on a stalk: only on the tufts chosen for one (the stalk is a
			// straight blade, COLOR.b 0.5, that goes the way of the head).
			if (grow <= 0.0) {
				H = 0.0;
			}
			H *= min(flower_size * 4.0, 1.0);        // (a ring with no flowers: stalks sink as the heads shrink)
		}
		if (flower) {
			v_flower = flower_color[biome * 4 + int(min(hf(hash_u(uvec2(h0, 6u))) * fc, fc - 1.0))];
			float stalk = H * 1.12;
			p.y += stalk;
			p.xz += push * stalk;
			// UV.x, COLOR.g: the petal's corner in the head's disc: five wedges
			// round the middle, a shallow cup tilted a little toward the lean.
			vec2 corner = vec2(UV.x, COLOR.g * 2.0 - 1.0);
			vec2 pet = rot * corner * (H > 0.0 ? 0.038 * flower_size : 0.0);
			p += vec3(pet.x, dot(pet, lean) * 0.4 + length(pet) * 0.3, pet.y);
			k = 1.0 + length(corner);          // past 1: how far out from the head's middle (the fragment's eye and petal)
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
		Shade sh = shade_ground_from(cover, p, distance(p, eye_pos));
		v_shade = vec4(sh.amb, sh.sun);
	}
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
		ground = mix(ground, meadow_tone(v_blades, n3), meadow_share(length(VERTEX), v_ground.a, meadow_end, meadow_thin));
	}
	vec3 tip = v_tip * mix(vec3(1.0), vec3(1.3, 1.08, 0.75), dryness * 0.6) * (0.8 + 0.4 * n3);
	vec3 root = mix(tip * 0.5, ground * 0.92, v_matched);
	vec3 col = mix(root, tip, smoothstep(0.0, 0.75, v_k));
	col *= mix(0.94, 1.06, v_var);
	float back = 0.35 * min(v_k, 1.0);
	if (v_flower.r >= 0.0) {
		// Petals: the flower's colour as a matt surface (pale petals reflect
		// about two thirds of the light, not all of it: at full strength they
		// stood out of a dark meadow as if lit from inside), a little darker
		// toward the middle, round a yellow eye.
		float r = v_k - 1.0;
		col = v_flower * 0.62 * mix(0.8, 1.0, smoothstep(0.3, 0.9, r));
		col = mix(vec3(0.5, 0.36, 0.05), col, smoothstep(0.24, 0.36, r));
		back = 0.2;
	}
	NORMAL = normalize(NORMAL) * (FRONT_FACING ? 1.0 : -1.0);     // the ground's normal, whichever face shows
	ALBEDO = col * mix(1.0, 0.8, rain_wet);
	ROUGHNESS = mix(0.8, 0.4, rain_wet);
	SPECULAR = 0.25;
	BACKLIGHT = col * back;
	Shade sh;
	sh.amb = v_shade.rgb;
	sh.sun = v_shade.a;
	SHADE_APPLY(sh)
}
