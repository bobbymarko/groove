shader_type spatial;
render_mode unshaded, cull_disabled;
// A plain colour (the backdrops PlantBake puts behind each picture, so the
// atlas's small copies blur a crown's edge into leaf colour, not black).
void fragment() {
	ALBEDO = COLOR.rgb;
}
