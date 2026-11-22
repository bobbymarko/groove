// Cactus skin: waxy green with the ribs' grooves darker (COLOR.a), fine spine
// specks, and for cholla (`fuzz`) a coat of pale spines that glows against the light.
#include "res://scene/real/wind.gdshaderinc"
#include "res://scene/real/bake.gdshaderinc"

uniform float fuzz = 0.0;
uniform vec3 fuzz_color = vec3(0.92, 0.86, 0.6);

varying float plant_d;
varying float gone;

void vertex() {
#ifndef BAKE
	plant_d = plant_distance(MODEL_MATRIX);
	gone = far_gone(MODEL_MATRIX[3].xyz, plant_d);
	if (lod_gone(plant_d, gone)) {
		VERTEX = vec3(0.0);
	}
#endif
}

void fragment() {
#ifndef BAKE
	if (lod_drop(plant_d, gone, dither_moving(FRAGCOORD.xy, TIME, PROJECTION_MATRIX[3][3] > 0.5))) {
		discard;
	}
#endif
	vec3 alb = COLOR.rgb * mix(0.45, 1.0, COLOR.a) * (0.9 + 0.18 * vnoise(UV * vec2(6.0, 24.0)));
	float speck = step(0.9, hash21(floor(UV * vec2(45.0, 60.0))));
	alb = mix(alb, vec3(0.78, 0.74, 0.6), speck * 0.35 * (1.0 - fuzz));
	alb = mix(alb, fuzz_color, fuzz * 0.45);
#ifdef BAKE
	ALBEDO = bake_out(alb, normalize(NORMAL), 1.0, 0.0);
#else
	ALBEDO = alb * mix(1.0, 0.75, rain_wet);
	ROUGHNESS = mix(mix(0.5, 0.85, fuzz), 0.3, rain_wet);
	SPECULAR = 0.45;
	BACKLIGHT = fuzz_color * fuzz * 0.7;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = fuzz_color * rim * fuzz * 0.12;
#endif
}
