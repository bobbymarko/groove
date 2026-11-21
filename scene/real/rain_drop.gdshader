shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A raindrop as the eye sees it in a frame: a faint streak along its fall,
// soft at both ends and both edges, tinted by the light around it.

uniform vec3 tint = vec3(0.72, 0.77, 0.85);
uniform float opacity = 0.42;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * PI);
	ALBEDO = tint;
	ALPHA = opacity * across * across * along * COLOR.a;
}
