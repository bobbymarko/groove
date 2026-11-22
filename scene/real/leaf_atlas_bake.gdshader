shader_type spatial;
render_mode unshaded, cull_disabled;
// Draws the leaf atlas's source shapes (PlantGen.atlas_cell: leaves, needles and
// twigs as real geometry, seen from straight above): their grey in one pass,
// their normal and shade in another.
uniform int bake_channel = 0;

varying vec3 vn;

void vertex() {
	vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(vn);
	if (n.z < 0.0) {
		n = -n;
	}
	ALBEDO = bake_channel == 0 ? COLOR.rgb : vec3(n.xy * 0.5 + 0.5, COLOR.a);
}
