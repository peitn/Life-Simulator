extends RefCounted
## Osobnostní rysy – ovlivňují úbytek potřeb, oblíbené akce, náladu, sociální chemii
## a „touhy“ (craving): když postava dlouho nedělá, co jeho povaha potřebuje, znervózní.

const DEFS := {
	"lenoch": {
		"label": "Lenoch", "desc": "Nejradši odpočívá, sport ho nebaví.",
		"decay": {"energy": 1.15, "comfort": 1.2},
		"tags": {"rest": 1.4, "sleep": 1.15, "exercise": 0.35},
		"irritability": 0.7,  # hluk a nepořádek ho skoro nerozhodí
	},
	"aktivni": {
		"label": "Aktivní", "desc": "Musí být pořád v pohybu.",
		"decay": {"energy": 0.9, "comfort": 0.8, "fun": 1.1},
		"tags": {"exercise": 1.9, "rest": 0.75},
		# [tag, po kolika hodinách, popisek moodletu, emoce, síla]
		"craving": ["exercise", 16.0, "Potřebuje se hýbat", "napjaty", -12.0],
	},
	"pedant": {
		"label": "Pořádkumilovný", "desc": "Čistota je pro něj zásadní.",
		"decay": {"hygiene": 1.25},
		"tags": {"hygiene": 1.5},
		"hygiene_threshold": 45.0,
		"irritability": 1.4,  # nádobí na lince a obsazená koupelna ho vytočí dřív
	},
	"spolecensky": {
		"label": "Společenský", "desc": "Bez lidí uvadá.",
		"decay": {"social": 1.45},
		"tags": {"social": 1.6, "solo": 0.9},
		"social_threshold": 40.0, "chemistry": 0.15, "forgiveness": 0.05,
	},
	"samotar": {
		"label": "Samotář", "desc": "Potřebuje klid a vlastní prostor.",
		"decay": {"social": 0.55},
		"tags": {"social": 0.55, "solo": 1.2, "quiet": 1.2},
		"chemistry": -0.12,
	},
	"gurman": {
		"label": "Gurmán", "desc": "Jídlo je pro něj zážitek.",
		"decay": {"hunger": 1.1},
		"tags": {"cooking": 1.7, "food": 1.15},
		"moodlet_bonus": {"food": 1.6},
	},
	"hravy": {
		"label": "Hravý", "desc": "Rád se baví a blbne.",
		"decay": {"fun": 1.35},
		"tags": {"fun": 1.35},
		"chemistry": 0.05,
	},
	"knihomol": {
		"label": "Knihomol", "desc": "Kniha je nejlepší přítel.",
		"tags": {"reading": 1.9, "quiet": 1.15},
		"moodlet_bonus": {"reading": 1.5},
		"craving": ["reading", 20.0, "Chybí mu knížka", "znudeny", -8.0],
	},
	"optimista": {
		"label": "Optimista", "desc": "Sklenice je vždycky poloplná.",
		"mood_bias": 8.0, "negative_scale": 0.7, "chemistry": 0.1,
		"dep_vuln": -0.12, "grudge_tau": 0.6, "forgiveness": 0.12,
		"irritability": 0.7,
	},
	"brucoun": {
		"label": "Bručoun", "desc": "Všechno ho trochu štve.",
		"mood_bias": -6.0, "negative_scale": 1.2,
		"tags": {"social": 0.8},
		"chemistry": -0.2, "stigma": 0.25,
		# Zášť drží dlouho, výčitky krátce, omlouvá se nerad.
		"grudge_tau": 1.6, "guilt_tau": 0.6, "pride": 0.45, "forgiveness": -0.1,
		"irritability": 1.4,
	},
	# --- negativní a ambivalentní rysy (dělají z postav lidi, ne záporáky)
	"zarlivy": {
		"label": "Žárlivý", "desc": "Když se jeho blízcí baví s jinými, hryže ho to.",
		"chemistry": -0.05, "jealous": true, "grudge_tau": 1.3,
	},
	"vznetlivy": {
		"label": "Vznětlivý", "desc": "Vybuchne dřív, než si to rozmyslí. Pak toho často lituje.",
		"argue_bias": 0.08, "stress_gain": 1.25,
		# Rychle vzplane, rychle odpustí – a své výbuchy pak lituje.
		"grudge_tau": 0.7, "guilt_tau": 1.2, "pride": 1.2,
		# Drobnosti ho vytočí, ale hádka v něm nedoutná: nižší měkký strop stresu z hádek
		# (vybuchne a vyfučí – vztek se nemění v chronický stres).
		"irritability": 1.4, "argue_stress_cap": 65.0,
		"tags": {"exercise": 1.15},
	},
	"cynik": {
		"label": "Cynik", "desc": "Na všechno má jedovatou poznámku. Pomoc přijímá těžko.",
		"mood_bias": -3.0, "chemistry": -0.08, "stigma": 0.35, "support_accept": 0.7,
		"dep_vuln": 0.05, "grudge_tau": 1.4, "pride": 0.5, "forgiveness": -0.08,
	},
	"impulzivni": {
		"label": "Impulzivní", "desc": "Nejdřív dělá, pak myslí. Rychlá úleva má přednost.",
		"tags": {"fun": 1.15, "coping_unhealthy": 1.6},
		"impulsive": true, "novelty": 0.85,
	},
	"uzkostlivy": {
		"label": "Úzkostlivý", "desc": "Citlivější nervová soustava – všímá si rizik, snadněji se rozhodí.",
		"vulnerability": 0.22, "tags": {"quiet": 1.15},
		"negative_scale": 1.1,
		# Výčitky si přehrává dlouho, omluví se spíš dřív než později.
		"guilt_tau": 1.5, "pride": 1.3,
		"irritability": 1.4,  # citlivější na hluk a narušený klid
	},
}

## Osobnostní akcenty (psychika D, mind.accents): zvýrazněné rysy, které mohou dělat potíže ve vztazích.
## Nejsou to legacy rysy (nedají se vybrat jako předvolba, neposílají se po síti, nejsou v náhodném
## generátoru) – jen další váhy v trait_profile se stejnými parametry jako rysy. Id mají předponu acc_.
## Klinické názvy (porucha osobnosti) jsou jen volitelný soukromý výklad (PersonalityAccents.labels).
const ACCENTS := {
	"acc_abandonment": {"label": "Citlivost na opuštění a emoční výkyvy",
		"stress_gain": 1.3, "negative_scale": 1.25, "jealous": true, "grudge_tau": 0.8, "guilt_tau": 1.3,
		"decay": {"social": 1.2}},
	"acc_suspicious": {"label": "Podezíravost",
		"chemistry": -0.08, "forgiveness": -0.12, "grudge_tau": 1.5, "support_accept": 0.75},
	"acc_attention": {"label": "Potřeba pozornosti",
		"decay": {"social": 1.35}, "tags": {"social": 1.4, "solo": 0.85}, "chemistry": 0.04, "argue_bias": 0.03},
	"acc_perfectionism": {"label": "Perfekcionismus a rigidita",
		"tags": {"hygiene": 1.3, "cooking": 1.15}, "irritability": 1.35, "guilt_tau": 1.4, "stress_gain": 1.1,
		"novelty": 1.25},
	"acc_avoidance": {"label": "Vyhýbavost a zábrany",
		"tags": {"social": 0.65, "solo": 1.2, "quiet": 1.15}, "negative_scale": 1.15, "pride": 1.2},
	"acc_dependency": {"label": "Závislost na druhých",
		"decay": {"social": 1.35}, "tags": {"social": 1.2}, "support_accept": 1.3, "forgiveness": 0.08},
	"acc_grandiosity": {"label": "Grandiozita a potřeba obdivu",
		"pride": 0.4, "argue_bias": 0.05, "forgiveness": -0.06, "stigma": 0.15, "mood_bias": 2.0},
	"acc_detachment": {"label": "Odstup a citový chlad",
		"decay": {"social": 0.55}, "tags": {"social": 0.6, "solo": 1.15}, "chemistry": -0.1,
		"moodlet_bonus": {"social": 0.7}},
}

const CONFLICTS := [["spolecensky", "samotar"], ["lenoch", "aktivni"], ["optimista", "brucoun"],
	["optimista", "cynik"], ["brucoun", "cynik"]]


## Trait profiles accept either the old Array[String] (full-strength selected traits),
## or the new {trait_id: intensity_0_to_1} for independent continuous sliders.
## No arbitrary number-of-traits limit applies to slider profiles.
static func weight(profile: Variant, id: String) -> float:
	if typeof(profile) == TYPE_DICTIONARY:
		var value = profile.get(id, 0.0)
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return clampf(float(value), 0.0, 1.0) if not is_nan(float(value)) and not is_inf(float(value)) else 0.0
		return 0.0
	if typeof(profile) == TYPE_ARRAY:
		return 1.0 if profile.has(id) else 0.0
	return 0.0


static func _ids(profile: Variant) -> Array:
	if typeof(profile) == TYPE_DICTIONARY:
		var ids: Array = profile.keys()
		ids.sort()
		return ids
	if typeof(profile) == TYPE_ARRAY:
		return profile
	return []


static func _def(id: Variant) -> Dictionary:
	return DEFS.get(id, ACCENTS.get(id, {}))


static func label(id: String) -> String:
	return String(_def(id).get("label", id))


static func labels(ids: Array) -> String:
	var out: PackedStringArray = []
	for id in ids:
		out.append(label(String(id)))
	return ", ".join(out)


static func apply_decay(profile: Variant, needs) -> void:
	for id in _ids(profile):
		var w := weight(profile, String(id))
		var decay: Dictionary = _def(id).get("decay", {})
		for k in decay:
			needs.decay_mult[k] = float(needs.decay_mult.get(k, 1.0)) * lerpf(1.0, float(decay[k]), w)


static func tag_multiplier(profile: Variant, tag: String) -> float:
	var m := 1.0
	for id in _ids(profile):
		var tags: Dictionary = _def(id).get("tags", {})
		m *= lerpf(1.0, float(tags.get(tag, 1.0)), weight(profile, String(id)))
	return m


static func moodlet_multiplier(profile: Variant, action_tags: Array) -> float:
	var m := 1.0
	for id in _ids(profile):
		var bonus: Dictionary = _def(id).get("moodlet_bonus", {})
		var w := weight(profile, String(id))
		for t in action_tags:
			m *= lerpf(1.0, float(bonus.get(t, 1.0)), w)
	return m


static func mood_bias(profile: Variant) -> float:
	var b := 0.0
	for id in _ids(profile):
		b += float(_def(id).get("mood_bias", 0.0)) * weight(profile, String(id))
	return b


static func negative_scale(profile: Variant) -> float:
	var s := 1.0
	for id in _ids(profile):
		s *= lerpf(1.0, float(_def(id).get("negative_scale", 1.0)), weight(profile, String(id)))
	return s


static func chemistry(profile: Variant) -> float:
	var c := 0.0
	for id in _ids(profile):
		c += float(_def(id).get("chemistry", 0.0)) * weight(profile, String(id))
	return c


static func cravings(profile: Variant) -> Array:
	var out: Array = []
	for id in _ids(profile):
		var w := weight(profile, String(id))
		var c: Array = _def(id).get("craving", [])
		if c.size() == 5 and w > 0.0:
			out.append([c[0], float(c[1]) / maxf(w, 0.05), c[2], c[3], float(c[4]) * w])
	return out


static func sum_param(profile: Variant, key: String) -> float:
	var s := 0.0
	for id in _ids(profile):
		s += float(_def(id).get(key, 0.0)) * weight(profile, String(id))
	return s


static func mult_param(profile: Variant, key: String) -> float:
	var m := 1.0
	for id in _ids(profile):
		m *= lerpf(1.0, float(_def(id).get(key, 1.0)), weight(profile, String(id)))
	return m


## Continuous strength; max avoids counting overlapping aliases twice.
static func flag_strength(profile: Variant, key: String) -> float:
	var strength := 0.0
	for id in _ids(profile):
		if bool(_def(id).get(key, false)):
			strength = maxf(strength, weight(profile, String(id)))
	return strength


## Compatibility/presentation only; simulation uses flag_strength().
static func has_flag(profile: Variant, key: String) -> bool:
	return flag_strength(profile, key) >= 0.5


static func get_param(profile: Variant, key: String, fallback: float) -> float:
	# A weighted mean with the unused weight assigned to the default.
	# This is commutative, continuous, bounded, and preserves a single legacy override.
	var total := 0.0
	var weighted := 0.0
	for id in _ids(profile):
		var d: Dictionary = _def(id)
		if d.has(key):
			var w := weight(profile, String(id))
			total += w
			weighted += float(d[key]) * w
	return (weighted + fallback * maxf(1.0 - total, 0.0)) / maxf(1.0, total)


static func conflicts_with(id: String, chosen: Array) -> bool:
	for pair in CONFLICTS:
		if pair.has(id):
			for other in pair:
				if other != id and chosen.has(other):
					return true
	return false


static func random_traits(rng: RandomNumberGenerator, n := 3) -> Array:
	var pool: Array = DEFS.keys()
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < 200:
		guard += 1
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if out.has(id) or conflicts_with(id, out):
			continue
		out.append(id)
	return out
