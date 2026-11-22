shader_type spatial;
// Boulders: the shared rock (rock.gdshaderinc) in world space, so the stone's
// grain keeps its real size whatever the boulder's; its beds tilted per
// boulder (boulders lie as they fell). Baked AO from COLOR.a darkens the
// underside; wet in rain.
#include "res://scene/real/wind.gdshaderinc"
#include "res://scene/real/rock.gdshaderinc"
#include "res://scene/real/shade.gdshaderinc"

uniform float snow = 0.0;
uniform float moss_amount = 0.0;

varying vec3 wp;
varying vec3 wn;
varying vec3 bed;
varying float plant_d;
varying float gone;
varying float above;   // metres above where the ground meets the boulder (a quarter of its size up from its middle)
varying float size;    // the boulder's size across, metres (the mesh is about 2 across at scale 1)

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
	float sz = length(MODEL_MATRIX[1].xyz);
	above = wp.y - o.y - 0.25 * sz;
	size = 2.0 * sz;
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
	// (sunlit granite reflects about a quarter of the light: without the ceiling the ridges of a pale boulder went near white)
	rock_surface(wp, dpx, dpy, n0, length(VERTEX), COLOR.rgb, bed, moss_amount, snow, size, 0.27, alb, nrm, rough, hgt);
	// The relief may lean a normal a long way, never past the face's own edge-on
	// (a face the sun is on must not shade as if turned from it).
	nrm = normalize(nrm + n0 * max(0.3 - dot(nrm, n0), 0.0));
	// A stone a hand or two across has no dark side to speak of: the ground
	// round it throws light back at it from every side, and the ambient light
	// here knows only the sky. Lit by its own normals, baked underside and
	// all, a face turned from the sun went pure black on bright ground. So a
	// small stone's normals lean toward straight up (it is lit much as the
	// ground it lies on) and its baked shade is eased, the more the smaller it is.
	float small = 1.0 - smoothstep(0.25, 1.0, size);
	nrm = normalize(mix(nrm, vec3(0.0, 1.0, 0.0), 0.9 * small) + vec3(0.0, 1e-4, 0.0));
	// (and, with no crevices of its own to darken it, it is taken down to the boulders' average)
	ALBEDO = alb * mix(mix(0.35, 1.0, COLOR.a), 0.55, 0.7 * small);
	ALBEDO *= mix(1.0, 0.62, rain_wet);
	ROUGHNESS = mix(rough, 0.25, rain_wet);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	// (the foot's shade reaches a share of the rock's own size: a fixed 0.45 m made a pebble all foot)
	Shade sh = shade_plant(wp, length(VERTEX), max(above, 0.0), 0.0, 0.5, min(0.45, 0.2 * size));
	SHADE_APPLY(sh)
}
