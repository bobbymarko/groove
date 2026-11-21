shader_type canvas_item;
// One-off bake of the cloud noise, ported from Cloudscape (MIT, Fishypants/cloudscape):
// 3D textures are written as a 2D atlas of slices, read back and stacked by CloudNoise.
//   mode 0: shape, 128^3 in a 16x8 atlas   rgba = Perlin-Worley, Worley fbm at 4, 8, 16
//   mode 1: detail, 64^3 in an 8x8 atlas   rgb  = Alligator fbm at 4, 8, 16
//   mode 2: weather map, 512^2             r = coverage, g = cloud type
//   mode 3: curl offsets, 128^2            rgb = signed offset (x, y, z) * 0.5 + 0.5

uniform int mode = 0;

uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return v;
}

vec3 hash33(vec3 p) {
	return vec3(pcg3d(uvec3(ivec3(floor(p)) + 4096))) * (1.0 / 4294967295.0);
}

float grad(vec3 i, vec3 f, vec3 o, float per) {
	return dot(hash33(mod(i + o, per)) * 2.0 - 1.0, f - o);
}

float perlin(vec3 p, float per) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = grad(i, f, vec3(0.0, 0.0, 0.0), per), n100 = grad(i, f, vec3(1.0, 0.0, 0.0), per);
	float n010 = grad(i, f, vec3(0.0, 1.0, 0.0), per), n110 = grad(i, f, vec3(1.0, 1.0, 0.0), per);
	float n001 = grad(i, f, vec3(0.0, 0.0, 1.0), per), n101 = grad(i, f, vec3(1.0, 0.0, 1.0), per);
	float n011 = grad(i, f, vec3(0.0, 1.0, 1.0), per), n111 = grad(i, f, vec3(1.0, 1.0, 1.0), per);
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
			mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float worley(vec3 p, float per) {
	vec3 id = floor(p);
	vec3 f = p - id;
	float md = 1.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 r = o + hash33(mod(id + o, per)) - f;
		md = min(md, dot(r, r));
	}
	return 1.0 - sqrt(md);
}

// Rounded bumps of random size combined with max: puffs with soft creases between them.
float alligator(vec3 p, float per) {
	vec3 id = floor(p);
	vec3 f = p - id;
	float v = 0.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 c = mod(id + o, per);
		vec3 r = o + hash33(c) - f;
		vec3 h2 = hash33(c + 131.0);
		float rad = mix(0.75, 1.35, h2.x);
		float amp = mix(0.45, 1.0, h2.y);
		float d = clamp(dot(r, r) / (rad * rad), 0.0, 1.0);
		v = max(v, amp * sqrt(1.0 - d) * (1.0 - d * 0.35));
	}
	return v;
}

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) / (b - a) * (d - c);
}

float pot(vec2 q) {
	vec3 a = vec3(q, 0.37);
	return perlin(a * 4.0, 4.0) + 0.5 * perlin(a * 8.0, 8.0) + 0.25 * perlin(a * 16.0, 16.0);
}

void fragment() {
	vec2 px = floor(FRAGCOORD.xy);
	if (mode == 0 || mode == 1) {
		float size = mode == 0 ? 128.0 : 64.0;
		float cols = mode == 0 ? 16.0 : 8.0;
		vec2 tile = floor(px / size);
		vec2 xy = px - tile * size;
		float layer = tile.y * cols + tile.x;
		vec3 p = vec3(xy + 0.5, layer + 0.5) / size;
		if (mode == 0) {
			float pf = perlin(p * 4.0, 4.0) + 0.5 * perlin(p * 8.0, 8.0) + 0.25 * perlin(p * 16.0, 16.0);
			pf = clamp(pf / 1.75 * 1.4 + 0.5, 0.0, 1.0);
			float w4 = worley(p * 4.0, 4.0), w8 = worley(p * 8.0, 8.0), w16 = worley(p * 16.0, 16.0);
			float w32 = worley(p * 32.0, 32.0), w64 = worley(p * 64.0, 64.0);
			float wf = w4 * 0.625 + w8 * 0.25 + w16 * 0.125;
			COLOR = vec4(remap(pf, 0.0, 1.0, wf, 1.0), wf, w8 * 0.625 + w16 * 0.25 + w32 * 0.125, w16 * 0.625 + w32 * 0.25 + w64 * 0.125);
		} else {
			float a4 = alligator(p * 4.0, 4.0), a8 = alligator(p * 8.0, 8.0);
			float a16 = alligator(p * 16.0, 16.0), a32 = alligator(p * 32.0, 32.0);
			COLOR = vec4(a4 * 0.625 + a8 * 0.25 + a16 * 0.125, a8 * 0.625 + a16 * 0.25 + a32 * 0.125, a16 * 0.75 + a32 * 0.25, 1.0);
		}
	} else if (mode == 2) {
		vec3 p = vec3((px + 0.5) / 512.0, 0.21);
		float n = perlin(p * 3.0, 3.0) + 0.5 * perlin(p * 6.0, 6.0) + 0.25 * perlin(p * 12.0, 12.0)
				+ 0.125 * perlin(p * 24.0, 24.0) + 0.0625 * perlin(p * 48.0, 48.0);
		n = clamp(n / 1.94 * 1.3 + 0.5, 0.0, 1.0);
		float wl = worley(p * 12.0, 12.0), wh = worley(p * 24.0, 24.0);
		float r = clamp(n * 0.6 + (wl * 0.55 + wh * 0.45) * 0.7 - 0.15, 0.0, 1.0);
		float t = clamp(0.5 + perlin(p * 2.0 + 0.37, 2.0) * 0.9, 0.0, 1.0);
		COLOR = vec4(r, t, 0.0, 1.0);
	} else {
		vec2 q = (px + 0.5) / 128.0;
		float e = 0.5 / 128.0;
		float dx = (pot(q + vec2(e, 0.0)) - pot(q - vec2(e, 0.0))) / (2.0 * e);
		float dy = (pot(q + vec2(0.0, e)) - pot(q - vec2(0.0, e))) / (2.0 * e);
		vec2 c = vec2(dy, -dx) / 8.0;
		vec3 off = vec3(clamp(c.x, -1.0, 1.0), clamp(pot(q) * 1.4, -1.0, 1.0) * 0.5, clamp(c.y, -1.0, 1.0));
		COLOR = vec4(off * 0.5 + 0.5, 1.0);
	}
}
