extends RefCounted
## Osobnostní rysy – ovlivňují úbytek potřeb, oblíbené akce, náladu, sociální chemii
## a „touhy“ (craving): když postava dlouho nedělá, co jeho povaha potřebuje, znervózní.

const DEFS := {
	"lenoch": {
		"label": "Lenoch", "desc": "Nejradši odpočívá, sport ho nebaví.",
		"decay": {"energy": 1.15, "comfort": 1.2},
		"tags": {"rest": 1.4, "sleep": 1.15, "exercise": 0.35},
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
	},
	"brucoun": {
		"label": "Bručoun", "desc": "Všechno ho trochu štve.",
		"mood_bias": -6.0, "negative_scale": 1.2,
		"tags": {"social": 0.8},
		"chemistry": -0.2, "stigma": 0.25,
		# Zášť drží dlouho, výčitky krátce, omlouvá se nerad.
		"grudge_tau": 1.6, "guilt_tau": 0.6, "pride": 0.45, "forgiveness": -0.1,
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
	},
}

const CONFLICTS := [["spolecensky", "samotar"], ["lenoch", "aktivni"], ["optimista", "brucoun"],
	["optimista", "cynik"], ["brucoun", "cynik"]]


static func label(id: String) -> String:
	return String(DEFS.get(id, {}).get("label", id))


static func labels(ids: Array) -> String:
	var out: PackedStringArray = []
	for id in ids:
		out.append(label(id))
	return ", ".join(out)


static func apply_decay(ids: Array, needs) -> void:
	for id in ids:
		var decay: Dictionary = DEFS.get(id, {}).get("decay", {})
		for k in decay:
			needs.decay_mult[k] = float(needs.decay_mult.get(k, 1.0)) * float(decay[k])


static func tag_multiplier(ids: Array, tag: String) -> float:
	var m := 1.0
	for id in ids:
		var tags: Dictionary = DEFS.get(id, {}).get("tags", {})
		m *= float(tags.get(tag, 1.0))
	return m


static func moodlet_multiplier(ids: Array, action_tags: Array) -> float:
	var m := 1.0
	for id in ids:
		var bonus: Dictionary = DEFS.get(id, {}).get("moodlet_bonus", {})
		for t in action_tags:
			m *= float(bonus.get(t, 1.0))
	return m


static func mood_bias(ids: Array) -> float:
	var b := 0.0
	for id in ids:
		b += float(DEFS.get(id, {}).get("mood_bias", 0.0))
	return b


static func negative_scale(ids: Array) -> float:
	var s := 1.0
	for id in ids:
		s *= float(DEFS.get(id, {}).get("negative_scale", 1.0))
	return s


static func chemistry(ids: Array) -> float:
	var c := 0.0
	for id in ids:
		c += float(DEFS.get(id, {}).get("chemistry", 0.0))
	return c


## Seznam tužeb: [[tag, hodiny, popisek, emoce, síla], …]
static func cravings(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var c: Array = DEFS.get(id, {}).get("craving", [])
		if c.size() == 5:
			out.append(c)
	return out


## Součet číselného parametru přes všechny rysy (např. vulnerability, stigma, argue_bias).
static func sum_param(ids: Array, key: String) -> float:
	var s := 0.0
	for id in ids:
		s += float(DEFS.get(id, {}).get(key, 0.0))
	return s


## Součin násobícího parametru (výchozí 1), např. stress_gain, support_accept, novelty.
static func mult_param(ids: Array, key: String) -> float:
	var m := 1.0
	for id in ids:
		m *= float(DEFS.get(id, {}).get(key, 1.0))
	return m


static func has_flag(ids: Array, key: String) -> bool:
	for id in ids:
		if bool(DEFS.get(id, {}).get(key, false)):
			return true
	return false


static func get_param(ids: Array, key: String, fallback: float) -> float:
	for id in ids:
		var d: Dictionary = DEFS.get(id, {})
		if d.has(key):
			return float(d[key])
	return fallback


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
