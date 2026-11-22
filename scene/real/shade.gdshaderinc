// Light and shade at the scale of the land, for every lit shader of the
// realistic look (R43 stage 5; the maps are RealShade's):
//  - under leaf cover a spot sees less of the sky (ambient light), tinted a
//    little green under leaves, and beyond the reach of the sun's real shadow
//    maps it gets less sun too, so far woods have a dark floor;
//  - where trunks, rocks and bushes meet the ground it darkens (contact);
//  - the clouds overhead take sunlight away where their shadows fall.
// A shader includes this, works out a Shade for its pixel (shade_ground,
// shade_plant), and ends its fragment() with SHADE_APPLY(that Shade).
//
// How: ambient light can only be scaled through ALBEDO (and AO, which SSAO
// overrides with its minimum), and Godot gives no hook on direct light except
// a light() of one's own. So ALBEDO is scaled by the ambient factor, and the
// light() below (Godot's own Lambert diffuse, backlight and Schlick-GGX
// specular, as in its scene_forward_lights) divides that back out of direct
// light and applies the direct factor (the sun only; other lights are left
// as they are). Specular keeps the material's own strength (shade_f0); only
// the sky's reflection is dimmed under cover.
#ifndef SHADE_INC
#define SHADE_INC

global uniform sampler2D shade_near : filter_linear, repeat_disable;    // r leaf cover (summed), g contact
global uniform sampler2D shade_far : filter_linear, repeat_disable;     // r leaf cover
global uniform sampler2D shade_cloud : filter_linear, repeat_disable;   // r sunlight through the clouds
global uniform vec4 shade_near_at;   // xy world xz of the map's corner, z 1 / its size in metres, w how far from its middle it holds
global uniform vec4 shade_far_at;
global uniform vec4 shade_cloud_at;  // xy corner, z 1 / size, w the height of the plane it lies on
global uniform vec4 shade_amount;    // x canopy (0 off), y cloud shadow strength, z leaf green, w the sun's shadow reach
global uniform vec4 shade_trees;     // xy the eye's x and z, z where trees are gone (metres from it), w the same along the trail (strip rides)
global uniform vec3 sun_dir;         // toward the sun or moon

struct Shade {
	vec3 amb;       // ambient factor
	float sun;      // direct sunlight factor
	float contact;  // 0..1 next to something standing on the ground
	float cover;    // leaf cover overhead (0 open; ~1 under one crown; more in a wood)
};

// Leaf cover (x) and contact (y) at p: the near map where it holds, the far map beyond.
vec2 shade_cover(vec2 p) {
	if (shade_amount.x <= 0.0) {
		return vec2(0.0);
	}
	vec2 dn = abs(p - shade_near_at.xy - 0.5 / shade_near_at.z);
	float to_far = smoothstep(shade_near_at.w - 16.0, shade_near_at.w, max(dn.x, dn.y));
	vec2 c = vec2(0.0);
	if (to_far < 1.0) {
		c = textureLod(shade_near, (p - shade_near_at.xy) * shade_near_at.z, 0.0).rg;
	}
	if (to_far > 0.0) {
		vec2 df = abs(p - shade_far_at.xy - 0.5 / shade_far_at.z);
		float gone = smoothstep(shade_far_at.w - 60.0, shade_far_at.w, max(df.x, df.y));
		float f = textureLod(shade_far, (p - shade_far_at.xy) * shade_far_at.z, 0.0).r * (1.0 - gone);
		c = mix(c, vec2(f, 0.0), to_far);
	}
	return c;
}

// Sunlight left by the clouds at wp: the cloud map is a plane at one height,
// so wp is first carried along its ray to the sun up (or down) to that plane.
float shade_cloud_sun(vec3 wp) {
	if (shade_amount.y <= 0.0) {
		return 1.0;
	}
	float ly = max(sun_dir.y, 0.08);
	vec2 q = wp.xz + sun_dir.xz / ly * (shade_cloud_at.w - wp.y);
	vec2 uv = (q - shade_cloud_at.xy) * shade_cloud_at.z;
	float edge = smoothstep(0.4, 0.49, max(abs(uv.x - 0.5), abs(uv.y - 0.5)));
	float t = textureLod(shade_cloud, uv, 0.0).r;
	return mix(1.0, t, shade_amount.y * (1.0 - edge));
}

// The general case, from the cover (shade_cover) already looked up at wp.
// dist: metres from the eye. open: 0 at the foot of the
// wood .. 1 up in the light above it. own: cover a tree's own crown adds over
// itself (its leaves already carry their own baked shade).
Shade shade_from(vec2 c, vec3 wp, float dist, float open, float own) {
	// No shade where the trees that cast it are no longer drawn (RealFlora:
	// trees dither away over the last 60 m before their end).
	float trees = 1.0 - clamp(max(dist - shade_trees.z, abs(wp.z - shade_trees.y) - shade_trees.w) / 60.0 + 1.0, 0.0, 1.0);
	Shade s;
	s.cover = max(c.x * trees - own, 0.0) * (1.0 - open);
	s.contact = min(c.y, 1.0);
	float occ = 1.0 - exp(-s.cover);
	s.amb = (1.0 - 0.7 * occ) * mix(vec3(1.0), vec3(0.84, 1.0, 0.78), occ * shade_amount.z);
	s.sun = shade_cloud_sun(wp);
	// Within the shadow maps' reach the trees' real shadows already fall;
	// beyond it the crowns' cover shades the sun too, looked up where the
	// sun's ray passes through them (a crown's middle is ~7 m up).
	float beyond = smoothstep(shade_amount.w * 0.75, shade_amount.w, dist);
	if (beyond > 0.0 && open < 1.0) {
		vec2 toward = sun_dir.xz / max(sun_dir.y, 0.33) * 7.0 * (1.0 - open);
		float lit = max(shade_cover(wp.xz + toward).x * trees - own, 0.0) * (1.0 - open);
		s.sun *= mix(1.0, exp(-1.8 * lit), beyond);
	}
	return s;
}

Shade shade_at(vec3 wp, float dist, float open, float own) {
	return shade_from(shade_cover(wp.xz), wp, dist, open, own);
}

// The ground (and grass, bridges): cover overhead and contact round what stands on it.
Shade shade_ground_from(vec2 c, vec3 wp, float dist) {
	Shade s = shade_from(c, wp, dist, 0.0, 0.0);
	s.amb *= 1.0 - 0.35 * s.contact;
	s.sun *= 1.0 - 0.1 * s.contact;
	return s;
}

Shade shade_ground(vec3 wp, float dist) {
	return shade_ground_from(shade_cover(wp.xz), wp, dist);
}

// A plant's surface at h metres above its root, darker toward its foot
// (base: how much at the very foot, over `foot` metres).
Shade shade_plant(vec3 wp, float dist, float h, float own, float base, float foot) {
	Shade s = shade_at(wp, dist, smoothstep(1.5, 13.0, h), own);
	float k = 1.0 - base * (1.0 - smoothstep(0.0, foot, h));
	s.amb *= k;
	s.sun *= mix(1.0, k, 0.4);
	return s;
}

varying vec4 shade_lt;   // rgb: 1 / the ambient factor ALBEDO was scaled by; a: the direct sunlight factor
varying float shade_f0;  // the material's own specular reflectance

// The last thing in fragment(), after ALBEDO and SPECULAR are set.
#define SHADE_APPLY(S) ALBEDO *= S.amb; shade_lt = vec4(1.0 / max(S.amb, vec3(0.05)), S.sun); shade_f0 = 0.16 * SPECULAR * SPECULAR; SPECULAR *= sqrt(dot(S.amb, vec3(0.3333)));

float shade_schlick(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

#ifndef SHADE_NO_LIGHT
void light() {
	vec3 gain = shade_lt.rgb * (LIGHT_IS_DIRECTIONAL ? shade_lt.a : 1.0);
	float cNdotL = max(dot(NORMAL, LIGHT), 0.0);
	float cNdotV = max(dot(NORMAL, VIEW), 1e-4);
	vec3 H = normalize(VIEW + LIGHT);
	float cLdotH = clamp(dot(LIGHT, H), 0.0, 1.0);
	// Lambert diffuse (Godot's default for a shader with no diffuse_ render mode).
	float diff = (1.0 / PI) * cNdotL;
	vec3 lc = LIGHT_COLOR * ATTENUATION;
	DIFFUSE_LIGHT += lc * gain * diff;
#ifdef SHADE_BACKLIGHT
	DIFFUSE_LIGHT += lc * gain * (1.0 / PI - diff) * BACKLIGHT;
#endif
	// Schlick-GGX specular (a dielectric).
	if (ROUGHNESS > 0.0) {
		float cNdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
		float a = ROUGHNESS * ROUGHNESS;
		float ah = cNdotH * a;
		float k = a / (1.0 - cNdotH * cNdotH + ah * ah);
		float D = min(k * k * (1.0 / PI), 65504.0);
		float G = min(0.5 / mix(2.0 * cNdotL * cNdotV, cNdotL + cNdotV, a), 65504.0);
		float f90 = clamp(shade_f0 * 49.5, 0.0, 1.0);
		float F = shade_f0 + (f90 - shade_f0) * shade_schlick(cLdotH);
		SPECULAR_LIGHT += lc * (cNdotL * D * F * G * SPECULAR_AMOUNT * (LIGHT_IS_DIRECTIONAL ? shade_lt.a : 1.0));
	}
}
#endif
#endif
