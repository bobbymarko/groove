// Leaf cards: a crown is built from flat cards, each showing a whole cluster of
// leaves (or a spruce bough, or a spray of bare twigs) from the leaf atlas
// PlantBake draws at startup. The card's own normal carries the cluster's
// relief; it is bent toward the outside of the crown (CUSTOM0) so the crown
// shades as one rounded mass; light shines through (BACKLIGHT); baked AO from
// COLOR.a darkens the inside; snow settles on what faces up.
// Vertices with UV.x < 0 are solid wood (a distant tree's trunk and limbs
// ride in the same surface, to halve its draws).
#include "res://scene/real/wind.gdshaderinc"
#include "res://scene/real/bake.gdshaderinc"

uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_data : filter_linear_mipmap_anisotropic, repeat_disable;   // rg normal, b shade (wood under 0.5), a cover
uniform float snow = 0.0;
uniform float translucency = 0.55;
uniform float roundness = 0.6;                   // how far the cards' normals bend to the crown's
uniform vec3 wood_color = vec3(0.2, 0.16, 0.12);  // twigs drawn in a cluster
uniform float shade_own = 0.9;                   // a tree's own crown in the canopy map (0: a bush, which adds none)

varying float ao;
varying vec3 tint;
varying float plant_d;
varying float gone;
varying vec3 wp;
varying vec3 v_bent;
varying vec3 v_tan;
varying vec3 v_bin;
varying vec3 v_face;
varying float above;    // metres above the root

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
#ifdef BAKE
	wp = VERTEX;
	tint = vec3(1.0);
#else
	plant_d = plant_distance(MODEL_MATRIX);
	gone = far_gone(origin, plant_d);
	if (lod_gone(plant_d, gone)) {
		VERTEX = vec3(0.0);
	} else {
#ifndef STILL
		VERTEX += wind_offset(origin, UV2.x, UV2.y, TIME) * sway_at(plant_d);
#endif
	}
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = INSTANCE_CUSTOM.a > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	above = wp.y - origin.y;
#endif
	ao = COLOR.a;
	mat3 mv = mat3(MODELVIEW_MATRIX);
	v_bent = normalize(mv * CUSTOM0.xyz);
	v_tan = normalize(mv * TANGENT);
	v_face = normalize(mv * NORMAL);
	v_bin = cross(v_face, v_tan);
}

void fragment() {
#ifndef BAKE
	if (lod_drop(plant_d, gone, dither_moving(FRAGCOORD.xy, TIME, PROJECTION_MATRIX[3][3] > 0.5))) {
		discard;
	}
#endif
	vec3 alb;
	vec3 n;
	float shade = ao;
	float leafy = 1.0;
	if (UV.x < -0.5) {
		// Solid wood.
		alb = COLOR.rgb * (0.7 + 0.5 * vnoise(wp.xy * vec2(9.0, 2.0) + wp.z * 5.0));
		n = normalize(v_face) * (FRONT_FACING ? 1.0 : -1.0);
		leafy = 0.0;
	} else {
		vec4 data = texture(leaf_data, UV);
#ifdef BAKE
		float cut = 0.5;
#else
		// Far off the atlas's small copies blur thin leaves to a faint haze: keep
		// more of it, so a crown holds its mass instead of thinning away.
		float cut = mix(0.5, 0.28, smoothstep(12.0, 70.0, plant_d));
#endif
		if (data.a < cut) {
			discard;
		}
		vec3 tex = texture(leaf_albedo, UV).rgb;
		float wood = step(data.b, 0.47);
		float tex_shade = wood > 0.5 ? clamp(data.b * 2.1, 0.0, 1.0) : clamp((data.b - 0.5) * 2.0, 0.0, 1.0);
		alb = tex * mix(COLOR.rgb * tint, wood_color, wood);
		shade *= mix(0.45, 1.0, tex_shade);
		leafy = 1.0 - wood;
		vec3 t = data.rgb * 2.0 - 1.0;
		t.z = sqrt(max(1.0 - dot(t.xy, t.xy), 0.0));
		vec3 nc = normalize(v_tan) * t.x + normalize(v_bin) * t.y + normalize(v_face) * t.z;
		if (!FRONT_FACING) {
			nc = -nc;
		}
		n = normalize(mix(nc, normalize(v_bent), roundness));
	}
	vec3 wn = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	// Snow lies in clumps on the upper faces of the outer branches.
	float s = 0.0;
	if (snow > 0.0) {
		float clumps = smoothstep(0.3, 0.62, vnoise(wp.xz * 2.3 + wp.y * 1.7));
		s = snow * 1.6 * smoothstep(0.4, 0.8, wn.y) * smoothstep(0.3, 0.7, ao) * clumps;
		s = min(s, 1.0);
		alb = mix(alb, vec3(0.88, 0.9, 0.95), s);
	}
	vec3 lit = alb * mix(0.3, 1.0, shade);
#ifdef BAKE
	ALBEDO = bake_out(lit, n, shade, leafy * (1.0 - s));
#else
	NORMAL = n;
	ALBEDO = lit * mix(1.0, 0.82, rain_wet);
	AO = shade;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = mix(mix(0.72, 0.6, s), 0.32, rain_wet);
	SPECULAR = 0.35;
	BACKLIGHT = alb * translucency * leafy * (1.0 - s) * mix(0.4, 1.0, shade);
	Shade sh = shade_plant(wp, length(VERTEX), above, shade_own, 0.3, 0.5);
	SHADE_APPLY(sh)
#endif
}
