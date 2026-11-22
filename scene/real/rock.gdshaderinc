// Rock, shared by boulders (real_rock.gdshader) and steep ground
// (real_ground.gdshader), so a boulder and the bank it lies under are one
// stone. After Abyssal Garden's rock (MIT, Noniv/abyssal-garden): a height
// field baked from code (SurfaceTex.rock_detail: slope, height, mottling) read
// triplanar at about 10 m and 2.3 m gives the stone its shape, the normal
// coming from that same height, and the colour is multiplied by it (crevices
// dark, ridges light), which is most of what makes it read as stone. The
// finer scales, about 0.5 m and below, come from the scanned rock_cliff set
// (its grain, pale mineral flecks and normal), which beat a third and fourth
// octave of the bake side by side (R43 stage 2: the bake alone looked soft
// close up, the scan alone flat and printed-on). Then designed geology: beds
// of different tints with a dark joint between them, lichen only on raised
// parts, pale specks, moss only on faces that look up, snow on top. Needs
// wind.gdshaderinc (vnoise) first. Without the bake (no renderer) it falls back
// to noise; without the scan, to the bake's own finer octaves.

uniform sampler2D rock_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool rock_baked = false;
uniform bool rock_scan = false;
uniform sampler2D scan_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 scan_mean = vec3(0.095);   // the scan's average colour (linear)

struct RockTri {
	float h;
	float c;
	vec3 n;
};

// One scale of the bake, three projections weighted by the normal (w); dpx/dpy
// are the position's screen derivatives, so mip levels stay right inside branches.
RockTri rock_tri(vec3 p, vec3 w, float s, vec3 dpx, vec3 dpy) {
	RockTri o = RockTri(0.0, 0.0, vec3(0.0));
	if (w.x > 0.02) {
		vec4 t = textureGrad(rock_detail, p.zy * s, dpx.zy * s, dpy.zy * s);
		vec2 a = t.rg * 2.0 - 1.0;
		o.h += t.b * w.x;
		o.c += t.a * w.x;
		o.n += vec3(0.0, a.y, a.x) * w.x;
	}
	if (w.y > 0.02) {
		vec4 t = textureGrad(rock_detail, p.xz * s, dpx.xz * s, dpy.xz * s);
		vec2 a = t.rg * 2.0 - 1.0;
		o.h += t.b * w.y;
		o.c += t.a * w.y;
		o.n += vec3(a.x, 0.0, a.y) * w.y;
	}
	if (w.z > 0.02) {
		vec4 t = textureGrad(rock_detail, p.xy * s, dpx.xy * s, dpy.xy * s);
		vec2 a = t.rg * 2.0 - 1.0;
		o.h += t.b * w.z;
		o.c += t.a * w.z;
		o.n += vec3(a.x, a.y, 0.0) * w.z;
	}
	float tw = max(w.x * step(0.02, w.x) + w.y * step(0.02, w.y) + w.z * step(0.02, w.z), 1e-3);
	o.h /= tw;
	o.c /= tw;
	return o;
}

// The scan, triplanar: colour, normal lean (world), height. OpenGL normal maps,
// green up the picture, i.e. against v (which runs with world y or z here).
void scan_tri(vec3 p, vec3 w, float s, vec3 dpx, vec3 dpy, out vec3 col, out vec3 n, out float h) {
	col = vec3(0.0);
	n = vec3(0.0);
	h = 0.0;
	if (w.x > 0.02) {
		vec2 g1 = dpx.zy * s;
		vec2 g2 = dpy.zy * s;
		col += textureGrad(scan_albedo, p.zy * s, g1, g2).rgb * w.x;
		vec2 t = textureGrad(scan_normal, p.zy * s, g1, g2).rg * 2.0 - 1.0;
		n += vec3(0.0, -t.y, t.x) * w.x;
		h += textureGrad(scan_height, p.zy * s, g1, g2).r * w.x;
	}
	if (w.y > 0.02) {
		vec2 g1 = dpx.xz * s;
		vec2 g2 = dpy.xz * s;
		col += textureGrad(scan_albedo, p.xz * s, g1, g2).rgb * w.y;
		vec2 t = textureGrad(scan_normal, p.xz * s, g1, g2).rg * 2.0 - 1.0;
		n += vec3(t.x, 0.0, -t.y) * w.y;
		h += textureGrad(scan_height, p.xz * s, g1, g2).r * w.y;
	}
	if (w.z > 0.02) {
		vec2 g1 = dpx.xy * s;
		vec2 g2 = dpy.xy * s;
		col += textureGrad(scan_albedo, p.xy * s, g1, g2).rgb * w.z;
		vec2 t = textureGrad(scan_normal, p.xy * s, g1, g2).rg * 2.0 - 1.0;
		n += vec3(t.x, -t.y, 0.0) * w.z;
		h += textureGrad(scan_height, p.xy * s, g1, g2).r * w.z;
	}
	float tw = max(w.x * step(0.02, w.x) + w.y * step(0.02, w.y) + w.z * step(0.02, w.z), 1e-3);
	col /= tw;
	h /= tw;
}

float rock_hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

// p: world position (metres), dpx/dpy: dFdx(p), dFdy(p) taken by the caller
// outside any branch, n0: world normal, dist: metres from the eye, tint: the
// biome's rock colour, bed: the direction the beds stack along (up for a bank;
// tilted per boulder), moss 0..1, snow 0..1.
// Out: albedo (linear), world normal, roughness, height (0 crevice .. 1 ridge).
void rock_surface(vec3 p, vec3 dpx, vec3 dpy, vec3 n0, float dist, vec3 tint, vec3 bed, float moss, float snow,
		out vec3 alb, out vec3 nrm, out float rough, out float hgt) {
	vec3 w = pow(abs(n0), vec3(4.0));
	w /= (w.x + w.y + w.z);
	if (!rock_baked) {
		float n1 = vnoise(p.xz * 3.0 + p.y * 2.0);
		float n2 = vnoise(p.xz * 13.0 - p.y * 9.0);
		alb = tint * (0.6 + 0.5 * n1) * (0.8 + 0.35 * n2);
		alb = mix(alb, vec3(0.88, 0.9, 0.95), snow * smoothstep(0.35, 0.7, n0.y + (n2 - 0.5) * 0.4));
		nrm = n0;
		rough = 0.85;
		hgt = n1;
		return;
	}
	float fk = smoothstep(10.0, 1.5, dist);     // the finest grain, near only
	float ck = smoothstep(60.0, 12.0, dist);    // the fine scale
	RockTri A = rock_tri(p, w, 0.1, dpx, dpy);
	RockTri B = rock_tri(p, w, 0.43, dpx, dpy);
	RockTri C = RockTri(0.5, 0.5, vec3(0.0));
	RockTri F = RockTri(0.5, 0.5, vec3(0.0));
	float grain = 1.0;      // the scan's brightness against its average
	if (ck > 0.0) {
		if (rock_scan) {
			vec3 sc;
			vec3 sn;
			float sh;
			scan_tri(p, w, 0.55, dpx, dpy, sc, sn, sh);
			grain = dot(sc, vec3(0.33)) / dot(scan_mean, vec3(0.33));
			C = RockTri(sh, clamp(grain * 0.5, 0.0, 1.0), sn * 0.8);
			F = RockTri(sh, 0.5, vec3(0.0));
		} else {
			C = rock_tri(p, w, 1.9, dpx, dpy);
			if (fk > 0.0) {
				F = rock_tri(p, w, 6.7, dpx, dpy);
			}
		}
	}
	float big = textureGrad(rock_detail, p.xz * 0.013 + p.y * 0.021, dpx.xz * 0.013, dpy.xz * 0.013).a;
	float big2 = textureGrad(rock_detail, p.zx * 0.031 + p.y * 0.043 + 0.37, dpx.zx * 0.031, dpy.zx * 0.031).a;
	hgt = A.h * 0.5 + B.h * 0.35 + mix(0.5, C.h, ck) * 0.15;
	// Beds: stacked along `bed`, warped by the big shapes; each its own tint, a dark joint at each.
	float st = dot(p, bed) * 0.55 + A.h * 1.6 + big * 5.0 + big2 * 3.0;
	float bd = rock_hash(floor(st));
	float sf = fract(st);
	float side = 1.0 - abs(dot(n0, bed));
	alb = mix(tint * 0.45, tint * 0.95, clamp(A.c * 1.5 - 0.25, 0.0, 1.0));
	alb = mix(alb, mix(tint * vec3(1.1, 0.96, 0.8), tint * vec3(0.86, 0.92, 0.9), bd), smoothstep(0.42, 0.66, big) * 0.6);
	alb *= mix(0.76, 1.14, bd) * (1.0 - 0.45 * smoothstep(0.12, 0.0, sf) * side);
	// Lichen on the raised parts only, pale specks of other minerals.
	float enc = smoothstep(0.5, 0.64, big2 * 0.6 + B.c * 0.5) * smoothstep(0.35, 0.6, hgt);
	vec3 lichen = mix(vec3(0.4, 0.42, 0.37), vec3(0.46, 0.4, 0.22), smoothstep(0.5, 0.62, A.c));
	alb = mix(alb, lichen * (0.55 + 0.7 * B.h), enc * 0.3);
	alb = mix(alb, vec3(0.55, 0.54, 0.5) * (0.5 + 0.7 * C.h), smoothstep(0.62, 0.7, B.c * 0.6 + C.c * 0.5) * 0.4 * ck);
	// Moss in patches on faces that look up, thickest in the hollows.
	float alg = smoothstep(0.6, 0.72, n0.y * 0.8 + (B.c - 0.5) * 0.6 + (big - 0.5) * 0.5 + (0.5 - hgt) * 0.3 + (moss - 0.6) * 0.3)
			* step(0.01, moss);
	alb = mix(alb, vec3(0.06, 0.1, 0.025) * (0.6 + 0.8 * B.h), alg * 0.92);
	// Crevices dark, ridges light; the scan's grain on top.
	alb *= (0.22 + 1.35 * hgt) * mix(1.0, 0.65 + 0.7 * F.h, fk) * mix(1.0, grain, ck * 0.8);
	float sgro = -smoothstep(0.14, 0.0, sf) * side * 1.2;
	vec3 bump = A.n * 0.85 + B.n * 0.65 + C.n * 0.45 * ck + F.n * 0.5 * fk;
	nrm = normalize(n0 + bump * 1.5 * (1.0 - alg * 0.5) + bed * sgro * 0.3);
	rough = mix(0.72, 0.9, hgt) + alg * 0.08;
	// Snow on what faces up, first in the hollows.
	float s = step(0.01, snow) * smoothstep(0.54, 0.6, n0.y + (0.5 - hgt) * 0.4 + (B.c - 0.5) * 0.35 + (snow - 0.5) * 0.4);
	alb = mix(alb, vec3(0.86, 0.88, 0.93) * (0.92 + 0.1 * B.h), s);
	nrm = normalize(mix(nrm, n0, s * 0.7));
	rough = mix(rough, 0.6, s);
}
