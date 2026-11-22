shader_type spatial;
render_mode cull_disabled;
// A tree far away: one flat card that turns to face the eye, showing the
// picture of that tree PlantBake drew from the nearest of `frames` directions
// round its trunk (two neighbours dither into each other as the view moves
// round). The picture carries the tree's normals and shade, so it takes the
// sun, sky light and backlight like the real crown, and snow and leaf colour
// are already in it. In the sun's shadow pass the card faces the sun instead.
// Per instance: the tree's own transform (turn and size), INSTANCE_CUSTOM rgb
// its tint and a its row in the atlas + 1.
#include "res://scene/real/wind.gdshaderinc"
#define SHADE_BACKLIGHT
#include "res://scene/real/shade.gdshaderinc"

uniform sampler2D imp_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D imp_data : filter_linear_mipmap, repeat_disable;   // rg normal, b shade (+0.5 leaf), a cover
uniform vec3 sizes[24];          // per row: picture width, height (metres), bottom edge against the root
uniform float frames = 12.0;
uniform vec2 rows[24];           // per row: its top and height in the atlas
uniform float translucency = 0.5;

varying float plant_d;
varying float gone;
varying vec3 tint;
varying flat float row;
varying flat float frame0;
varying flat float frame_t;
varying vec3 v_right;
varying vec3 v_face;
varying vec3 v_up;
varying vec3 v_wp;
varying float above;    // metres above the root

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	plant_d = distance(origin, eye_pos);
	gone = far_gone(origin, plant_d);
	row = floor(INSTANCE_CUSTOM.a - 0.5);
	tint = INSTANCE_CUSTOM.rgb;
	vec3 sz = sizes[int(row)];
	float s = length(MODEL_MATRIX[0].xyz);
	// Orthographic projection: this is one of the sun's shadow maps.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	vec3 f = shadow_pass ? INV_VIEW_MATRIX[2].xyz : eye_pos - origin;
	f.y = 0.0;
	f = dot(f, f) > 1e-6 ? normalize(f) : vec3(0.0, 0.0, 1.0);
	vec3 right = vec3(f.z, 0.0, -f.x);
	// Which side of the tree is toward the viewer, in the tree's own frame.
	float phi = atan(dot(MODEL_MATRIX[0].xyz, f), dot(MODEL_MATRIX[2].xyz, f));
	float ff = fract(phi / TAU + 1.0) * frames;
	frame0 = floor(ff);
	frame_t = ff - frame0;
	vec3 wpos = origin + right * (UV.x - 0.5) * sz.x * s + vec3(0.0, (1.0 - UV.y) * sz.y + sz.z, 0.0) * s;
	if (lod_gone(plant_d, gone)) {
		wpos = origin;
	}
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
	v_wp = wpos;
	above = wpos.y - origin.y;
	v_right = (VIEW_MATRIX * vec4(right, 0.0)).xyz;
	v_up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	v_face = (VIEW_MATRIX * vec4(f, 0.0)).xyz;
}

void fragment() {
	if (lod_drop(plant_d, gone, dither_moving(FRAGCOORD.xy, TIME, PROJECTION_MATRIX[3][3] > 0.5))) {
		discard;
	}
	// Between two pictures: each pixel takes one or the other.
	float pick = step(dither_moving(FRAGCOORD.xy + vec2(37.0, 17.0), TIME, PROJECTION_MATRIX[3][3] > 0.5), smoothstep(0.25, 0.75, frame_t));
	float fr = mod(frame0 + pick, frames);
	vec2 band = rows[int(row)];
	vec2 scale = vec2(1.0 / frames, band.y);
	vec2 uv = vec2((fr + UV.x) * scale.x, band.x + UV.y * scale.y);
	vec2 dx = dFdx(UV) * scale;
	vec2 dy = dFdy(UV) * scale;
	vec4 data = textureGrad(imp_data, uv, dx, dy);
	if (data.a < 0.4) {
		discard;
	}
	data.rgb /= max(data.a, 0.05);
	vec3 alb = textureGrad(imp_albedo, uv, dx, dy).rgb * tint;
	float leafy = step(0.5, data.b);
	float shade = clamp((data.b - leafy * 0.5) / 0.49, 0.0, 1.0);
	vec3 t = vec3(data.rg * 2.0 - 1.0, 0.0);
	t.z = sqrt(max(1.0 - dot(t.xy, t.xy), 0.0));
	NORMAL = normalize(v_right * t.x + v_up * t.y + v_face * t.z);
	ALBEDO = alb * mix(1.0, 0.82, rain_wet);
	AO = shade;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = mix(0.72, 0.32, rain_wet);
	SPECULAR = 0.35;
	BACKLIGHT = alb / mix(0.3, 1.0, shade) * translucency * leafy * mix(0.4, 1.0, shade);
	// As the live tree's leaves (real_leaf): the same cover, by the same height above the root.
	Shade sh = shade_plant(v_wp, length(VERTEX), above, 0.9, 0.3, 0.5);
	SHADE_APPLY(sh)
}
