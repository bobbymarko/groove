shader_type canvas_item;
// RealLook's light meter: the finished 3D picture, averaged down to a few
// hundred pixels (sixteen samples each). Out: the square root of each pixel's
// luminance (the root keeps the dark end's precision in eight bits).
uniform sampler2D frame : filter_linear, repeat_disable;
uniform vec2 cells = vec2(32.0, 18.0);

void fragment() {
	float acc = 0.0;
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			vec3 c = texture(frame, UV + ((vec2(float(i), float(j)) + 0.5) / 4.0 - 0.5) / cells).rgb;
			c = pow(max(c, vec3(0.0)), vec3(2.2));      // the picture is stored display-encoded
			acc += dot(c, vec3(0.2126, 0.7152, 0.0722));
		}
	}
	COLOR = vec4(vec3(sqrt(acc / 16.0)), 1.0);
}
