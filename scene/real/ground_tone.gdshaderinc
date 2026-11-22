// The ground's broad colour, shared by real_ground.gdshader and the meadow
// (real_grass.gdshader), so grass roots take exactly the colour of the bare
// ground round them, and beyond the meadow's last ring the ground carries the
// meadow's own colour: no edge where the grass ends.

// Large-scale tint over the field (lush and dry patches, lighter and darker
// stretches): n1 is the ground noise at p * 0.011, n2 at p * 0.07 + 0.3.
vec3 ground_macro(int look, float n1, float n2) {
	if (look == 1) {
		return mix(vec3(0.88, 1.06, 0.86), vec3(1.14, 1.0, 0.76), smoothstep(0.35, 0.75, n1)) * (0.8 + 0.4 * n2);
	}
	return vec3((0.88 + 0.24 * n2) * (0.94 + 0.12 * n1));
}

// How much the bare field gives way to the meadow's colour at `dist` metres
// from the eye: none close by, growing as the meadow's outer rings thin out
// (more of the field shows between fewer blades), all of it a little past
// where the last ring has shrunk away (`end`, RealGrass's).
float meadow_share(float dist, float amount, float end) {
	return amount * smoothstep(end * 0.3, end + 4.0, dist);
}

// The meadow seen from afar: its blades' colour, a little darker for the
// shade between them.
vec3 meadow_tone(vec3 blades, float n3) {
	return blades * 0.78 * (0.88 + 0.24 * n3);
}
