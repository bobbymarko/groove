shader_type canvas_item;
// Pixel-art post-process for the low-resolution scene texture: ordered dither,
// nearest-palette quantization, and a dark outline where neighbouring pixels differ.

uniform int palette_size = 24;
uniform vec3 palette[32];
uniform float dither_strength : hint_range(0.0, 0.2) = 0.09;
uniform float outline_threshold : hint_range(0.0, 1.5) = 0.45;
uniform float outline_darken : hint_range(0.0, 1.0) = 0.0;   // 0 = no outlines
uniform vec2 texel = vec2(0.0023474, 0.0041667);

const float BAYER[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0);

vec3 nearest(vec3 c) {
	float best = 1e9;
	vec3 out_c = c;
	for (int i = 0; i < palette_size; i++) {
		float d = distance(c, palette[i]);
		if (d < best) {
			best = d;
			out_c = palette[i];
		}
	}
	return out_c;
}

void fragment() {
	vec2 uv = UV;
	vec3 c = texture(TEXTURE, uv).rgb;
	// Edge strength from the four neighbours in the low-res image.
	vec3 n = texture(TEXTURE, uv + vec2(0.0, -texel.y)).rgb;
	vec3 s = texture(TEXTURE, uv + vec2(0.0, texel.y)).rgb;
	vec3 w = texture(TEXTURE, uv + vec2(-texel.x, 0.0)).rgb;
	vec3 e = texture(TEXTURE, uv + vec2(texel.x, 0.0)).rgb;
	float edge = distance(c, n) + distance(c, s) + distance(c, w) + distance(c, e);
	ivec2 px = ivec2(floor(uv / texel));
	float d = BAYER[(px.x % 4) + (px.y % 4) * 4] / 16.0 - 0.5;
	vec3 q = nearest(c + d * dither_strength);
	if (outline_darken > 0.0 && edge > outline_threshold) {
		q *= 1.0 - outline_darken;
	}
	COLOR = vec4(q, 1.0);
}
