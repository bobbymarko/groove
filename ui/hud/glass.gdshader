shader_type canvas_item;
// "Liquid glass" panel: the world behind is frosted, bent a little at the
// rounded rim the way thick glass lenses what is under its edge, lifted by a
// soft tint, and caught by a thin highlight on the rim facing the light.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 22.0;
uniform vec4 tint : source_color = vec4(0.06, 0.09, 0.15, 0.38);
uniform float frost = 3.2;          // blur, as a mip level of the screen
uniform float lens = 18.0;          // pixels of bending at the rim

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 p = local - half_size;
	float r = min(radius, min(half_size.x, half_size.y));
	float d = sd_box(p, half_size, r);
	float aa = max(fwidth(d), 0.5);
	float mask = 1.0 - smoothstep(-aa, aa, d);
	if (mask <= 0.0) {
		discard;
	}
	vec2 n = normalize(vec2(sd_box(p + vec2(1.0, 0.0), half_size, r) - sd_box(p - vec2(1.0, 0.0), half_size, r),
			sd_box(p + vec2(0.0, 1.0), half_size, r) - sd_box(p - vec2(0.0, 1.0), half_size, r)) + 1e-5);
	float rim = smoothstep(-lens * 1.8, 0.0, d);          // 0 well inside .. 1 at the edge
	vec2 bend = -n * rim * rim * lens * SCREEN_PIXEL_SIZE;
	vec3 bg = vec3(textureLod(screen, SCREEN_UV + bend * 1.06, frost).r,
			textureLod(screen, SCREEN_UV + bend, frost).g,
			textureLod(screen, SCREEN_UV + bend * 0.94, frost).b);
	vec3 col = mix(bg, tint.rgb, tint.a);
	col += vec3(0.07) * rim * rim;                         // glass catches more light toward its edge
	col += vec3(0.04) * smoothstep(half_size.y, -half_size.y, p.y);   // a little brighter at the top
	float line = 1.0 - smoothstep(0.0, 1.4, abs(d + 0.9));
	float lit = clamp(dot(n, normalize(vec2(-0.55, -1.0))), 0.0, 1.0);
	float back = clamp(dot(n, normalize(vec2(0.55, 1.0))), 0.0, 1.0);
	col += line * (0.12 + 0.55 * lit + 0.2 * back);
	COLOR = vec4(col, mask);
}
