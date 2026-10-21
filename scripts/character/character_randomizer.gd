extends RefCounted
## Náhodná postava „s rozumným rozložením, ne chaos“ – a bez stereotypů:
##  - tělo, kůže, vlasy, oči, hlas, oblečení a make-up se losují NEZÁVISLE na identitě a rodu
##    (žádné „žena = menší, dlouhé vlasy, vyšší hlas“); kůže je spojitá a rovnoměrná přes celé
##    spektrum, jména nesouvisí se vzhledem;
##  - realistické jsou jen vazby, které dávají fyzikální/biologický smysl: věk → šediny,
##    ustupující linie, vrásky, brýle, naslouchadlo; tělesný tuk → pas;
##  - zájmena (gramatický rod) se odvozují z identity (tak je lidé obvykle volí) a jméno z rodu
##    (česká jména a příjmení jsou rodová); u nebinárních postav se míchají;
##  - duševní predispozice a traumata se NElosují (nevyplněno = výchozí), jen když o to volající
##    výslovně požádá (`include_mind`) – a i pak vzácně a nezávisle na všem ostatním.
## Zámky: cesty "skupina" nebo "skupina.pole" – zamčené hodnoty se převezmou z `base`.

const Schema := preload("res://scripts/character/character_schema.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")

const NAMES_F := ["Jana", "Eliška", "Tereza", "Lucie", "Kateřina", "Petra", "Veronika", "Markéta", "Hana", "Zuzana",
	"Adéla", "Barbora", "Klára", "Michaela", "Lenka", "Ivana", "Monika", "Simona", "Aneta", "Dagmar", "Linh", "Mai", "Olena"]
const NAMES_M := ["Petr", "Jan", "Tomáš", "Martin", "Jakub", "Lukáš", "David", "Ondřej", "Pavel", "Jiří", "Michal",
	"Vojtěch", "Marek", "Filip", "Radek", "Zdeněk", "Vladimír", "Roman", "Milan", "Duc", "Minh", "Taras", "Mehmet"]
const NAMES_UNISEX := ["Saša", "Nikola", "Robin", "Alex", "Kim", "Max", "Ríša", "Andy", "Charlie", "Sam"]
## Příjmení [mužský tvar, ženský tvar] – i menšinová a přistěhovalecká (Česko je pestré).
const SURNAMES := [["Novák", "Nováková"], ["Dvořák", "Dvořáková"], ["Malý", "Malá"], ["Svoboda", "Svobodová"],
	["Černý", "Černá"], ["Procházka", "Procházková"], ["Kučera", "Kučerová"], ["Veselý", "Veselá"],
	["Horák", "Horáková"], ["Němec", "Němcová"], ["Pokorný", "Pokorná"], ["Marek", "Marková"], ["Hájek", "Hájková"],
	["Král", "Králová"], ["Beneš", "Benešová"], ["Fiala", "Fialová"], ["Sedláček", "Sedláčková"],
	["Nguyen", "Nguyen"], ["Tran", "Tran"], ["Horváth", "Horváthová"], ["Balog", "Balogová"],
	["Kowalski", "Kowalská"], ["Kovalenko", "Kovalenko"], ["Yilmaz", "Yilmaz"], ["Schneider", "Schneiderová"]]
const TOWNS := ["Praha", "Brno", "Ostrava", "Plzeň", "Liberec", "Olomouc", "Ústí nad Labem", "Most", "Kladno",
	"Karviná", "Jihlava", "Tábor", "Zlín", "Děčín", "Cheb", "Vsetín", "malá vesnice", "sídliště na okraji města"]
## Tlumená paleta hry pro oblečení.
const PALETTE := ["#3a4250", "#5b6b7a", "#7d8fa3", "#2f3a4a", "#4a5a3c", "#6b7a52", "#8a6f4e", "#5c4033", "#7a3b3b",
	"#9e5a4a", "#c9b79c", "#d8d2c4", "#23262b", "#46494f", "#6e5a7a", "#3f6f7a", "#a08a5a", "#b25e46", "#e3ddd2"]
const OUTFIT_POOLS := {
	"bezne": {"top": ["tricko", "kosile", "svetr", "mikina", "halenka", "rolak", "tilko", "saty"],
		"bottom": ["dziny", "kalhoty", "kratasy", "sukne", "leginy"], "shoes": ["tenisky", "polobotky", "kozacky", "sandaly"]},
	"pracovni": {"top": ["kosile", "halenka", "rolak", "svetr", "sako", "tricko"], "bottom": ["kalhoty", "oblekove", "sukne", "dziny"],
		"shoes": ["polobotky", "pracovni", "kozacky", "lodicky", "tenisky"]},
	"spolecenske": {"top": ["sako", "saty", "kosile", "halenka", "rolak"], "bottom": ["oblekove", "sukne", "kalhoty"],
		"shoes": ["polobotky", "lodicky", "kozacky"]},
	"spani": {"top": ["pyzamo", "tricko", "tilko"], "bottom": ["pyzamo", "kratasy", "teplaky"], "shoes": ["bosy", "bacory"]},
	"sport": {"top": ["sportovni", "tilko", "tricko", "mikina"], "bottom": ["teplaky", "leginy", "kratasy"], "shoes": ["tenisky"]},
}


static func _n(rng: RandomNumberGenerator, mean: float, sd: float, lo: float, hi: float) -> float:
	return clampf(rng.randfn(mean, sd), lo, hi)


static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]


## Vážený výběr z {hodnota: váha}.
static func _weighted(rng: RandomNumberGenerator, w: Dictionary):
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[-1]


## Vygeneruje kompletní slovník postavy (v1). `base` = stávající data (pro zámky), `locks` = cesty.
## opts: include_mind (bool, výchozí false)
static func generate(rng: RandomNumberGenerator, base: Dictionary = {}, locks: Array = [], opts := {}) -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = String(base.get("uid", "")) if base.has("uid") else CharacterData.new_uid()
	var age := _age(rng)
	if _locked(locks, "body.age") or _locked(locks, "body"):
		age = int(base.get("body", {}).get("age", age))
	_identity(rng, d)
	_body(rng, d, age)
	_face(rng, d)
	_skin(rng, d, age)
	_hair(rng, d, age)
	_eyes(rng, d)
	_extras(rng, d, age)
	_clothing(rng, d)
	_voice(rng, d, age)
	_personality(rng, d)
	_story(rng, d)
	if bool(opts.get("include_mind", false)):
		_mind(rng, d)
	# Zámky: převzít hodnoty z base (celé skupiny nebo jednotlivá pole).
	for lk in locks:
		var p := String(lk).split(".")
		if p.size() == 1 and base.has(p[0]) and typeof(base[p[0]]) == TYPE_DICTIONARY:
			d[p[0]] = (base[p[0]] as Dictionary).duplicate(true)
		elif p.size() == 2 and base.has(p[0]) and typeof(base[p[0]]) == TYPE_DICTIONARY and base[p[0]].has(p[1]):
			var v = base[p[0]][p[1]]
			d[p[0]][p[1]] = v.duplicate(true) if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY else v
	# Zamčený rod bez zamčeného jména: jméno se přizpůsobí rodu (Jana Nováková ≠ rod „on“ náhodou).
	if (_locked(locks, "identity.grammar") and not _locked(locks, "identity.first_name")):
		_name_for(rng, d, String(d["identity"]["grammar"]))
	return d


static func _locked(locks: Array, path: String) -> bool:
	return locks.has(path) or locks.has(path.split(".")[0])


static func _age(rng: RandomNumberGenerator) -> int:
	var band = _weighted(rng, {"mlady": 22.0, "stredni": 48.0, "starsi": 20.0, "senior": 10.0})
	match band:
		"mlady":
			return rng.randi_range(18, 24)
		"stredni":
			return rng.randi_range(25, 49)
		"starsi":
			return rng.randi_range(50, 66)
	return rng.randi_range(67, 90)


static func _identity(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var idn: Dictionary = d["identity"]
	var gi = _weighted(rng, {"muz": 45.0, "zena": 45.0, "nebinarni": 4.0, "genderfluidni": 1.5, "agender": 1.0, "neuvedeno": 3.5})
	idn["gender_identity"] = gi
	var g := "m"
	match gi:
		"muz":
			g = _weighted(rng, {"m": 97.0, "pl": 2.0, "n": 1.0})
		"zena":
			g = _weighted(rng, {"f": 97.0, "pl": 2.0, "n": 1.0})
		"neuvedeno":
			g = _pick(rng, ["m", "f"])
		_:
			g = _weighted(rng, {"pl": 35.0, "n": 25.0, "f": 20.0, "m": 20.0})
	idn["grammar"] = g
	_name_for(rng, d, g)
	idn["nickname"] = ""
	# Orientace: kategorie s realistickou četností, převedená na množinu podle identity.
	var cat = _weighted(rng, {"hetero": 80.0, "homo": 7.0, "bi": 10.0, "ace": 3.0})
	var att: Array = []
	match cat:
		"hetero":
			att = ["zeny"] if gi == "muz" else (["muzi"] if gi == "zena" else [_pick(rng, ["muzi", "zeny"])])
		"homo":
			att = ["muzi"] if gi == "muz" else (["zeny"] if gi == "zena" else ["nebinarni"])
		"bi":
			att = ["muzi", "zeny", "nebinarni"] if rng.randf() < 0.4 else ["muzi", "zeny"]
	idn["asexual"] = cat == "ace"
	idn["aromantic"] = cat == "ace" and rng.randf() < 0.5
	if cat == "ace" and not idn["aromantic"]:
		att = [_pick(rng, ["muzi", "zeny", "nebinarni"])]   # asexualita ≠ bez romantické přitažlivosti
	idn["attracted_to"] = att


static func _name_for(rng: RandomNumberGenerator, d: Dictionary, g: String) -> void:
	var pool: Array
	match g:
		"f":
			pool = NAMES_F
		"m":
			pool = NAMES_M
		_:
			pool = NAMES_UNISEX + [_pick(rng, NAMES_F), _pick(rng, NAMES_M)]
	d["identity"]["first_name"] = _pick(rng, pool)
	var sn: Array = _pick(rng, SURNAMES)
	var col := 1 if g == "f" else (0 if g == "m" else rng.randi_range(0, 1))
	d["identity"]["last_name"] = sn[col]


static func _body(rng: RandomNumberGenerator, d: Dictionary, age: int) -> void:
	var b: Dictionary = d["body"]
	b["age"] = age
	b["height_cm"] = snappedf(_n(rng, 171.0, 9.5, 148.0, 202.0), 0.5)
	b["frame"] = _n(rng, 0.5, 0.15, 0.05, 0.95)
	var fat := _n(rng, 0.3 + maxf(age - 30, 0) * 0.003, 0.14, 0.04, 0.95)
	b["body_fat"] = fat
	b["muscle"] = _n(rng, 0.38 - maxf(age - 45, 0) * 0.004, 0.15, 0.03, 0.95)
	b["shoulders"] = _n(rng, 0.5, 0.15, 0.05, 0.95)
	b["chest"] = _n(rng, 0.5, 0.14, 0.05, 0.95)
	b["bust"] = _n(rng, 0.08, 0.05, 0.0, 0.3) if rng.randf() < 0.5 else _n(rng, 0.5, 0.17, 0.15, 0.95)
	b["waist"] = clampf(0.3 + 0.5 * fat + rng.randfn(0.0, 0.06), 0.05, 0.95)
	b["hips"] = _n(rng, 0.5, 0.15, 0.05, 0.95)
	b["leg_length"] = _n(rng, 0.5, 0.13, 0.08, 0.92)
	b["head_size"] = _n(rng, 0.0, 0.3, -0.8, 0.8)


static func _face(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var f: Dictionary = d["face"]
	for k in Schema.FACE_MORPHS:
		f[k] = _n(rng, 0.0, 0.3, -0.9, 0.9)
	f["chin_cleft"] = rng.randf_range(0.15, 0.8) if rng.randf() < 0.2 else 0.0
	# Každý skutečný obličej je trochu nesouměrný – malé odchylky, výjimečně výraznější.
	for k in Schema.FACE_ASYMMETRY:
		f[k] = _n(rng, 0.0, 0.22, -0.75, 0.75)


static func _skin(rng: RandomNumberGenerator, d: Dictionary, age: int) -> void:
	var s: Dictionary = d["skin"]
	s["tone"] = rng.randf_range(0.02, 0.98)        # rovnoměrně přes celé spektrum
	s["undertone"] = _n(rng, 0.0, 0.45, -1.0, 1.0)
	s["redness"] = _n(rng, 0.3, 0.12, 0.0, 1.0)
	s["freckles"] = rng.randf_range(0.1, 0.7) if rng.randf() < 0.05 + 0.3 * (1.0 - float(s["tone"])) else 0.0
	s["moles"] = _n(rng, 0.15, 0.08, 0.0, 0.6)
	s["acne"] = rng.randf_range(0.1, 0.45) if rng.randf() < (0.3 if age < 25 else 0.05) else 0.0
	s["vitiligo"] = rng.randf_range(0.1, 0.6) if rng.randf() < 0.015 else 0.0
	s["weathering"] = _n(rng, 0.1, 0.1, 0.0, 0.8)
	s["detail_seed"] = rng.randi_range(0, 65535)   # rozmístění pih/znamének (C4)
	var scars: Array = []
	if rng.randf() < 0.15:
		scars.append({"zone": _pick(rng, Schema.BODY_ZONES.keys()), "size": snappedf(rng.randf_range(0.1, 0.6), 0.001)})
	s["scars"] = scars
	var tats: Array = []
	if rng.randf() < 0.25:
		for i in rng.randi_range(1, 3):
			tats.append({"zone": _pick(rng, Schema.BODY_ZONES.keys()), "design": _pick(rng, Schema.TATTOO_DESIGNS.keys()),
				"color": _pick(rng, ["#1d1f24", "#1d1f24", "#2b3550", "#5a1f1f", "#2f4a2f"])})
	s["tattoos"] = tats


static func _hair(rng: RandomNumberGenerator, d: Dictionary, age: int) -> void:
	var h: Dictionary = d["hair"]
	var w := {}
	for k in Schema.HAIR_STYLES:
		w[k] = 1.0
	w["holy"] = 0.5 + maxf(age - 35, 0) * 0.04
	h["style"] = _weighted(rng, w)
	var m = _weighted(rng, {"tmave": 60.0, "stredni": 25.0, "svetle": 15.0})
	h["melanin"] = rng.randf_range(0.7, 1.0) if m == "tmave" else (rng.randf_range(0.4, 0.7) if m == "stredni" else rng.randf_range(0.0, 0.4))
	h["red"] = rng.randf_range(0.4, 0.9) if rng.randf() < 0.12 else rng.randf_range(0.0, 0.2)
	var gp := 1.0 / (1.0 + exp(-(float(age) - 48.0) / 7.0))
	h["grey"] = clampf(gp * rng.randf_range(0.5, 1.1), 0.0, 1.0)
	h["dyed"] = rng.randf() < 0.1
	h["dye_color"] = _pick(rng, ["#7a3b8f", "#2a5aa8", "#c2306a", "#e8e0c8", "#b8452a", "#2f2f2f"])
	h["hairline"] = rng.randf_range(0.2, 0.85) if rng.randf() < maxf(float(age) - 28.0, 0.0) / 90.0 else 0.0
	h["brows"] = _pick(rng, Schema.BROW_STYLES.keys())
	h["brow_density"] = _n(rng, 0.6, 0.15, 0.1, 1.0)
	h["facial"] = _pick(rng, Schema.FACIAL_HAIR.keys()) if rng.randf() < 0.35 else "zadne"
	h["facial_density"] = _n(rng, 0.6, 0.2, 0.1, 1.0)


static func _eyes(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var e: Dictionary = d["eyes"]
	var c = _weighted(rng, {"hnede": 55.0, "zelene": 15.0, "modre": 30.0})
	e["iris"] = rng.randf_range(0.72, 1.0) if c == "hnede" else (rng.randf_range(0.38, 0.68) if c == "zelene" else rng.randf_range(0.0, 0.33))
	e["heterochromia"] = rng.randf_range(0.2, 0.8) if rng.randf() < 0.01 else 0.0


static func _extras(rng: RandomNumberGenerator, d: Dictionary, age: int) -> void:
	var mk: Dictionary = d["makeup"]
	if rng.randf() < 0.3:
		mk["eyeliner"] = rng.randf_range(0.0, 0.7)
		mk["eyeshadow"] = rng.randf_range(0.0, 0.5)
		mk["lipstick"] = rng.randf_range(0.0, 0.8)
		mk["blush"] = rng.randf_range(0.0, 0.4)
		mk["lip_color"] = _pick(rng, ["#9e3a42", "#b0565f", "#7a2f3a", "#c47a6a", "#5a2a3a"])
		mk["eyeshadow_color"] = _pick(rng, ["#6b5a7a", "#8a6f4e", "#3a4250", "#a07a6a"])
	var a: Dictionary = d["aids"]
	a["glasses"] = _pick(rng, ["kulate", "hranate", "tenke", "silne"]) if rng.randf() < 0.2 + float(age) / 180.0 else "zadne"
	a["hearing_aid"] = rng.randf() < (0.15 if age > 65 else 0.01)


static func _clothing(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var out := {}
	for cat in OUTFIT_POOLS:
		var p: Dictionary = OUTFIT_POOLS[cat]
		var top: String = _pick(rng, p["top"])
		var bottom: String = "zadne" if top == "saty" and rng.randf() < 0.7 else _pick(rng, p["bottom"])
		if top == "pyzamo":
			bottom = "pyzamo"
		out[cat] = {"top": top, "bottom": bottom, "shoes": _pick(rng, p["shoes"]),
			"top_color": _pick(rng, PALETTE), "bottom_color": _pick(rng, PALETTE)}
	d["clothing"] = out


static func _voice(rng: RandomNumberGenerator, d: Dictionary, age: int) -> void:
	var v: Dictionary = d["voice"]
	v["pitch"] = _n(rng, 0.0, 0.45, -1.0, 1.0)
	v["timbre"] = _n(rng, 0.0, 0.4, -1.0, 1.0)
	v["tempo"] = _n(rng, 0.0, 0.35, -1.0, 1.0)
	v["roughness"] = _n(rng, 0.18 + maxf(age - 50, 0) * 0.006, 0.12, 0.0, 1.0)


static func _personality(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var tr: Array = []
	var want := rng.randi_range(2, 4)
	var pool: Array = Schema.TRAIT_COST.keys()
	var guard := 0
	while tr.size() < want and guard < 200:
		guard += 1
		var id: String = _pick(rng, pool)
		if tr.has(id) or Traits.conflicts_with(id, tr) or Schema.trait_cost(tr + [id]) > Schema.TRAIT_BUDGET:
			continue
		tr.append(id)
	d["personality"]["traits"] = tr
	var asp: Array = []
	for i in rng.randi_range(1, 2):
		var a: String = _pick(rng, Schema.ASPIRATIONS.keys())
		if not asp.has(a):
			asp.append(a)
	d["personality"]["aspirations"] = asp


static func _story(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var s: Dictionary = d["story"]
	s["family"] = _weighted(rng, {"oba_rodice": 60.0, "jeden_rodic": 22.0, "prarodice": 6.0, "pestouni": 3.0,
		"detsky_domov": 2.0, "neuvedeno": 7.0})
	s["childhood"] = _weighted(rng, {"klidne": 45.0, "chude": 12.0, "prisne": 14.0, "chaoticke": 10.0,
		"stehovani": 8.0, "zanedbane": 4.0, "neuvedeno": 7.0})
	var pw: Array = []
	for i in rng.randi_range(1, 2):
		var w: String = _pick(rng, Schema.PAST_WORK.keys())
		if not pw.has(w):
			pw.append(w)
	s["past_work"] = pw
	s["hometown"] = _pick(rng, TOWNS)
	s["backstory"] = ""


static func _mind(rng: RandomNumberGenerator, d: Dictionary) -> void:
	var m: Dictionary = d["mind"]
	var p := {}
	if rng.randf() < 0.12:
		p["anxiety"] = snappedf(rng.randf_range(0.2, 0.7), 0.001)
	if rng.randf() < 0.1:
		p["depression"] = snappedf(rng.randf_range(0.2, 0.7), 0.001)
	m["predispositions"] = p
	m["traumas"] = [_pick(rng, Schema.TRAUMAS.keys())] if rng.randf() < 0.15 else []
	m["morning_worse"] = p.has("depression") and rng.randf() < 0.4
