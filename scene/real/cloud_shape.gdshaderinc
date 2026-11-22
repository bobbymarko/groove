// The clouds' large shapes, shared by the sky (real_sky.gdshader, which
// raymarches them) and their shadows on the land (cloud_shadow.gdshader), so
// a shadow lies under the very cloud overhead. After Cloudscape (MIT,
// Fishypants/cloudscape). Units are kilometres; W is a point with y its
// altitude above the planet's surface.

uniform sampler3D shape_tex : filter_linear, repeat_enable;
uniform sampler2D weather_tex : filter_linear, repeat_enable;

uniform float coverage = 0.51;
uniform float cloud_type = 1.0;
uniform float cloud_bottom = 1.5;
uniform float cloud_top = 4.4;
uniform vec3 wind = vec3(0.0);                  // accumulated wind offset, km
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);

const float Rg = 6360.0;
const float WEATHER_SCALE = 45.0;
const float SHAPE_SCALE = 2.0;

float sat(float x) { return clamp(x, 0.0, 1.0); }
float remap(float v, float a, float b, float c, float d) { return c + (v - a) / (b - a) * (d - c); }

float height_frac(vec3 W) {
	return (length(W + vec3(0.0, Rg, 0.0)) - Rg - cloud_bottom) / (cloud_top - cloud_bottom);
}

vec2 weather_at(vec3 W) {
	vec4 w = textureLod(weather_tex, (W.xz - wind.xz * 0.6) / WEATHER_SCALE, 0.0);
	float thr = 1.0 - coverage * 1.3;
	return vec2(smoothstep(thr, thr + 0.45, w.r), sat(cloud_type + (w.g - 0.5) * 0.7));
}

vec4 profile(float type) {
	vec4 st = vec4(0.0, 0.07, 0.12, 0.25);
	vec4 sc = vec4(0.0, 0.12, 0.35, 0.55);
	vec4 cu = vec4(0.0, 0.10, 0.55, 1.00);
	return type < 0.5 ? mix(st, sc, type * 2.0) : mix(sc, cu, type * 2.0 - 1.0);
}

float cloud_base(vec3 W, float h, vec2 wt, float lod) {
	if (wt.x <= 0.001 || h < 0.0 || h > 1.0) return 0.0;
	vec3 p = W - wind + wind_dir * h * 0.6;
	vec4 n = textureLod(shape_tex, p / SHAPE_SCALE, lod);
	float fbm = dot(n.gba, vec3(0.625, 0.25, 0.125));
	float base = remap(n.r, fbm - 1.0, 1.0, 0.0, 1.0);
	vec4 g = profile(wt.y);
	base *= smoothstep(g.x, g.y, h) * (1.0 - smoothstep(g.z, g.w, h));
	float hn = sat((h - g.y) / max(g.w - g.y, 1e-3));
	float cov = wt.x * mix(1.0, 0.5, hn * hn);
	base = remap(base, 1.0 - cov, 1.0, 0.0, 1.0) * cov;
	return sat(base);
}
