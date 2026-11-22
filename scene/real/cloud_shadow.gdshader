shader_type canvas_item;
render_mode unshaded, blend_disabled;
// RealShade's cloud map: for each spot of a plane at the eye's height, how much
// sunlight comes through the clouds above it (1 clear .. 0 under a thick
// cloud), integrated along the ray toward the sun through the cloud layer.
// The cloud shapes and their settings are the sky's own (cloud_shape.gdshaderinc,
// kept in step by RealLook), so the shadows lie under the clouds seen and
// drift with them. Kilometres, as in the sky.
#include "res://scene/real/cloud_shape.gdshaderinc"

uniform vec3 light_dir = vec3(0.0, 0.5, 0.86);
uniform float cloud_density = 0.19;
uniform vec2 corner_km;          // world xz of the map's corner
uniform float size_km = 24.0;
uniform float ref_km = 0.25;     // altitude of the plane the map lies on
uniform bool ready = false;      // the noise textures are baked

const int STEPS = 6;

void fragment() {
	if (!ready) {
		COLOR = vec4(1.0);
	} else {
		vec3 L = light_dir;
		L.y = max(L.y, 0.08);
		L = normalize(L);
		vec3 W0 = vec3(corner_km.x + UV.x * size_km, ref_km, corner_km.y + UV.y * size_km);
		float t0 = max(cloud_bottom - ref_km, 0.0) / L.y;
		float t1 = max(cloud_top - ref_km, 0.0) / L.y;
		float dt = (t1 - t0) / float(STEPS);
		float od = 0.0;
		// The shapes' fine noise is far smaller than a texel: one sample a step
		// would alias into grain. So each step takes four, spread over the
		// texel and half its neighbours (turned a little each step), and the
		// shadow comes out soft, as a cloud's shadow on the ground is.
		float texel = size_km * SCREEN_PIXEL_SIZE.x;
		for (int i = 0; i < STEPS; i++) {
			vec3 W = W0 + L * (t0 + (float(i) + 0.5) * dt);
			float a = float(i) * 0.785;
			vec2 u = vec2(cos(a), sin(a)) * texel * 0.7;
			vec2 v = vec2(-u.y, u.x);
			float b = 0.0;
			for (int k = 0; k < 4; k++) {
				vec2 o = (k == 0 ? u : (k == 1 ? -u : (k == 2 ? v : -v)));
				vec3 Wk = W + vec3(o.x, 0.0, o.y);
				b += cloud_base(Wk, height_frac(Wk), weather_at(Wk), 0.0);
			}
			od += b * 0.25 * dt;
		}
		// The sky thins the clouds' edges with finer noise; their shadows'
		// edges likewise (a little of the depth goes before any light is lost).
		od = max(od * 45.0 * cloud_density * 0.8 - 0.15, 0.0);
		COLOR = vec4(vec3(exp(-od)), 1.0);
	}
}
