// Shared by the plant shaders' "bake" twins (PlantBake draws a plant into the
// flat-picture atlases with them): no light, the surface's own colour in one
// pass, its normal (as the bake camera sees it), shade and leafiness in another.
#ifdef BAKE
uniform int bake_channel = 0;      // 0 colour, 1 normal + shade

// Shade (0..1) and whether this is foliage (light shines through) in one number.
float bake_pack(float shade, float leafy) {
	return (leafy > 0.5 ? 0.5 : 0.0) + clamp(shade, 0.0, 1.0) * 0.49;
}

vec3 bake_out(vec3 albedo, vec3 view_normal, float shade, float leafy) {
	return bake_channel == 0 ? albedo : vec3(view_normal.xy * 0.5 + 0.5, bake_pack(shade, leafy));
}
#endif
