shader_type spatial;
// Camp's one surface shader: faceted low-poly with a sky/ground ambient,
// a warm rim and a small per-facet tint shift so surfaces read hand-cut.
render_mode diffuse_lambert_wrap, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.5);
uniform float glow = 0.0;              // self-lit roles: screens, fire
uniform vec3 sky : source_color = vec3(0.56, 0.50, 0.86);
uniform vec3 ground : source_color = vec3(0.52, 0.32, 0.28);
uniform float ambient = 0.55;
uniform vec3 rim_color : source_color = vec3(1.0, 0.62, 0.42);
uniform float rim = 0.45;
uniform float facet = 0.07;            // per-facet brightness wobble

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 wn = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	// Continuous in the normal, so derivative noise never flips it (no stripes).
	float h = 0.5 + 0.5 * sin(dot(wn, vec3(17.1, 31.7, 23.3)));
	vec3 col = albedo * (1.0 + (h - 0.5) * 2.0 * facet);
	ALBEDO = col * (1.0 - glow);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 amb = mix(ground, sky, clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	float r = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.5) * clamp(wn.y + 0.6, 0.0, 1.0);
	EMISSION = col * amb * ambient * (1.0 - glow) + rim_color * r * rim * (1.0 - glow) + albedo * glow;
}
