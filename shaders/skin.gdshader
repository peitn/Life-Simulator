shader_type spatial;
// Kůže postavy (C4). Albedo počítá TÝŽ fyzikálně inspirovaný model jako SkinModel.gd (Beer–Lambert:
// melanin, hemoglobin, karoten), lokální jevy mění koncentrace chromoforů, ne „nálepky“ barvy – proto
// vypadají věrohodně na jakémkoli odstínu kůže. Masky se počítají v KLIDOVÝCH souřadnicích vrcholu
// (CUSTOM0, plní AssetLibrary), takže jizva nad obočím zůstane nad obočím i při morfech a animaci.
// Parametry plní SkinLayers.apply() z veřejného snapshotu postavy (deterministicky na všech peerech).
render_mode sss_mode_skin;

// --- model kůže (SkinModel.shader_constants) ---
uniform vec3 rd = vec3(1.0638, 0.9236, 0.7323);
uniform float surface_refl = 0.0083;
uniform vec3 k_mel = vec3(1.0, 1.32, 2.05);
uniform vec3 k_hb = vec3(0.06, 1.0, 0.55);
uniform vec3 k_car = vec3(0.0, 0.12, 1.0);
uniform vec3 chrom = vec3(0.6, 0.19, 0.0);   // melanin, hemoglobin, karoten
uniform float sss = 0.3;

// --- orientační body hlavy (SkinLayers.EYE / EYE_SHAPE / MOUTH) ---
uniform vec3 eye = vec3(0.0318, 1.6685, 0.0708);
uniform vec4 eye_shape = vec4(0.0142, 0.0053, 0.0043, 0.0698);
uniform vec3 mouth = vec3(0.0, 1.6035, 0.0245);

// --- vrstvy (SkinLayers.resolve) ---
uniform float seed = 0.0;
uniform float freckles = 0.0;
uniform float moles = 0.15;
uniform float acne = 0.0;
uniform float vitiligo = 0.0;
uniform float wrinkles = 0.0;
uniform float age_spots = 0.0;
uniform float pores = 0.6;
uniform float eyeliner = 0.0;
uniform float eyeshadow = 0.0;
uniform vec3 eyeshadow_color = vec3(0.15, 0.1, 0.19);
uniform float blush = 0.0;
uniform vec3 brow_color = vec3(0.03, 0.025, 0.02);
uniform vec4 brow_shape = vec4(0.0042, 0.0035, 0.0125, 0.0);
uniform float brow_density = 0.6;
uniform vec3 facial_color = vec3(0.03, 0.025, 0.02);
uniform vec4 facial_mask = vec4(0.0);
uniform float facial_length = 0.0;
uniform float facial_density = 0.0;
uniform int scar_count = 0;
uniform vec4 scar0[6];
uniform vec4 scar1[6];
uniform vec4 scar2[6];
uniform int tattoo_count = 0;
uniform vec4 tattoo0[8];
uniform vec4 tattoo1[8];
uniform vec4 tattoo2[8];
uniform vec4 tattoo3[8];
uniform float tattoo_depth[8];

varying vec3 rp;

void vertex() {
	rp = CUSTOM0.xyz;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float fbm(vec3 p) {
	return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.03 + 11.7) + 0.15 * vnoise(p * 4.11 + 3.1);
}

// Pásmo lo..hi s měkkými okraji.
float band(float v, float lo, float hi, float soft) {
	return smoothstep(lo - soft, lo + soft, v) * (1.0 - smoothstep(hi - soft, hi + soft, v));
}

// Skvrny v buňkách: jedna možná skvrna na buňku, střed uvnitř buňky (bez ořezu), poloměr ≤ čtvrtina buňky.
float cell_spots(vec3 p, float cell, float prob, float rmin, float rmax, float salt) {
	vec3 q = p / cell + vec3(seed * 1.37 + salt);
	vec3 ci = floor(q);
	vec3 h = hash33(ci + salt * 3.1);
	if (h.x >= prob) {
		return 0.0;
	}
	vec3 c = ci + 0.25 + 0.5 * hash33(ci + 17.0 + salt);
	float r = mix(rmin, rmax, h.y) / cell;
	float d = length(q - c);
	return 1.0 - smoothstep(r * 0.65, r, d);
}

float seg2(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.5, w, length(pa - ba * h));
}

float ring2(float d, float r, float w) {
	return 1.0 - smoothstep(w * 0.5, w, abs(d - r));
}

// Procedurální motivy tetování v souřadnicích uv ∈ [-1, 1]² (vzor = id, var = varianta 0..1).
float tattoo_pattern(int id, vec2 uv, float var) {
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float w = 0.07;
	float c = 0.0;
	if (id == 0) {          // nápis: řádek „písmen“ z tahů
		float row = abs(uv.y) < 0.24 ? 1.0 : 0.0;
		float x = (uv.x + 1.0) * 5.0;
		float gi = floor(x);
		float gx = fract(x);
		vec3 h = hash33(vec3(gi, var * 91.0, 3.0));
		float v1 = 1.0 - smoothstep(0.05, 0.1, abs(gx - (0.25 + 0.5 * h.x)));
		float h1 = (1.0 - smoothstep(0.03, 0.06, abs(uv.y - (h.y - 0.5) * 0.3))) * band(gx, 0.15, 0.85, 0.03);
		float cur = (1.0 - smoothstep(0.03, 0.06, abs(length(vec2(gx - 0.5, uv.y * 2.0)) - 0.32))) * step(0.6, h.z);
		c = row * max(max(v1, h1), cur) * band(uv.x, -0.95, 0.95, 0.02);
	} else if (id == 1) {   // květina
		vec2 p = uv - vec2(0.0, 0.2);
		float pr = length(p);
		float pa = atan(p.y, p.x);
		float petal = 0.32 + 0.22 * abs(cos(2.5 * pa + var * 6.28));
		c = max(ring2(pr, petal, w), 1.0 - smoothstep(0.08, 0.12, pr));
		c = max(c, seg2(uv, vec2(0.0, -0.1), vec2(0.05 * sin(var * 9.0), -0.95), w));
		c = max(c, seg2(uv, vec2(0.02, -0.55), vec2(0.3, -0.4), w));
	} else if (id == 2) {   // geometrický: trojúhelník v kruhu
		vec2 p = uv;
		float k = sqrt(3.0);
		p.x = abs(p.x) - 0.62;
		p.y = p.y + 0.62 / k;
		if (p.x + k * p.y > 0.0) {
			p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
		}
		p.x -= clamp(p.x, -1.24, 0.0);
		float tri = -length(p) * sign(p.y);
		c = max(ring2(tri, 0.0, w), ring2(r, 0.82, w));
		c = max(c, ring2(r, 0.18 + 0.1 * var, w * 0.8));
	} else if (id == 3) {   // zvíře: stylizovaný pták (vlaštovka)
		float wing_l = ring2(length(uv - vec2(-0.42, -0.35)), 0.5, w) * step(0.0, uv.y + 0.05) * step(uv.x, 0.0);
		float wing_r = ring2(length(uv - vec2(0.42, -0.35)), 0.5, w) * step(0.0, uv.y + 0.05) * step(0.0, uv.x);
		float body = 1.0 - smoothstep(0.1, 0.14, length((uv - vec2(0.0, 0.05)) * vec2(1.0, 0.55)));
		float tail = max(seg2(uv, vec2(0.0, -0.15), vec2(-0.15, -0.7), w), seg2(uv, vec2(0.0, -0.15), vec2(0.15, -0.7), w));
		c = max(max(wing_l, wing_r), max(body, tail));
	} else if (id == 4) {   // abstraktní tahy štětcem
		float n = vnoise(vec3(uv * 2.6, var * 10.0));
		c = band(n, 0.47, 0.55, 0.02) * (1.0 - smoothstep(0.75, 1.0, r));
	} else if (id == 5) {   // symbol: kruh s křížem nebo hvězdou
		c = ring2(r, 0.7, w);
		if (var < 0.5) {
			c = max(c, max(seg2(uv, vec2(0.0, -0.9), vec2(0.0, 0.9), w), seg2(uv, vec2(-0.5, 0.25), vec2(0.5, 0.25), w)));
		} else {
			float star = 0.35 + 0.25 * cos(5.0 * a + 1.5708);
			c = max(c, ring2(r, star, w));
		}
	} else if (id == 6) {   // ornament / mandala
		c = max(ring2(r, 0.28, w * 0.8), ring2(r, 0.62, w * 0.8));
		float sect = fract(a / 6.2832 * (8.0 + floor(var * 4.0)));
		c = max(c, (1.0 - smoothstep(0.06, 0.1, length(vec2((sect - 0.5) * 0.9, r - 0.82)))));
		c = max(c, ring2(r, 0.45 + 0.08 * cos(a * 8.0), w * 0.7));
	} else {                // portrét: ovál, oči, šrafování
		float ov = length(uv * vec2(1.25, 0.95));
		c = ring2(ov, 0.78, w);
		c = max(c, 1.0 - smoothstep(0.05, 0.08, length(uv - vec2(-0.22, 0.15))));
		c = max(c, 1.0 - smoothstep(0.05, 0.08, length(uv - vec2(0.22, 0.15))));
		c = max(c, seg2(uv, vec2(-0.18, -0.35), vec2(0.18, -0.35), w * 0.8));
		float hatch = step(fract((uv.x + uv.y) * 9.0), 0.22) * step(0.1, uv.x) * step(ov, 0.74);
		c = max(c, hatch * 0.8);
	}
	return c * (1.0 - smoothstep(0.96, 1.0, max(abs(uv.x), abs(uv.y))));
}

void fragment() {
	vec3 p = rp;
	float ax = abs(p.x);
	bool head = p.y > 1.52;
	bool front = p.z > 0.035;
	float mel = chrom.x;
	float hb = chrom.y;
	float car = chrom.z;
	float rough = 0.52;
	float crease = 0.0;
	// LOD (audit Gemini, běh 10): jemné detaily pod rozlišením pixelu (pihy, póry, chloupky obočí, strniště,
	// drobné skvrny) se od ~6 m plynule vypínají – šetří fragmentový výpočet u vzdálených postav a brání
	// mihotání (aliasingu) šumu. Velké útvary (vitiligo, jizvy, tetování, make-up) zůstávají.
	float near = 1.0 - smoothstep(6.0, 12.0, -VERTEX.z);

	// --- pihy (kumulované do shluků, víc na obličeji a ramenou) ---
	if (freckles > 0.001 && near > 0.01) {
		float face_z = head && front ? (0.35 + exp(-pow((p.y - 1.645) / 0.03, 2.0) - pow(p.x / 0.05, 2.0))) : 0.0;
		float body_z = (!head && p.y > 1.15) ? 0.8 : (!head ? 0.25 : 0.0);
		float fr = freckles * clamp(face_z + body_z, 0.0, 1.0) * (0.55 + 0.9 * vnoise(p * 30.0 + seed));
		float n = vnoise(p * 520.0 + vec3(seed));
		float dotm = smoothstep(0.82 - 0.22 * fr, 0.86 - 0.22 * fr, n) * clamp(fr * 1.5, 0.0, 1.0);
		mel += dotm * near * (0.35 + 0.6 * mel);
	}
	// --- znaménka ---
	if (moles > 0.001 && near > 0.01) {
		float m = cell_spots(p, 0.02, moles * 0.07, 0.0006, 0.0018, 1.0);
		mel += m * near * (1.6 + 0.5 * mel);
		rough -= 0.05 * m;
	}
	// --- stařecké skvrny (exponovaná místa: obličej, ruce, předloktí, dekolt) ---
	if (age_spots > 0.001) {
		float expo = head ? 1.0 : ((ax > 0.22 && p.y < 1.25) ? 0.9 : (p.y > 1.2 && front ? 0.5 : 0.15));
		float s = cell_spots(p, 0.03, age_spots * 0.55 * expo, 0.0018, 0.006, 2.0);
		s *= 0.6 + 0.4 * vnoise(p * 900.0);
		mel += s * (0.45 + 0.35 * mel);
	}
	// --- akné (T-zóna, tváře, brada, záda, hrudník) a pozánětlivé skvrny ---
	if (acne > 0.001 && near > 0.01) {
		float zone = 0.0;
		if (head && p.z > 0.03 && p.y > 1.55) zone = 1.0;
		if (!head && p.z < -0.06 && p.y > 1.1 && p.y < 1.45) zone = 0.8;
		if (!head && p.z > 0.08 && p.y > 1.25 && p.y < 1.42) zone = 0.6;
		if (zone > 0.0) {
			float les = cell_spots(p, 0.008, acne * 0.35 * zone, 0.0007, 0.0018, 3.0);
			float pih = cell_spots(p, 0.011, acne * 0.3 * zone, 0.001, 0.0026, 4.0);
			hb += les * 0.55;
			mel += pih * 0.45 * mel;      // po zánětu tmavší skvrna – výraznější na tmavší kůži (z modelu)
			rough -= 0.12 * zone * acne;  // mastnější pleť
		}
	}
	// --- vitiligo (depigmentované ostrůvky, častěji kolem očí, úst a na rukou) ---
	if (vitiligo > 0.001) {
		float bias = 0.0;
		if (head) {
			bias += 0.18 * exp(-pow(length(vec2(ax - eye.x, p.y - eye.y)) / 0.02, 2.0));
			bias += 0.15 * exp(-pow(length(vec2(p.x, p.y - mouth.y)) / 0.025, 2.0));
		} else if (ax > 0.26 && p.y < 1.0) {
			bias += 0.15;
		}
		float v = fbm(p * 14.0 + vec3(seed * 1.3)) + bias;
		float th = 1.0 - 0.6 * vitiligo;
		float patch = smoothstep(th, th + 0.035, v);
		float rim = band(v, th - 0.03, th, 0.01);
		mel = mix(mel + rim * 0.12 * mel, 0.015, patch);
		hb += patch * 0.04;
	}
	// --- jizvy (úsečka v rovině kůže, světlejší a lesklejší tkáň, volitelně stehy) ---
	for (int i = 0; i < 6; i++) {
		if (i >= scar_count) break;
		vec3 c = scar0[i].xyz;
		float hl = scar0[i].w;
		vec3 dir = scar1[i].xyz;
		float hw = scar1[i].w;
		vec3 n = scar2[i].xyz;
		vec3 d = p - c;
		float dn = dot(d, n);
		if (abs(dn) > 0.012) continue;
		vec3 dp = d - n * dn;
		float along = dot(dp, dir);
		float perp = length(dp - dir * along);
		float taper = 1.0 - smoothstep(0.6, 1.0, abs(along) / hl);
		float w = hw * (0.45 + 0.55 * taper);
		float m = (1.0 - smoothstep(w * 0.6, w * 1.3, perp)) * (1.0 - smoothstep(hl * 0.92, hl * 1.05, abs(along)));
		if (scar2[i].w > 0.5) {
			float st = (1.0 - smoothstep(hw * 2.6, hw * 3.4, perp)) * step(fract(along / 0.006 + 0.5), 0.16) * step(abs(along), hl * 0.9);
			m = max(m, 0.55 * st);
		}
		mel = mix(mel, mel * 0.45 + 0.03, m);
		hb = mix(hb, hb + 0.1, m * 0.6);
		rough -= 0.16 * m;
	}
	// --- vrásky a rýhy (věk + stárnutí kůže) jako jemné ztmavení a okluze ---
	if (wrinkles > 0.001 && head && front) {
		float fh = band(p.y, 1.705, 1.755, 0.006) * band(ax, 0.0, 0.05, 0.01);
		float lines = smoothstep(0.82, 0.98, sin(p.y * 6.2832 / 0.0072 + 0.6 * sin(p.x * 90.0 + seed)));
		crease += fh * lines * wrinkles;
		vec2 corner = vec2(ax - (eye.x + eye_shape.x + 0.003), p.y - eye.y);
		float cr = length(corner);
		float spokes = smoothstep(0.75, 0.97, sin(atan(corner.y, corner.x) * 9.0 + seed));
		crease += step(0.0, corner.x + 0.002) * band(cr, 0.002, 0.012, 0.002) * spokes * wrinkles * 0.8;
		vec2 q = vec2(ax, p.y);
		float nl = seg2(q, vec2(0.019, 1.623), vec2(mouth.z + 0.007, mouth.y - 0.004), 0.0012 + 0.0016 * wrinkles);
		crease += nl * smoothstep(0.1, 0.6, wrinkles);
		float bag = band(p.y, eye.y - eye_shape.z - 0.0045, eye.y - eye_shape.z - 0.0025, 0.0008) * band(ax - eye.x, -eye_shape.x * 0.8, eye_shape.x * 0.8, 0.002);
		crease += bag * wrinkles * 0.6;
	}
	crease = clamp(crease, 0.0, 1.0);

	// --- přírodní ruměnec / tvářenka ---
	if (head && blush > 0.001) {
		float ck = exp(-pow(length(vec3(ax - 0.044, p.y - 1.635, (p.z - 0.07) * 0.6)) / 0.016, 2.0));
		hb += ck * blush * 0.35;
	}

	// --- albedo z modelu (Beer–Lambert) ---
	vec3 e = mel * k_mel + hb * k_hb + car * k_car;
	vec3 alb = clamp(vec3(surface_refl) + rd * exp(-e), 0.0, 1.0);
	alb *= 1.0 - 0.2 * crease;

	// --- tetování (inkoust pod pokožkou: kůže filtruje barvu inkoustu) ---
	for (int i = 0; i < 8; i++) {
		if (i >= tattoo_count) break;
		vec3 c = tattoo0[i].xyz;
		vec3 u = tattoo1[i].xyz;
		vec3 n = tattoo2[i].xyz;
		vec3 d = p - c;
		float dn = dot(d, n);
		if (abs(dn) > tattoo_depth[i]) continue;
		vec3 side = normalize(cross(n, u));
		vec2 uv = vec2(dot(d, side) / tattoo0[i].w, dot(d, u) / tattoo3[i].w);
		if (abs(uv.x) > 1.0 || abs(uv.y) > 1.0) continue;
		float cov = tattoo_pattern(int(tattoo1[i].w + 0.5), uv, tattoo2[i].w);
		vec3 ink = tattoo3[i].xyz * 0.9 + 0.025;
		alb *= mix(vec3(1.0), ink, cov * 0.9);
	}

	// --- obočí (tahy chloupků podél oblouku) ---
	if (head && p.z > 0.055 && brow_density > 0.001) {
		float inner = brow_shape.w > 0.5 ? 0.0 : brow_shape.z;
		float outer = eye.x + eye_shape.x + 0.006;
		float t = clamp((ax - inner) / (outer - inner), 0.0, 1.0);
		float yc = eye.y + 0.0125 + brow_shape.y * sin(3.1416 * t * 0.9) - 0.002 * t;
		float th = brow_shape.x * (1.1 - 0.55 * t);
		if (brow_shape.w > 0.5 && ax < brow_shape.z) {
			th *= 0.45;
		}
		float inb = band(p.y - yc, -th * 0.5, th * 0.5, th * 0.18) * band(ax, inner, outer, 0.002);
		float hairs = near > 0.01 ? smoothstep(0.3, 0.65, vnoise(vec3(p.x * 1100.0, p.y * 240.0, seed))) : 0.6;
		hairs = mix(0.6, hairs, near);
		float cov = inb * (0.45 + 0.55 * hairs) * brow_density;
		alb = mix(alb, brow_color, clamp(cov, 0.0, 0.95));
	}

	// --- strniště a stín vousů (geometrie delších vousů přijde v C4b) ---
	if (head && facial_density > 0.001) {
		float my = mouth.y;
		float mw = mouth.z;
		float z_m = facial_mask.x * band(p.y, my + 0.003, my + 0.017, 0.0015) * band(ax, 0.0, mw + 0.006 - (p.y - my) * 0.3, 0.002) * step(0.055, p.z);
		float z_c = facial_mask.y * band(p.y, 1.548, my - 0.006, 0.002) * band(ax, 0.0, 0.028 + (my - p.y) * 0.3, 0.003) * step(0.03, p.z);
		float jaw = band(p.y, 1.545, 1.628 - max(ax - 0.02, 0.0) * 0.15, 0.003) * band(ax, 0.02, 0.074, 0.003) * step(-0.025, p.z);
		jaw *= 1.0 - band(ax, 0.0, mw + 0.004, 0.002) * band(p.y, my - 0.012, my + 0.012, 0.002);
		float neck = band(p.y, 1.51, 1.548, 0.004) * step(0.0, p.z);
		float z_j = facial_mask.z * max(jaw, neck * 0.7);
		float z_s = facial_mask.w * step(0.062, ax) * band(p.y, 1.615, 1.672, 0.003) * band(p.z, -0.015, 0.035, 0.003);
		float zone = clamp(max(max(z_m, z_c), max(z_j, z_s)), 0.0, 1.0);
		float dots = near > 0.01 ? smoothstep(0.5, 0.78, vnoise(p * 2600.0 + vec3(seed))) : 0.4;
		dots = mix(0.4, dots, near);
		float cov = zone * facial_density * (0.35 + 0.65 * dots) * (0.55 + 0.45 * facial_length);
		alb = mix(alb, facial_color * 0.9, clamp(cov * 0.75, 0.0, 0.9));
	}

	// --- make-up: oční linky a stíny (podle linie víčka ve výchozí poloze, jede s vrcholy) ---
	if (head && p.z > 0.05 && (eyeliner > 0.001 || eyeshadow > 0.001)) {
		vec2 el = vec2(ax - eye.x, p.y - eye.y);
		float ct = cos(-eye_shape.w);
		float st = sin(-eye_shape.w);
		el = vec2(el.x * ct - el.y * st, el.x * st + el.y * ct);
		float W = eye_shape.x;
		float xn = el.x / W;
		float lid = eye_shape.y * sqrt(max(0.0, 1.0 - xn * xn));
		float wing = max(0.0, xn - 0.85) * W * 0.6;
		float lw = 0.0006 + 0.0012 * eyeliner;
		float liner = band(el.y - lid - wing, -lw * 0.3, lw, 0.0003) * band(xn, -0.95, 1.0 + 0.35 * eyeliner, 0.04);
		alb = mix(alb, vec3(0.012, 0.011, 0.012), clamp(liner * eyeliner * 1.5, 0.0, 0.92));
		float sh = band(el.y - lid, 0.0, 0.0085, 0.002) * band(xn, -1.05, 1.2, 0.12);
		alb = mix(alb, eyeshadow_color, clamp(sh * eyeshadow * 0.75, 0.0, 0.8));
	}

	// --- drsnost: T-zóna lesklejší, póry, vrásky matnější ---
	if (head && front && ax < 0.025 && p.y > 1.61) {
		rough -= 0.08;
	}
	if (near > 0.01) {
		rough += (vnoise(p * 1800.0) - 0.5) * 0.12 * pores * near;
	}
	rough += 0.08 * crease;

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.25, 0.85);
	SPECULAR = 0.35;
	AO = 1.0 - 0.45 * crease;
	SSS_STRENGTH = sss;
}
