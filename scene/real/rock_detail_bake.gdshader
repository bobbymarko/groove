shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Rock detail, drawn once (SurfaceTex.rock_detail): a tileable height field,
// after Abyssal Garden's W_DETAIL (MIT, Noniv/abyssal-garden). Warped fBm for
// the body, sharp ridges, two crack networks crossing and Worley pits; its own
// slope beside it, so the light follows the same bumps the colour does.
// Out: rg slope (0.5 flat), b height, a a separate mottling for colour.

uniform float px = 1024.0;

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 h33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Value noise that repeats every `per` cells.
float hp(vec2 p, float per) {
	return h31(vec3(p - per * floor(p / per), per));
}

float tn(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hp(i, per), hp(i + vec2(1.0, 0.0), per), u.x), mix(hp(i + vec2(0.0, 1.0), per), hp(i + vec2(1.0, 1.0), per), u.x), u.y);
}

float tf(vec2 uv, float per, int n) {
	float a = 0.5;
	float s = 0.0;
	float pr = per;
	for (int i = 0; i < n; i++) {
		s += a * tn(uv * pr + float(i) * 7.3, pr);
		pr *= 2.0;
		a *= 0.5;
	}
	return s / (1.0 - 2.0 * a);
}

// Worley: distance to the nearest and second cell point, and the nearest's id.
vec3 tw(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 d = vec2(9.0);
	float id = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = i + o;
			vec2 cw = c - per * floor(c / per);
			vec3 hh = h33(vec3(cw, per));
			vec2 r = o + hh.xy - f;
			float l = dot(r, r);
			if (l < d.x) {
				d.y = d.x;
				d.x = l;
				id = hh.z;
			} else if (l < d.y) {
				d.y = l;
			}
		}
	}
	return vec3(sqrt(d), id);
}

float H(vec2 uv) {
	vec2 wq = uv + 0.11 * (vec2(tf(uv, 3.0, 4), tf(uv + 0.5, 3.0, 4)) - 0.5);
	float f = tf(wq, 3.0, 8);
	float r1 = 1.0 - abs(tf(wq + 1.7, 5.0, 6) * 2.0 - 1.0);
	float cr = min(abs(tf(wq + 4.1, 4.0, 5) * 2.0 - 1.0) * 7.0, 1.0);
	float cr2 = min(abs(tf(wq.yx + 2.3, 9.0, 4) * 2.0 - 1.0) * 9.0, 1.0);
	vec3 pt = tw(wq * 29.0, 29.0);
	float pit = (1.0 - smoothstep(0.0, 0.34, pt.x)) * step(0.62, pt.z);
	return f * 0.5 + r1 * r1 * 0.24 + cr * cr2 * 0.26 - pit * 0.07;
}

void fragment() {
	vec2 uv = floor(FRAGCOORD.xy) / px;
	float e = 1.0 / px;
	float h = H(uv);
	float gx = H(uv + vec2(e, 0.0)) - H(uv - vec2(e, 0.0));
	float gy = H(uv + vec2(0.0, e)) - H(uv - vec2(0.0, e));
	vec2 s = clamp(vec2(gx, gy) * px * 0.5 * 0.075, vec2(-1.0), vec2(1.0));
	COLOR = vec4(-s * 0.5 + 0.5, h, tf(uv + 3.7, 3.0, 5));
}
