shader_type spatial;
render_mode cull_disabled;
// Solid small leaves and petals (ocotillo, a barrel cactus's flowers). Both sides use the authored normal (bent
// toward the crown's outside), light shines through (BACKLIGHT), baked AO from
// COLOR.a darkens the inside of a crown, snow settles on what faces up.
#include "res://scene/real/wind.gdshaderinc"
#define SHADE_BACKLIGHT
#include "res://scene/real/shade.gdshaderinc"

uniform float snow = 0.0;
uniform float translucency = 0.55;
uniform float sway = 1.0;
uniform float fringe = 0.0;   // needles: the blade's edge is cut into a serrated needle fringe

varying float ao;
varying vec3 tint;
varying vec3 wn;
varying float plant_d;
varying float gone;
varying vec3 wp;
varying float above;   // metres above the root

void vertex() {
	plant_d = plant_distance(MODEL_MATRIX);
	vec3 origin = MODEL_MATRIX[3].xyz;
	gone = far_gone(origin, plant_d);
	if (lod_gone(plant_d, gone)) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX += wind_offset(origin, UV2.x, UV2.y, TIME) * sway * sway_at(plant_d);
	}
	ao = COLOR.a;
	tint = INSTANCE_CUSTOM.a > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	above = wp.y - origin.y;
}

void fragment() {
	if (lod_drop(plant_d, gone, dither_moving(FRAGCOORD.xy, TIME, PROJECTION_MATRIX[3][3] > 0.5))) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (fringe > 0.0) {
		float teeth = vnoise(vec2(UV.y * 55.0, UV.x > 0.0 ? 3.1 : 7.7)) * 0.6 + vnoise(vec2(UV.y * 140.0, 1.3)) * 0.4;
		if (abs(UV.x) > 1.0 - fringe * teeth) {
			discard;
		}
	}
	vec3 alb = COLOR.rgb * tint * (fringe > 0.0 ? mix(0.75, 1.1, abs(UV.x)) : 1.0);
	// Snow lies in clumps on the upper faces of the outer branches.
	float clumps = smoothstep(0.35, 0.7, vnoise(wp.xz * 2.3 + wp.y * 1.7));
	float s = snow * smoothstep(0.55, 0.9, wn.y) * smoothstep(0.35, 0.75, ao) * clumps;
	alb = mix(alb, vec3(0.88, 0.9, 0.95), s);
	ALBEDO = alb * mix(0.3, 1.0, ao);
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	ALBEDO *= mix(1.0, 0.82, rain_wet);
	ROUGHNESS = mix(mix(0.72, 0.6, s), 0.32, rain_wet);
	SPECULAR = 0.35;
	BACKLIGHT = alb * translucency * (1.0 - s) * mix(0.4, 1.0, ao);
	Shade sh = shade_plant(wp, length(VERTEX), above, 0.0, 0.35, 0.6);
	SHADE_APPLY(sh)
}
