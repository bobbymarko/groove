shader_type sky;
render_mode use_quarter_res_pass;
// Physically based sky with raymarched volumetric clouds, ported from
// Cloudscape (MIT, Fishypants/cloudscape): Hillaire-style single scattering
// (multiple scattering approximated), Schneider / Nubis cloud shapes and light.
// Units are kilometres. The expensive work runs in the quarter-resolution pass
// with a per-frame jitter that TAA accumulates; the full-resolution pass adds
// the sun or moon disk and the stars. No TIME or POSITION here: Godot would
// then redraw the radiance cubemap every frame, so both come in as uniforms.

uniform sampler3D shape_tex : filter_linear, repeat_enable;
uniform sampler3D detail_tex : filter_linear, repeat_enable;
uniform sampler2D weather_tex : filter_linear, repeat_enable;
uniform sampler2D curl_tex : filter_linear, repeat_enable;

uniform vec3 cam_km = vec3(0.0, 0.3, 0.0);     // camera, km (y = altitude above the planet surface)
uniform vec3 light_dir = vec3(0.0, 0.5, 0.86);  // toward the sun, or the moon at night
uniform vec3 light_illum = vec3(1.0);           // sunlight (or moonlight) colour and strength
uniform float sun_disk = 1.0;                   // 1: the light is the sun, 0: the moon
uniform float stars = 0.0;                      // 0 by day, 1 at full night
uniform float exposure = 4.0;
uniform float haze = 0.78;
uniform vec3 ground_albedo = vec3(0.6);
uniform float frame = 0.0;                      // 0..63, jitter for TAA

uniform float coverage = 0.51;
uniform float cloud_type = 1.0;
uniform float cloud_density = 0.19;
uniform float erosion = 0.45;
uniform float cloud_bottom = 1.5;
uniform float cloud_top = 4.4;
uniform float sharp = 1.0;
uniform float turb = 1.0;
uniform float ambient = 2.0;
uniform float crease = 0.8;
uniform vec3 wind = vec3(0.0);                  // accumulated wind offset, km
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);
uniform int cloud_steps = 64;
uniform int light_steps = 6;
uniform int atmo_steps = 14;
uniform float cloud_far = 60.0;

const float Rg = 6360.0;
const float Rt = 6460.0;
const vec3 RAY_S = vec3(5.802e-3, 13.558e-3, 33.1e-3);
const float MIE_S = 3.996e-3;
const vec3 OZONE_A = vec3(0.650e-3, 1.881e-3, 0.085e-3);
const float WEATHER_SCALE = 45.0;
const float SHAPE_RES = 128.0;
const float DETAIL_RES = 64.0;
const float CURL_SCALE = 2.5;
const float SHAPE_SCALE = 2.0;
const float MID_SCALE = 1.85;
const float MID_AMT = 0.11;
const float FINE_SCALE = 0.42;
const float FINE_AMT = 0.78;
const vec3 OCT_W = vec3(1.0 / 3.0);

float sat(float x) { return clamp(x, 0.0, 1.0); }
float remap(float v, float a, float b, float c, float d) { return c + (v - a) / (b - a) * (d - c); }

vec2 ray_sphere2(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float lr = length(ro);
	float c = (lr - r) * (lr + r);
	float d = b * b - c;
	if (d < 0.0) return vec2(1e9, -1e9);
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

float ray_sphere(vec3 ro, vec3 rd, float r) {
	vec2 t = ray_sphere2(ro, rd, r);
	if (t.y < 0.0) return -1.0;
	return t.x > 0.0 ? t.x : t.y;
}

// ---- atmosphere ----
void medium(float h, out vec3 ray_s, out float mie_s, out vec3 ext) {
	h = max(h, 0.0);
	float dR = exp(-h / 8.0);
	float dM = exp(-h / 1.2);
	float dH = exp(-h / 0.8) * haze;
	float dO = max(0.0, 1.0 - abs(h - 25.0) / 15.0);
	ray_s = RAY_S * dR;
	mie_s = MIE_S * dM + 0.012 * dH;
	ext = ray_s + vec3(mie_s * 1.11) + OZONE_A * dO;
}

float phase_r(float c) { return 3.0 / (16.0 * PI) * (1.0 + c * c); }
float phase_m(float c, float g) {
	float g2 = g * g;
	return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + c * c)) / ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}
float phase_hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}

// Transmittance from planet-centred P toward the light, with a soft terminator
// (in place of Cloudscape's lookup table: six steps to the top of the air).
vec3 trans_to_light(vec3 P) {
	float r = length(P);
	float mu = dot(P, light_dir) / r;
	float sin_h = Rg / r;
	float mu_h = -sqrt(max(0.0, 1.0 - sin_h * sin_h));
	float vis = smoothstep(mu_h - 0.012, mu_h + 0.006, mu);
	if (vis <= 0.0) return vec3(0.0);
	float d = max(ray_sphere(P, light_dir, Rt), 0.0);
	vec3 od = vec3(0.0);
	float dt = d / 6.0;
	for (int i = 0; i < 6; i++) {
		vec3 Q = P + light_dir * (dt * (float(i) + 0.5));
		vec3 rs; float ms; vec3 ext;
		medium(length(Q) - Rg, rs, ms, ext);
		od += ext * dt;
	}
	return exp(-od) * vis;
}

// In-scattered light and transmittance along rd from ro over D km. Multiple
// scattering is folded in as a share of the single-scattered light, brighter
// near the horizon and through twilight, as Cloudscape's MS table does.
void atmosphere(vec3 ro, vec3 rd, float D, float jit, int steps, out vec3 L, out vec3 T) {
	L = vec3(0.0);
	T = vec3(1.0);
	float cos_t = dot(rd, light_dir);
	float pR = phase_r(cos_t);
	float pM = phase_m(cos_t, 0.8);
	float inv_n = 1.0 / float(steps);
	float t_prev = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= steps) break;
		float s1 = float(i + 1) * inv_n;
		float t1 = D * s1 * s1;
		float dt = t1 - t_prev;
		float t = t_prev + dt * jit;
		t_prev = t1;
		vec3 P = ro + rd * t;
		float r = length(P);
		vec3 rs; float ms; vec3 ext;
		medium(r - Rg, rs, ms, ext);
		vec3 sun_t = trans_to_light(P);
		float mu_s = dot(P, light_dir) / r;
		vec3 multi = (rs + ms) * (0.45 * sun_t + vec3(0.06, 0.08, 0.12) * smoothstep(-0.25, 0.1, mu_s));
		vec3 S = light_illum * ((rs * pR + ms * pM) * sun_t + multi);
		vec3 sT = exp(-ext * dt);
		L += T * (S - S * sT) / max(ext, vec3(1e-8));
		T *= sT;
	}
}

// ---- clouds ----
float height_frac(vec3 W) {
	return (length(W + vec3(0.0, Rg, 0.0)) - Rg - cloud_bottom) / (cloud_top - cloud_bottom);
}

vec2 weather_at(vec3 W) {
	vec4 w = textureLod(weather_tex, (W.xz - wind.xz * 0.6) / WEATHER_SCALE, 0.0);
	float thr = 1.0 - coverage * 1.3;
	return vec2(smoothstep(thr, thr + 0.45, w.r), sat(cloud_type + (w.g - 0.5) * 0.7));
}

vec4 profile(float type) {
	vec4 st = vec4(0.0, 0.07, 0.12, 0.25);
	vec4 sc = vec4(0.0, 0.12, 0.35, 0.55);
	vec4 cu = vec4(0.0, 0.10, 0.55, 1.00);
	return type < 0.5 ? mix(st, sc, type * 2.0) : mix(sc, cu, type * 2.0 - 1.0);
}

float cloud_base(vec3 W, float h, vec2 wt, float lod) {
	if (wt.x <= 0.001 || h < 0.0 || h > 1.0) return 0.0;
	vec3 p = W - wind + wind_dir * h * 0.6;
	vec4 n = textureLod(shape_tex, p / SHAPE_SCALE, lod);
	float fbm = dot(n.gba, vec3(0.625, 0.25, 0.125));
	float base = remap(n.r, fbm - 1.0, 1.0, 0.0, 1.0);
	vec4 g = profile(wt.y);
	base *= smoothstep(g.x, g.y, h) * (1.0 - smoothstep(g.z, g.w, h));
	float hn = sat((h - g.y) / max(g.w - g.y, 1e-3));
	float cov = wt.x * mix(1.0, 0.5, hn * hn);
	base = remap(base, 1.0 - cov, 1.0, 0.0, 1.0) * cov;
	return sat(base);
}

float erode(float b, vec3 p, float scale, float h, float amt) {
	float n = dot(textureLod(detail_tex, p / scale, 0.0).rgb, OCT_W);
	float m = mix(n, 1.0 - n, sat(h * 8.0));
	return sat(remap(b, m * erosion * amt, 1.0, 0.0, 1.0));
}

float detail_light(vec3 W, float h, float base) {
	return erode(base, W - wind * 1.4 + vec3(17.3, 5.1, -9.7), MID_SCALE, h, MID_AMT);
}

float cloud_detail(vec3 W, float h, float base) {
	vec3 p = W - wind * 1.4;
	vec3 c = textureLod(curl_tex, p.xz / CURL_SCALE, 0.0).rgb * 2.0 - 1.0;
	p += c * (turb * 0.18 * (1.0 - 0.7 * sat(h)));
	float b = erode(base, p + vec3(17.3, 5.1, -9.7), MID_SCALE, h, MID_AMT);
	if (b <= 0.003) return 0.0;
	return erode(b, p, FINE_SCALE, h, FINE_AMT);
}

float cloud_phase(float c, float k) { return mix(phase_hg(c, -0.25 * k), phase_hg(c, 0.82 * k), 0.72); }

float light_od(vec3 W, vec2 wt, float sigma) {
	float od = 0.0;
	float ds = 0.08;
	vec3 p = W;
	for (int i = 0; i < 8; i++) {
		if (i >= light_steps) break;
		p += light_dir * ds;
		float hf = height_frac(p);
		if (hf > 1.0 || hf < 0.0) break;
		float b = cloud_base(p, hf, wt, 1.0);
		if (b > 0.0) od += (i < 2 ? detail_light(p, hf, b) : b * 0.8) * ds;
		ds *= 1.8;
	}
	return od * sigma;
}

void march_clouds(vec3 W0, vec3 rd, float jit, out vec3 col, out float T, out float dc) {
	col = vec3(0.0);
	T = 1.0;
	dc = 1e9;
	vec3 P0 = W0 + vec3(0.0, Rg, 0.0);
	float r0 = length(P0);
	float rb = Rg + cloud_bottom;
	float rt = Rg + cloud_top;
	vec2 ib = ray_sphere2(P0, rd, rb);
	vec2 it = ray_sphere2(P0, rd, rt);
	bool hit_inner = ib.x > 0.0 && ib.x < 1e8;
	float t0;
	float t1;
	if (r0 < rb) { t0 = ib.y; t1 = it.y; }
	else if (r0 < rt) { t0 = 0.0; t1 = hit_inner ? ib.x : it.y; }
	else {
		if (it.y < 0.0) return;
		t0 = max(it.x, 0.0);
		t1 = hit_inner ? ib.x : it.y;
	}
	// Below the horizon the ground is in the way.
	if (rd.y < 0.0 && r0 < rb) return;
	t1 = min(t1, cloud_far);
	if (t1 <= t0) return;
	float seg = t1 - t0;
	float steps = mix(float(cloud_steps) * 0.4, float(cloud_steps), sat(seg / 12.0));
	float dt = seg / steps;
	float t = t0 + dt * jit;
	float cos_t = dot(rd, light_dir);
	float ph0 = cloud_phase(cos_t, 1.0);
	float ph1 = cloud_phase(cos_t, 0.5);
	float ph2 = cloud_phase(cos_t, 0.25);
	float sigma = 45.0 * cloud_density;
	float powder_w = 0.6 * sat(0.5 - 0.5 * cos_t) + 0.2;
	// Sky light on the clouds: zenith-ish blue above, darker and ground-tinted below.
	vec3 sky_light = light_illum * trans_to_light(vec3(0.0, Rg + cloud_bottom, 0.0)) * sat(light_dir.y * 2.0 + 0.25);
	vec3 amb_top = sky_light * vec3(0.10, 0.14, 0.22) * ambient;
	vec3 amb_bot = sky_light * (vec3(0.05, 0.06, 0.08) + ground_albedo * 0.04) * ambient * 0.55;
	float wsum = 0.0;
	float dsum = 0.0;
	for (int i = 0; i < 256; i++) {
		if (t >= t1 || T < 0.01) break;
		vec3 W = W0 + rd * t;
		float hf = height_frac(W);
		vec2 wt = weather_at(W);
		float base = cloud_base(W, hf, wt, 0.0);
		if (base > 0.0) {
			float dens0 = cloud_detail(W, hf, base);
			float sw = mix(1.0, 0.03, pow(sharp, 0.6));
			float dens = sat((dens0 - sharp * 0.05) / sw);
			dens *= 1.0 - smoothstep(cloud_far * 0.6, cloud_far, t);
			if (dens > 0.002) {
				float sE = dens * sigma;
				float od = light_od(W, wt, sigma);
				vec3 sun_l = light_illum * trans_to_light(W + vec3(0.0, Rg, 0.0));
				float beer = ph0 * exp(-od) + 0.5 * ph1 * exp(-od * 0.5) + 0.25 * ph2 * exp(-od * 0.25);
				float powder = mix(1.0, 1.0 - exp(-sE * 0.15), powder_w);
				float depth_p = 0.05 + pow(sat(dens0 * 1.5), clamp(remap(hf, 0.3, 0.85, 0.5, 2.0), 0.5, 2.0));
				float vert_p = pow(clamp(remap(hf, 0.07, 0.14, 0.1, 1.0), 0.1, 1.0), 0.8);
				float in_scat = mix(1.0, sat(depth_p * vert_p * 1.6), crease);
				vec3 amb = mix(amb_bot, amb_top, sat(hf)) * mix(1.0, in_scat, 0.6);
				vec3 S = sun_l * beer * powder * in_scat + amb;
				float a = 1.0 - exp(-sE * dt);
				col += T * S * a;
				dsum += T * a * t;
				wsum += T * a;
				T *= 1.0 - a;
			}
			t += dt;
		} else {
			t += dt * 2.0;
		}
	}
	if (wsum > 0.0) dc = dsum / wsum;
	if (T < 0.01) { col /= max(1.0 - T, 1e-4); T = 0.0; }
}

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }

// Sky (and the ground below the horizon) along rd, clouds included.
vec4 sky_color(vec3 rd, vec2 px, bool cheap) {
	vec3 W0 = cam_km;
	vec3 P0 = W0 + vec3(0.0, Rg, 0.0);
	float jit = cheap ? 0.5 : ign(px + 5.588238 * frame);
	float t_planet = ray_sphere(P0, rd, Rg);
	float D = t_planet > 0.0 ? t_planet : max(ray_sphere(P0, rd, Rt), 0.0);
	vec3 L;
	vec3 T;
	atmosphere(P0, rd, D, cheap ? 0.5 : fract(jit + 0.618034), cheap ? 8 : atmo_steps, L, T);
	vec3 col = L;
	if (t_planet > 0.0) {
		vec3 Pg = P0 + rd * t_planet;
		vec3 n = normalize(Pg);
		vec3 sky_amb = light_illum * vec3(0.05, 0.07, 0.1) * sat(light_dir.y * 2.0 + 0.2);
		col += T * ground_albedo * (light_illum * trans_to_light(Pg) * max(dot(n, light_dir), 0.0) / PI + sky_amb);
	}
	float cloud_t = 1.0;
	if (cheap) {
		// Radiance pass: clouds as coverage at their mid height, enough for ambient light.
		if (rd.y > 0.02) {
			float tc = ray_sphere(P0, rd, Rg + mix(cloud_bottom, cloud_top, 0.3));
			vec2 wt = weather_at(W0 + rd * tc);
			float c = wt.x * smoothstep(0.02, 0.15, rd.y) * 0.8;
			vec3 cloud_col = light_illum * trans_to_light(vec3(0.0, Rg + cloud_bottom, 0.0)) * (0.18 + 0.25 * sat(light_dir.y)) * vec3(0.95, 0.97, 1.0);
			col = mix(col, cloud_col, c);
			cloud_t = 1.0 - c;
		}
	} else {
		vec3 cc;
		float ct;
		float cd;
		march_clouds(W0, rd, jit, cc, ct, cd);
		if (ct < 1.0) {
			// Air between the eye and the cloud hazes it over with distance.
			vec3 Lc;
			vec3 Tc;
			atmosphere(P0, rd, min(cd, D), 0.5, 6, Lc, Tc);
			col = col * ct + (cc * Tc + Lc) * (1.0 - ct);
		}
		cloud_t = ct;
	}
	return vec4(col * exposure, cloud_t);
}

float star_field(vec3 rd) {
	vec3 p = rd * 300.0;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = fract(sin(dot(id, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	if (h < 0.985) return 0.0;
	float d = length(f);
	return smoothstep(0.2, 0.0, d) * (h - 0.985) * 66.0;
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = sky_color(EYEDIR, vec2(0.0), true).rgb;
	} else if (AT_QUARTER_RES_PASS) {
		vec4 s = sky_color(EYEDIR, FRAGCOORD.xy, false);
		COLOR = s.rgb;
		ALPHA = s.a;
	} else {
		vec3 col = QUARTER_RES_COLOR.rgb;
		float clear = QUARTER_RES_COLOR.a;
		float c = dot(EYEDIR, light_dir);
		vec3 P0 = cam_km + vec3(0.0, Rg, 0.0);
		if (EYEDIR.y > -0.02) {
			// Sun: 0.75 degrees with limb darkening. Moon: a pale disc.
			float radius = sun_disk > 0.5 ? 0.0065 : 0.0045;
			float ang = acos(clamp(c, -1.0, 1.0));
			float edge = 1.0 - smoothstep(radius * 0.85, radius * 1.15, ang);
			if (edge > 0.0) {
				vec3 disk = sun_disk > 0.5 ? light_illum * 4000.0 : vec3(0.75, 0.8, 0.9) * 0.6;
				col += disk * edge * trans_to_light(P0) * clear * exposure;
			}
			col += vec3(0.8, 0.85, 1.0) * star_field(EYEDIR) * stars * clear * smoothstep(0.0, 0.15, EYEDIR.y);
		}
		COLOR = col;
	}
}
