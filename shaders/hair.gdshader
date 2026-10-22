shader_type spatial;
// Vlasy, obočí a vousy (C4b) – karty s procedurálními prameny, trubice (copánky, dredy), skořepiny.
// Atributy z HairBuilderu: CUSTOM0.x = náhoda pramene (u skořepiny okraj vlasové linie, 0,5 = linie),
// .y = pořadí ústupu (vlasy zmizí, když hairline > pořadí), .z = vrstva 0 (u hlavy) … 1 (navrchu), .w = druh / 8.
// Šedivění je po jednotlivých vlasech (sůl a pepř), ne plošné zesvětlení; barva je lineární (AppearanceResolver).
// Alpha scissor + alpha-to-coverage: žádné řazení průhlednosti, stíny fungují.
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec3 hair_color = vec3(0.05, 0.03, 0.02);
uniform vec3 grey_color = vec3(0.60, 0.59, 0.56);
uniform float grey : hint_range(0.0, 1.0) = 0.0;
uniform float hairline : hint_range(0.0, 1.0) = 0.0;
uniform float density : hint_range(0.0, 1.0) = 1.0;
// 1 = vlasy na hlavě (víc pramenů na kartu), 0 = obočí a vousy
uniform float fine = 1.0;
uniform float roughness_base = 0.42;

varying vec4 attr;

float h11(float n) { return fract(sin(n * 127.1 + 31.7) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	attr = CUSTOM0;
}

void fragment() {
	int kind = int(floor(attr.w * 8.0 + 0.01));
	float band = fract(attr.w * 8.0 + 0.01);
	float rnd = attr.x;
	float layer = attr.z;
	vec2 uv = UV;
	float a = 1.0;
	vec3 base = hair_color;
	float shade = 1.0;
	float spec_k = 1.0;
	bool greyed = false;

	// --- ustupující vlasová linie a řídnutí temene (miniaturizace u okraje) ---
	float edge_noise = (kind == 1 || kind == 4) ? vnoise(uv * 900.0) : rnd;
	float edge = attr.y - hairline + (edge_noise - 0.5) * 0.12;
	if (edge < 0.0) discard;
	float thin = smoothstep(0.0, 0.14, edge);

	if (kind == 0) {
		// karta: N pramenů napříč, každý jinak dlouhý; konec karty se zužuje
		float n = mix(5.0, 11.0, fine);
		float x = uv.x * n + rnd * 7.0;
		float id = floor(x);
		float fx = fract(x);
		float sr = h11(id * 1.37 + rnd * 91.0);
		if (fine < 0.5 && rnd > density) discard;
		float wob = sin(uv.y * (9.0 + sr * 7.0) + sr * 6.28) * 0.12;
		float w = mix(0.30, 0.42, sr) * mix(1.0, 0.45, uv.y) * mix(0.55, 1.0, thin);
		float fw = fwidth(x);
		float line = 1.0 - smoothstep(w - fw, w + fw, abs(fx - 0.5 + wob));
		float len_cut = 1.0 - 0.38 * h11(id * 3.11 + rnd * 17.0);
		float tip = 1.0 - smoothstep(len_cut - 0.06, len_cut, uv.y);
		float side = smoothstep(0.0, 0.06, uv.x) * smoothstep(1.0, 0.94, uv.x);
		a = line * tip * side;
		greyed = h11(id * 5.71 + rnd * 33.0) < grey;
		shade = (0.80 + 0.32 * sr) * mix(0.62, 1.0, smoothstep(0.0, 0.35, uv.y) * 0.5 + 0.5 * layer);
	} else if (kind == 1 || kind == 4) {
		// skořepina (na ježka, strany undercutu, afro): krátké tahy / spirálky v síti
		float scale = kind == 4 ? 1500.0 : 2300.0;
		vec2 q = uv * scale;
		float nz = vnoise(q) * 0.65 + vnoise(q * 2.3 + 7.0) * 0.35;
		float cov = kind == 4 ? mix(0.30, 0.62, 1.0 - layer) : mix(0.42, 0.55, 1.0 - layer);
		a = smoothstep(cov, cov + 0.08, nz);
		a *= smoothstep(0.42, 0.62, rnd + (vnoise(uv * 700.0) - 0.5) * 0.22);
		if (kind == 4) a = max(a, step(0.999, 1.0 - layer));
		greyed = h21(floor(q * 0.6)) < grey;
		shade = (0.78 + 0.3 * nz) * mix(0.65, 1.0, layer);
		spec_k = 0.5;
	} else if (kind == 2) {
		// copánek / cornrow: střídavé šikmé prameny (ploché opletení)
		float t = uv.y / 0.011;
		float side_s = step(0.5, fract(uv.x * 2.0));
		float d = fract(t + (side_s > 0.5 ? uv.x * 2.0 : -uv.x * 2.0));
		float ridge = sin(d * 3.14159);
		shade = 0.55 + 0.5 * ridge;
		greyed = h11(floor(t) * 1.7 + rnd * 9.0) < grey;
		spec_k = 0.6;
	} else if (kind == 3) {
		// dred: plstěný povrch
		float nz = vnoise(vec2(uv.x * 30.0, uv.y * 180.0)) * 0.6 + vnoise(vec2(uv.x * 70.0, uv.y * 420.0)) * 0.4;
		shade = 0.6 + 0.5 * nz;
		greyed = h21(floor(vec2(uv.x * 8.0, uv.y * 60.0))) < grey;
		spec_k = 0.25;
	} else {
		// plné části (jádro drdolu, gumička)
		shade = band > 0.25 ? 0.25 : 0.7 + 0.2 * vnoise(uv * vec2(20.0, 300.0));
		spec_k = band > 0.25 ? 0.3 : 0.5;
	}
	if (a < 0.02) discard;
	vec3 col = greyed ? grey_color : base;
	if (band > 0.25 && kind == 5) col = vec3(0.02);
	ALBEDO = clamp(col * shade, 0.0, 1.0);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = roughness_base + (greyed ? 0.06 : 0.0);
	SPECULAR = 0.35 * spec_k;
	ANISOTROPY = 0.75 * spec_k;
	ANISOTROPY_FLOW = vec2(1.0, 0.0);
	BACKLIGHT = col * 0.35;
}
