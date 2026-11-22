shader_type spatial;
// Boulders: the shared rock (rock.gdshaderinc) in world space, so the stone's
// grain keeps its real size whatever the boulder's; its beds tilted per
// boulder (boulders lie as they fell). Baked AO from COLOR.a darkens the
// underside; wet in rain.
#include "res://scene/real/wind.gdshaderinc"
#include "res://scene/real/rock.gdshaderinc"

uniform float snow = 0.0;
uniform float moss_amount = 0.0;

varying vec3 wp;
varying vec3 wn;
varying vec3 bed;
varying float plant_d;
varying float gone;

void vertex() {
	plant_d = plant_distance(MODEL_MATRIX);
	vec3 o = MODEL_MATRIX[3].xyz;
	gone = far_gone(o, plant_d);
	if (lod_gone(plant_d, gone)) {
		VERTEX = vec3(0.0);
	}
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float a = hash21(o.xz) * TAU;
	bed = normalize(vec3(cos(a), 2.2 + hash21(o.zx + 3.0) * 2.0, sin(a)));
}

void fragment() {
	vec3 dpx = dFdx(wp);
	vec3 dpy = dFdy(wp);
	if (lod_drop(plant_d, gone, dither_moving(FRAGCOORD.xy, TIME, PROJECTION_MATRIX[3][3] > 0.5))) {
		discard;
	}
	vec3 n0 = normalize(wn) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 alb;
	vec3 nrm;
	float rough;
	float hgt;
	rock_surface(wp, dpx, dpy, n0, length(VERTEX), COLOR.rgb, bed, moss_amount, snow, alb, nrm, rough, hgt);
	ALBEDO = alb * mix(0.35, 1.0, COLOR.a);
	ALBEDO *= mix(1.0, 0.62, rain_wet);
	ROUGHNESS = mix(rough, 0.25, rain_wet);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
