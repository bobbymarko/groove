shader_type canvas_item;
render_mode blend_add, unshaded;
// RealShade's canopy and contact maps: one soft disc per blob, added up in a
// float target. Each instance's custom data is the blob (world x, z, radius in
// metres, value): a positive value is leaf cover (red), a negative one contact
// with the ground (green). The quad is placed here, in the map's texels.

uniform vec2 origin;           // world xz of the map's corner (texel 0)
uniform float px_per_m = 2.0;
uniform float min_radius = 0.75;   // smaller discs are drawn this wide, as faint as they keep the same sum (no flicker as the map moves)
uniform float contact = 1.0;       // 0: this map leaves contact out

varying vec2 local;
varying vec2 value;

void vertex() {
	vec4 b = INSTANCE_CUSTOM;
	float r = max(b.z, min_radius);
	bool touch = b.w < 0.0;
	float amp = abs(b.w) * (b.z * b.z) / (r * r);
	value = touch ? vec2(0.0, amp * contact) : vec2(amp, 0.0);
	local = VERTEX;
	VERTEX = (b.xy + VERTEX * r - origin) * px_per_m;
	if (touch && contact <= 0.0) {
		VERTEX = vec2(-100.0);
	}
}

void fragment() {
	float d2 = dot(local, local);
	// Crowns: a rounded dome of cover. Contact: full at the foot, gone at the rim.
	float dome = max(1.0 - d2, 0.0);
	dome *= dome;
	float foot = 1.0 - smoothstep(0.2, 1.0, d2);
	COLOR = vec4(value.x * dome, value.y * foot, 0.0, 1.0);
}
