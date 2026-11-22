shader_type spatial;
render_mode cull_back;
// Ground for the realistic look (R43 stage 2). Position, slope and the
// distance from the trail centre (UV.x, written by TerrainStreamer) decide
// what lies where: the trail with a ragged edge and a worn wheel line, the
// field, rock on steep ground. Each is a scanned material (SurfaceTex.ground:
// colour, normal and height in texture arrays) and they meet by height, the
// higher one winning at the seam: gravel stones poke into the grass at the
// trail's edge, grass creeps into the trail's low spots. Repeats are hidden by
// a slow warp, a different turn per material, a second, larger scale mixed in
// with distance and a broad tint over the land. A fine normal layer within
// ~10 m keeps the trail under the wheels crisp; beyond ~90 m only one cheap
// sample remains. Steep ground is the same rock as the boulders
// (rock.gdshaderinc). Rain darkens, puddles collect in the low spots and the
// wheel line, with rings where drops land. Without the texture sets (before
// tools/fetch-textures.sh) the noise ground of before is drawn instead.

#include "res://scene/real/wind.gdshaderinc"
#include "res://scene/real/rock.gdshaderinc"
#include "res://scene/real/ground_tone.gdshaderinc"
#include "res://scene/real/shade.gdshaderinc"

// Ground looks: 0 snow, 1 grass, 2 sand, 3 Sonoran desert (decomposed granite).
// A route ride's chunk blends two (ground_b's share per vertex in UV.y, R41).
uniform int ground_a = 0;
uniform int ground_b = 0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float trail_half_width = 0.75;

uniform bool textured = false;
uniform sampler2DArray g_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray g_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray g_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float slot_tile[10];     // metres one repeat covers
uniform vec3 slot_mean[10];      // each set's average colour once scaled (linear): the far ground
uniform float slot_gain[10];     // brings each scan to a true albedo (grass ~0.09, gravel ~0.22, snow ~0.84)
uniform vec3 field_tint[4];      // per look: the field turned toward its biome's colour (the grass's, a desert's tan)
uniform vec3 trail_tint[4];      // per look: the same for the trail
uniform vec3 meadow_color[4];    // per look: the meadow's blades (RealFlora's grass colour)
uniform float meadow_amount[4];  // per look: how thick that meadow grows (0: none)
uniform float meadow_end = 56.0; // where the meadow's last ring of blades ends (RealGrass sets it)
uniform vec3 rock_tint = vec3(0.4, 0.39, 0.37);
uniform float rock_moss = 0.0;
uniform float rock_snow = 0.0;

// Layers in the arrays (SurfaceTex.GROUND).
const int S_GRASS = 0;
const int S_FOREST = 1;
const int S_GRAVEL = 2;
const int S_MUD = 3;
const int S_SNOW = 4;
const int S_SNOWTRAIL = 5;
const int S_SAND = 6;
const int S_DESERT = 7;

const float NEAR_END = 90.0;     // full materials within this; one cheap sample beyond FAR_FROM
const float FAR_FROM = 70.0;

varying vec3 wpos;
varying float lat;
varying float b_share;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lat = UV.x;
	b_share = UV.y;
}

float n(vec2 p) { return texture(noise_tex, p).r; }

// Rain rings on a puddle: one drop per 0.5 m cell at a random moment, its ring
// spreading and fading. Returns the ring's slope (a normal-map tilt).
vec2 ripples(vec2 p, float t) {
	vec2 cell = floor(p * 2.0);
	vec2 f = fract(p * 2.0) - 0.5;
	vec2 total = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 c = cell + float(k) * 17.0;
		float h = hash21(c);
		float age = fract(t * (0.8 + 0.4 * h) + h);
		vec2 centre = (vec2(hash21(c + 3.1), hash21(c + 7.7)) - 0.5) * 0.5;
		vec2 v = f - centre;
		float d = length(v);
		float ring = exp(-pow((d - age * 0.45) * 26.0, 2.0)) * (1.0 - age);
		total += v / max(d, 1e-3) * ring;
		f = fract(p * 2.0 + 0.5) - 0.5;
		cell = floor(p * 2.0 + 0.5);
	}
	return total;
}

// --- the scanned materials ---------------------------------------------------

struct Surf {
	vec3 col;
	vec2 tilt;    // the normal's lean, world x and z
	float h;      // 0 low .. 1 high
};

// Each layer's field, a patch material, the trail and the worn wheel line.
ivec4 look_slots(int g) {
	if (g == 0) {
		return ivec4(S_SNOW, S_SNOW, S_SNOWTRAIL, S_SNOWTRAIL);
	} else if (g == 1) {
		return ivec4(S_GRASS, S_FOREST, S_GRAVEL, S_MUD);
	} else if (g == 2) {
		return ivec4(S_SAND, S_DESERT, S_SAND, S_SAND);
	}
	return ivec4(S_DESERT, S_SAND, S_DESERT, S_DESERT);
}

// How much of a look's field its patch material may take.
float look_patch(int g) {
	return g == 1 ? 1.0 : (g == 0 ? 0.0 : 0.5);
}

float slot_rough(int s) {
	if (s == S_SNOW) {
		return 0.62;
	} else if (s == S_SNOWTRAIL) {
		return 0.5;
	} else if (s == S_MUD) {
		return 0.78;
	}
	return 0.92;
}

mat2 turn(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// One material at p, turned by `angle` (each its own, so no two share a grid;
// a striped set turned to follow the trail), the slow warp, and (k2 > 0) a
// 3.7x larger copy turned again mixed into the colour.
Surf layer(int s, vec2 p, vec2 warp, vec2 dpx, vec2 dpy, float k2, float angle) {
	float tile = slot_tile[s];
	mat2 r = turn(angle);
	vec2 uv = r * p / tile + warp;
	vec2 gx = r * dpx / tile;
	vec2 gy = r * dpy / tile;
	vec3 at = vec3(uv, float(s));
	Surf o;
	o.col = textureGrad(g_albedo, at, gx, gy).rgb;
	vec2 nm = textureGrad(g_normal, at, gx, gy).rg * 2.0 - 1.0;
	o.tilt = transpose(r) * vec2(nm.x, -nm.y);    // OpenGL normal maps: green up the picture
	o.h = textureGrad(g_height, at, gx, gy).r;
	if (k2 > 0.0) {
		mat2 r2 = turn(float(s) * 1.7 + 2.4);
		float t2 = tile * 3.7;
		vec3 col2 = textureGrad(g_albedo, vec3(r2 * p / t2 - warp * 0.3, float(s)), r2 * dpx / t2, r2 * dpy / t2).rgb;
		o.col = mix(o.col, col2, k2);
	}
	o.col *= slot_gain[s];
	return o;
}

// Share of b where a and b meet with b's weight wb: the higher surface wins,
// over a seam `depth` deep.
float height_blend(float ha, float hb, float wb, float depth) {
	float a = ha * 0.7 + (1.0 - wb);
	float b = hb * 0.7 + wb;
	float m = max(a, b) - depth;
	float ka = max(a - m, 0.0);
	float kb = max(b - m, 0.0);
	return kb / max(ka + kb, 1e-4);
}

Surf mix_surf(Surf a, Surf b, float t) {
	Surf o;
	o.col = mix(a.col, b.col, t);
	o.tilt = mix(a.tilt, b.tilt, t);
	o.h = mix(a.h, b.h, t);
	return o;
}

// One ground look at p, near: field (with patches), trail and wheel line,
// blended by height. trail_w: the trail's share by its ragged edge; rut: the
// wheel line's (0..1).
Surf look_near(int g, vec2 p, vec2 warp, vec2 dpx, vec2 dpy, float k2, float trail_w, float rut, float packed,
		float patch_w, float along_x, float n1, float n2, out float rough) {
	ivec4 sl = look_slots(g);
	Surf f = layer(sl.x, p, warp, dpx, dpy, k2, float(sl.x) * 1.7);
	f.col *= field_tint[g];
	rough = slot_rough(sl.x);
	if (patch_w * look_patch(g) > 0.0 && sl.y != sl.x) {
		Surf q = layer(sl.y, p, warp, dpx, dpy, k2, float(sl.y) * 1.7);
		q.col *= g == 1 ? field_tint[g] : vec3(1.0);     // the grass look's litter follows its biome too
		float t = height_blend(f.h, q.h, patch_w * look_patch(g), 0.2);
		f = mix_surf(f, q, t);
		rough = mix(rough, slot_rough(sl.y), t);
	}
	f.col *= ground_macro(g, n1, n2);
	if (trail_w > 0.0) {
		// The tracked snow's streaks run along the trail; other sets keep their own turn.
		float angle = sl.z == S_SNOWTRAIL ? along_x * 1.5708 : float(sl.z) * 1.7;
		Surf t = layer(sl.z, p, warp, dpx, dpy, k2 * 0.5, angle);
		float tr = slot_rough(sl.z);
		float mud = rut * smoothstep(0.62, 0.8, n2 * 0.6 + n1 * 0.4 + (0.5 - t.h) * 0.3);
		if (mud > 0.02 && sl.w != sl.z) {
			Surf w = layer(sl.w, p, warp, dpx, dpy, 0.0, float(sl.w) * 1.7);
			float k = height_blend(t.h, w.h * 0.6, mud, 0.15);
			t = mix_surf(t, w, k);
			tr = mix(tr, slot_rough(sl.w), k);
		}
		// The wheel line is packed down: darker, smoother, its stones pressed flat.
		float press = max(rut, packed * 0.8);
		t.col *= 1.0 - 0.07 * packed - 0.06 * rut;
		t.h = mix(t.h, 0.42, press * 0.55);
		t.tilt *= 1.0 - 0.6 * press;
		tr = mix(tr, tr - 0.12, rut);
		t.col *= trail_tint[g] * (0.94 + 0.12 * n2);
		float k = height_blend(f.h, t.h, trail_w, 0.12);
		f = mix_surf(f, t, k);
		rough = mix(rough, tr, k);
	}
	return f;
}

// One ground look at p, far: each material's average colour.
vec3 look_far(int g, float trail_w, float n1, float n2) {
	ivec4 sl = look_slots(g);
	vec3 f = slot_mean[sl.x] * field_tint[g] * ground_macro(g, n1, n2);
	return mix(f, slot_mean[sl.z] * trail_tint[g], trail_w);
}

// --- the noise ground (no texture sets) --------------------------------------

void ground_look(int g, vec2 p, float n1, float n2, float n3, float n4, float rut, float trail,
		out vec3 field, out vec3 path, out float field_rough, out float path_rough, out float bump) {
	if (g == 0) {
		field = vec3(0.86, 0.89, 0.94) * (0.94 + 0.06 * n2) - vec3(0.03, 0.02, 0.0) * smoothstep(0.55, 0.75, n3);
		path = mix(vec3(0.62, 0.62, 0.64), vec3(0.5, 0.48, 0.47), rut * 0.6) * (0.85 + 0.25 * n4);
		field_rough = 0.6;
		path_rough = 0.75;
		bump = mix(0.35, 0.8, trail);
	} else if (g == 1) {
		vec3 lush = vec3(0.07, 0.13, 0.035);
		vec3 dry = vec3(0.15, 0.16, 0.06);
		field = mix(lush, dry, smoothstep(0.35, 0.75, n1)) * (0.75 + 0.45 * n3) * (0.85 + 0.3 * n4);
		path = mix(vec3(0.27, 0.2, 0.13), vec3(0.2, 0.15, 0.1), rut * 0.7) * (0.75 + 0.45 * n4);
		field_rough = 0.95;
		path_rough = 0.9;
		bump = 1.0;
	} else if (g == 3) {
		vec3 tan = vec3(0.4, 0.29, 0.2);
		vec3 rust = vec3(0.43, 0.24, 0.15);
		field = mix(tan, rust, smoothstep(0.35, 0.7, n1)) * (0.86 + 0.22 * n3);
		field = mix(field, vec3(0.58, 0.5, 0.4), smoothstep(0.66, 0.82, n2) * 0.18);
		float peb = n(p * 6.7 + 2.0);
		field *= 1.0 - 0.35 * smoothstep(0.7, 0.74, peb);
		field = mix(field, vec3(0.75, 0.7, 0.62), smoothstep(0.76, 0.8, n(p * 9.1 + 5.0)) * 0.6);
		path = mix(vec3(0.5, 0.4, 0.3), vec3(0.43, 0.34, 0.26), rut * 0.6) * (0.85 + 0.2 * n4);
		field_rough = 0.95;
		path_rough = 0.92;
		bump = 1.1;
	} else {
		field = vec3(0.58, 0.32, 0.14) * (0.85 + 0.2 * n2) * (0.93 + 0.1 * n4);
		path = vec3(0.5, 0.29, 0.15) * (0.85 + 0.2 * n4);
		field_rough = 0.92;
		path_rough = 0.9;
		bump = 0.7;
	}
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	float n1 = n(p * 0.011);
	float n2 = n(p * 0.07 + 0.3);
	float n3 = n(p * 0.45 + 0.7);
	float nw = n(p * 0.031 + 0.9);
	vec3 dwx = dFdx(wpos);
	vec3 dwy = dFdy(wpos);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - wn.y;
	float a = abs(lat);
	float edge = trail_half_width + (n3 - 0.5) * 0.35 + (n2 - 0.5) * 0.25;
	float trail = 1.0 - smoothstep(edge - 0.18, edge + 0.22, a);
	float wander = lat + (n2 - 0.5) * 0.18;              // the wheel line wanders a little
	float rut = exp(-pow(wander / 0.13, 2.0));          // the wheel line down the middle
	float packed = exp(-pow(wander / (trail_half_width * 0.5), 2.0));   // the ridden band about it: stones pressed in
	float rock = smoothstep(0.38, 0.55, slope + (n2 - 0.5) * 0.25);
	float k_b = 0.0;
	if (b_share > 0.002 && ground_b != ground_a) {
		// Patchy, not a straight line: noise pushes the edge about.
		k_b = smoothstep(0.0, 1.0, clamp(b_share + (n2 - 0.5) * 0.6 + (n3 - 0.5) * 0.15, 0.0, 1.0));
	}
	float snowy = mix(ground_a == 0 ? 1.0 : 0.0, ground_b == 0 ? 1.0 : 0.0, k_b);
	float sandy = mix(ground_a == 2 ? 1.0 : 0.0, ground_b == 2 ? 1.0 : 0.0, k_b);
	int g_main = k_b > 0.5 ? ground_b : ground_a;
	float meadow = meadow_share(dist, mix(meadow_amount[ground_a], meadow_amount[ground_b], k_b) * (1.0 - trail), meadow_end);
	vec3 blades = mix(meadow_color[ground_a], meadow_color[ground_b], k_b);

	vec3 col;
	vec3 nrm = wn;
	float rough;
	float h = 0.5;
	float spec = 0.4;
	if (textured) {
		vec2 dpx = dFdx(p);
		vec2 dpy = dFdy(p);
		// The way across the trail (lat's gradient), for the wheel line's dip and striped trail sets.
		float dlx = dFdx(lat);
		float dly = dFdy(lat);
		float det = dpx.x * dpy.y - dpx.y * dpy.x;
		vec2 across = abs(det) > 1e-9 ? vec2(dpy.y * dlx - dpx.y * dly, dpx.x * dly - dpy.x * dlx) / det : vec2(1.0, 0.0);
		across = normalize(across + vec2(1e-5, 0.0));
		float along_x = smoothstep(0.55, 0.85, abs(across.y));
		vec3 far_col = look_far(ground_a, trail, n1, n2);
		if (k_b > 0.0) {
			far_col = mix(far_col, look_far(ground_b, trail, n1, n2), k_b);
		}
		far_col = mix(far_col, meadow_tone(blades, n3), meadow);
		far_col = mix(far_col, rock_tint * (0.55 + 0.6 * n3) * (0.8 + 0.3 * n2), rock * (1.0 - trail));
		col = far_col;
		rough = mix(0.92, 0.85, rock);
		float near_k = 1.0 - smoothstep(FAR_FROM, NEAR_END, dist);
		if (near_k > 0.0) {
			vec2 warp = (vec2(nw, n1) - 0.5) * 0.5;
			float k2 = 0.25 + 0.2 * smoothstep(8.0, 40.0, dist);
			float patch_w = smoothstep(0.66, 0.78, n3 * 0.5 + n2 * 0.35 + n1 * 0.25) * (1.0 - trail) * smoothstep(45.0, 20.0, dist);   // bare litter here and there, close by
			float r_a;
			Surf s = look_near(ground_a, p, warp, dpx, dpy, k2, trail, rut, packed, patch_w, along_x, n1, n2, r_a);
			if (k_b > 0.0) {
				float r_b;
				Surf sb = look_near(ground_b, p, warp, dpx, dpy, k2, trail, rut, packed, patch_w, along_x, n1, n2, r_b);
				s = mix_surf(s, sb, k_b);
				r_a = mix(r_a, r_b, k_b);
			}
			// Colour follows height a little: hollows darker, tops lighter.
			s.col *= 0.82 + 0.36 * s.h;
			s.col = mix(s.col, meadow_tone(blades, n3), meadow);
			// Fine detail under the wheels: the same material at a quarter the size.
			float fine = smoothstep(12.0, 3.0, dist);
			if (fine > 0.0) {
				int fs = look_slots(g_main).x;
				fs = trail > 0.5 ? look_slots(g_main).z : fs;
				float ft = slot_tile[fs] * 0.27;
				mat2 fr = turn(0.6);
				vec2 fnm = textureGrad(g_normal, vec3(fr * p / ft, float(fs)), fr * dpx / ft, fr * dpy / ft).rg * 2.0 - 1.0;
				s.tilt += transpose(fr) * vec2(fnm.x, -fnm.y) * 0.5 * fine * (1.0 - max(rut, packed * 0.8) * 0.6 * trail);
			}
			// The wheel line's dip: the ground leans in toward the middle.
			float dip = -wander / 0.13 * rut * 0.3 * trail * smoothstep(30.0, 5.0, dist);
			vec2 tilt = s.tilt * 1.1 * (1.0 - meadow) + across * dip;
			vec3 n_near = normalize(wn + vec3(tilt.x, 0.0, tilt.y));
			float r_near = r_a;
			h = s.h;
			// Steep ground: rock, meeting the soil by height too.
			if (rock > 0.01) {
				vec3 ra;
				vec3 rn;
				float rr;
				float rh;
				rock_surface(wpos, dwx, dwy, wn, dist, rock_tint, vec3(0.0, 1.0, 0.0), rock_moss, rock_snow * snowy, 1000.0, 10.0, ra, rn, rr, rh);
				float k = height_blend(s.h, rh, rock * (1.0 - trail), 0.15);
				s.col = mix(s.col, ra, k);
				n_near = normalize(mix(n_near, rn, k));
				r_near = mix(r_near, rr, k);
				h = mix(h, rh, k);
			}
			col = mix(far_col, s.col, near_k);
			nrm = normalize(mix(wn, n_near, near_k));
			rough = mix(rough, r_near, near_k);
		}
	} else {
		float n4 = n(p * 2.9 + 0.1);
		vec3 field;
		vec3 path;
		float field_rough;
		float path_rough;
		float bump;
		ground_look(ground_a, p, n1, n2, n3, n4, rut, trail, field, path, field_rough, path_rough, bump);
		if (k_b > 0.0) {
			vec3 f2; vec3 p2; float fr2; float pr2; float b2;
			ground_look(ground_b, p, n1, n2, n3, n4, rut, trail, f2, p2, fr2, pr2, b2);
			field = mix(field, f2, k_b);
			path = mix(path, p2, k_b);
			field_rough = mix(field_rough, fr2, k_b);
			path_rough = mix(path_rough, pr2, k_b);
			bump = mix(bump, b2, k_b);
		}
		vec3 stone = vec3(0.36, 0.35, 0.34) * (0.55 + 0.6 * n4) * (0.8 + 0.3 * n2);
		col = mix(field, path, trail);
		col = mix(col, stone, rock * (1.0 - trail));
		rough = mix(mix(field_rough, path_rough, trail), 0.8, rock);
		vec3 nm1 = texture(noise_nrm, p * 0.45).xyz * 2.0 - 1.0;
		vec3 nm2 = texture(noise_nrm, p * 2.9).xyz * 2.0 - 1.0;
		vec2 tilt = (nm1.xy * 0.45 + nm2.xy * 0.55) * 0.25 * bump * mix(1.0, 2.0, rock);
		nrm = normalize(wn + vec3(tilt.x, 0.0, -tilt.y));
		h = n3;
	}
	// Rain: soil darkens and shines, water collects in the low spots and the wheel line.
	float wet = (1.0 - snowy) * rain_wet;
	col *= mix(1.0, mix(0.58, 0.7, sandy), wet);
	rough = mix(rough, 0.35, wet);
	float pool = wet * smoothstep(0.6, 0.72, (1.0 - h) * 0.5 + n3 * 0.3 + rut * 0.4 + (1.0 - n2) * 0.2) * trail
			* smoothstep(0.42, 0.58, n(p * 0.16 + 5.0));   // separate pools, not one stream
	if (pool > 0.0) {
		vec2 rip = ripples(p, TIME) * smoothstep(30.0, 6.0, dist);
		col = mix(col, col * 0.3, pool);
		rough = mix(rough, 0.03, pool);
		nrm = normalize(mix(nrm, normalize(wn + vec3(rip.x, 0.0, rip.y) * 0.35), pool));
		spec = mix(spec, 0.5, pool);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(spec, 0.5, wet);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	Shade sh = shade_ground(wpos, dist);
	SHADE_APPLY(sh)
}
