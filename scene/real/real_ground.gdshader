shader_type spatial;
render_mode cull_back;
// Ground for the realistic look. Everything comes from position, slope and the
// distance from the trail centre (UV.x, written by TerrainStreamer): the trail
// with a ragged edge and worn wheel line, the field (snow, grass or sand),
// rock on steep ground, all broken up by noise at four scales.

#include "res://scene/real/wind.gdshaderinc"

uniform int ground = 0;      // 0 snow, 1 grass, 2 sand
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float trail_half_width = 0.75;

varying vec3 wpos;
varying float lat;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lat = UV.x;
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

void fragment() {
	vec2 p = wpos.xz;
	float n1 = n(p * 0.011);
	float n2 = n(p * 0.07 + 0.3);
	float n3 = n(p * 0.45 + 0.7);
	float n4 = n(p * 2.9 + 0.1);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - wn.y;
	float a = abs(lat);
	float edge = trail_half_width + (n3 - 0.5) * 0.35 + (n2 - 0.5) * 0.25;
	float trail = 1.0 - smoothstep(edge - 0.1, edge + 0.15, a);
	float rut = 1.0 - smoothstep(0.0, 0.22, abs(a - 0.0));      // the wheel line down the middle
	float rock = smoothstep(0.38, 0.55, slope + (n2 - 0.5) * 0.25);

	vec3 field;
	vec3 path;
	float field_rough;
	float path_rough;
	float bump;
	if (ground == 0) {
		field = vec3(0.86, 0.89, 0.94) * (0.94 + 0.06 * n2) - vec3(0.03, 0.02, 0.0) * smoothstep(0.55, 0.75, n3);
		path = mix(vec3(0.62, 0.62, 0.64), vec3(0.5, 0.48, 0.47), rut * 0.6) * (0.85 + 0.25 * n4);
		field_rough = 0.6;
		path_rough = 0.75;
		bump = mix(0.35, 0.8, trail);
	} else if (ground == 1) {
		vec3 lush = vec3(0.07, 0.13, 0.035);
		vec3 dry = vec3(0.15, 0.16, 0.06);
		field = mix(lush, dry, smoothstep(0.35, 0.75, n1)) * (0.75 + 0.45 * n3) * (0.85 + 0.3 * n4);
		path = mix(vec3(0.27, 0.2, 0.13), vec3(0.2, 0.15, 0.1), rut * 0.7) * (0.75 + 0.45 * n4);
		field_rough = 0.95;
		path_rough = 0.9;
		bump = 1.0;
	} else {
		field = vec3(0.58, 0.32, 0.14) * (0.85 + 0.2 * n2) * (0.93 + 0.1 * n4);
		path = vec3(0.5, 0.29, 0.15) * (0.85 + 0.2 * n4);
		field_rough = 0.92;
		path_rough = 0.9;
		bump = 0.7;
	}
	vec3 stone = vec3(0.36, 0.35, 0.34) * (0.55 + 0.6 * n4) * (0.8 + 0.3 * n2);
	vec3 col = mix(field, path, trail);
	col = mix(col, stone, rock * (1.0 - trail));
	float rough = mix(mix(field_rough, path_rough, trail), 0.8, rock);
	vec3 nm1 = texture(noise_nrm, p * 0.45).xyz;
	vec3 nm2 = texture(noise_nrm, p * 2.9).xyz;
	vec3 nmap = normalize(mix(nm1, nm2, 0.55));
	float depth = bump * mix(1.0, 2.0, rock);
	// Rain: soil darkens and shines, water collects in the trail's ruts and dips.
	float wet = ground == 0 ? 0.0 : rain_wet;
	col *= mix(1.0, ground == 2 ? 0.7 : 0.58, wet);
	rough = mix(rough, 0.35, wet);
	float pool = wet * smoothstep(0.6, 0.72, n3 * 0.65 + rut * 0.45 + (1.0 - n2) * 0.25) * trail
			* smoothstep(0.42, 0.58, n(p * 0.16 + 5.0));   // separate pools, not one stream
	if (pool > 0.0) {
		vec2 rip = ripples(p, TIME) * smoothstep(30.0, 6.0, length(VERTEX));
		col = mix(col, col * 0.3, pool);
		rough = mix(rough, 0.03, pool);
		nmap = normalize(mix(nmap, vec3(0.5 + rip.x * 0.35, 0.5 + rip.y * 0.35, 1.0), pool));
		depth = mix(depth, 1.0, pool);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.4, 0.5, wet);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = depth;
}
