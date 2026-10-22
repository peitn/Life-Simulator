extends RefCounted
## PsycheModel – 1. osa psychiky: společný rámec, nad kterým budou stát další stavy (docs/design/psyche-model.md).
##
##   P – osobnost: 6 os (HEXACO-like, −1..1). Uložené volitelně v CharacterData.personality.hexaco; chybějící
##       osa se odvodí z rysů (tabulka TRAIT_P). Rysy zůstávají jako předvolby a popisy nad vektorem.
##   D – psychické dispozice: 9 interpretovatelných dimenzí 0..1 (0,5 = průměr populace), POČÍTANÉ, ne zadávané:
##       D = clamp(0,5 + Σ P·W + Σ přímé vlivy rysů + Σ modulace profilů × závažnost (+ individualita), 0, 1)
##   C – profily stavů jako data (res://data/conditions/<id>.json) se záznamy modulací add / mul / threshold /
##       couple, každý s limitem a povinným „why“. Graf vazeb (couple) musí být acyklický a vyhodnocuje se
##       v pevném topologickém pořadí, takže nemůže oscilovat.
##
## Proti dvojímu započtení: dnešní mechaniky (MentalState, Depression, Traits) dál nesou účinek rysů a profilů
## s blokem „legacy“. Takové příspěvky jsou „nesené“ (carried) a do háčků simulace jde jen REZIDUUM
## D − D_legacy, kde D_legacy obsahuje jen nesené příspěvky bez individuality. Reziduum tedy tvoří:
##   - individualita ze `personality.psyche_seed` (±20 % každého příspěvku + malý vlastní posun dimenze),
##   - explicitní HEXACO, které se liší od toho, co by plynulo z rysů,
##   - budoucí profily bez „legacy“ (další osy) – ty působí jen přes D.
## Postava bez CharacterData (staré testy, setup bez dat) má reziduum 0 → chování beze změny.
##
## Zásady: modulace mění náklady, pravděpodobnosti, interpretace a rychlosti – nikdy neodeberou volbu
## (háčky jsou násobiče s ořezem 0,7–1,3). Psychika neurčuje názory ani identitu; seed nikdy ze jména.
## Vše je soukromé (owner/server), do veřejného snapshotu nic z toho nejde.

const Schema := preload("res://scripts/character/character_schema.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const LSX := preload("res://scripts/assets/lsx_decoder.gd")

const PROFILE_DIR := "res://data/conditions"

## D – 9 dimenzí: [popisek, jedna věta „co to znamená“].
const DIMS := {
	"threat_sensitivity": ["Citlivost na hrozbu", "Jak snadno se nejasná situace čte jako nebezpečí."],
	"social_threat": ["Sociální hrozba", "Jak silně postava čeká odmítnutí nebo posuzování."],
	"impulsivity": ["Impulzivita", "Jak rychle se chuť mění v čin."],
	"regulation_capacity": ["Schopnost regulace", "Jak dobře se napětí a emoce vracejí dolů."],
	"predictability_need": ["Potřeba předvídatelnosti", "Jak moc postava potřebuje vědět, co přijde."],
	"sensory_sensitivity": ["Senzorická citlivost", "Jak intenzivně působí hluk, dav a světlo."],
	"energy_baseline": ["Vlastní energie", "Normální hladina energie a chuti do věcí – měřítko pro výkyvy."],
	"reward_sensitivity": ["Radost z činností", "Kolik radosti činnosti přinášejí."],
	"cognitive_flexibility": ["Kognitivní flexibilita", "Jak snadno se postava přepne, když věci jdou jinak."],
}

## Osobnost z rysů: aditivní posuny os (součet se ořízne do −1..1).
const TRAIT_P := {
	"lenoch": {"conscientiousness": -0.35, "extraversion": -0.1},
	"aktivni": {"extraversion": 0.2, "conscientiousness": 0.1},
	"pedant": {"conscientiousness": 0.5},
	"spolecensky": {"extraversion": 0.55},
	"samotar": {"extraversion": -0.5},
	"gurman": {"openness": 0.15},
	"hravy": {"extraversion": 0.2, "openness": 0.2, "conscientiousness": -0.1},
	"knihomol": {"openness": 0.4, "extraversion": -0.15},
	"optimista": {"emotionality": -0.25, "agreeableness": 0.2},
	"brucoun": {"agreeableness": -0.4, "emotionality": 0.1},
	"zarlivy": {"emotionality": 0.3, "agreeableness": -0.15},
	"vznetlivy": {"agreeableness": -0.5, "emotionality": 0.3},
	"cynik": {"agreeableness": -0.3, "honesty": -0.1, "openness": -0.1},
	"impulzivni": {"conscientiousness": -0.4},
	"uzkostlivy": {"emotionality": 0.5},
}

## Vliv os osobnosti na dimenze: [osa, dimenze, váha na jednotku osy].
const P_TO_D := [
	["emotionality", "threat_sensitivity", 0.15],
	["emotionality", "social_threat", 0.08],
	["emotionality", "regulation_capacity", -0.1],
	["emotionality", "sensory_sensitivity", 0.06],
	["extraversion", "social_threat", -0.1],
	["extraversion", "energy_baseline", 0.08],
	["extraversion", "reward_sensitivity", 0.06],
	["agreeableness", "regulation_capacity", 0.05],
	["conscientiousness", "impulsivity", -0.15],
	["conscientiousness", "predictability_need", 0.1],
	["openness", "cognitive_flexibility", 0.12],
	["openness", "predictability_need", -0.08],
	["openness", "reward_sensitivity", 0.04],
]

## Přímé vlivy rysů na dimenze (tam, kde rys popisuje spíš dispozici než osobnost).
const TRAIT_D := {
	"impulzivni": {"impulsivity": 0.15},
	"aktivni": {"energy_baseline": 0.1},
	"lenoch": {"energy_baseline": -0.08},
	"uzkostlivy": {"threat_sensitivity": 0.08},
	"optimista": {"reward_sensitivity": 0.05},
	"samotar": {"sensory_sensitivity": 0.05},
}

## Limity záznamů modulací (design §3).
const MAX_ADD := 0.3
const MUL_MIN := 0.5
const MUL_MAX := 2.0
const MAX_THRESHOLD := 0.2
const MAX_COUPLE := 0.5
const OPS := ["add", "mul", "threshold", "couple"]
## Prahy, které profil smí posouvat (v jednotkách 0..1; MentalState je převede na svou škálu).
const THRESHOLDS := {"T.panic": "Práh panické ataky"}
## Uzly stavu, které smí vazba (couple) číst nebo měnit. D.* smí být jen zdroj (dispozice se vazbou nemění).
const COUPLE_STATE := {"S.stress": "stres", "S.arousal": "tělesná aktivace", "S.threat": "vnímaná hrozba", "S.burden": "depresivní zátěž"}
## Rychlost vazby: kolik z (váha × zdroj) se přenese za herní hodinu.
const COUPLE_RATE := 0.1

## Individualita: ±20 % každého příspěvku + vlastní posun dimenze (součet 3 rovnoměrných → zhruba normální,
## sd ≈ 0,05, nejvýš ±0,15).
const JITTER := 0.2
const IDIO := 0.1
## Háčky: zesílení rezidua a ořez výsledného násobiče (žádný háček nic nezamkne ani neudělá extrémním).
const HOOK_MIN := 0.7
const HOOK_MAX := 1.3
const SOCIAL_COST_MAX := 0.15

static var _profiles: Dictionary = {}
static var _profiles_loaded := false
static var _load_errors: PackedStringArray = []


# ---------------------------------------------------------------- profily (data)

## Všechny profily stavů z res://data/conditions (cache). Neplatný profil se nenačte (push_error).
static func profiles() -> Dictionary:
	if not _profiles_loaded:
		_profiles_loaded = true
		var r := load_profiles_from(PROFILE_DIR)
		_profiles = r["profiles"]
		_load_errors = r["errors"]
		for e in _load_errors:
			push_error("PsycheModel: " + e)
	return _profiles


static func load_errors() -> PackedStringArray:
	profiles()
	return _load_errors


## {"profiles": {id: profil}, "errors": PackedStringArray}. Soubory se čtou seřazeně (deterministicky).
static func load_profiles_from(dir_path: String) -> Dictionary:
	var out := {}
	var errors := PackedStringArray()
	var files := PackedStringArray()
	var da := DirAccess.open(dir_path)
	if da == null:
		errors.append("složka profilů %s nejde otevřít" % dir_path)
		return {"profiles": out, "errors": errors}
	for f in da.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	for f in files:
		var path := dir_path.path_join(f)
		var text := FileAccess.get_file_as_string(path)
		var j := JSON.new()
		if text.length() > 65536 or j.parse(text) != OK or typeof(j.data) != TYPE_DICTIONARY:
			errors.append("%s: poškozený JSON" % f)
			continue
		var p: Dictionary = j.data
		var errs := validate_profile(p)
		if String(p.get("id", "")) != f.get_basename():
			errs.append("id „%s“ neodpovídá názvu souboru" % str(p.get("id", "")))
		if not errs.is_empty():
			for e in errs:
				errors.append("%s: %s" % [f, e])
			continue
		out[String(p["id"])] = p
	var cyc := coupling_order(out.values())
	if not bool(cyc["ok"]):
		errors.append("graf vazeb mezi profily má cyklus: %s – vazby se nepoužijí" % " → ".join(cyc["cycle"]))
		for id in out:
			var mods: Array = []
			for m in out[id].get("modulations", []):
				if String(m.get("op", "")) != "couple":
					mods.append(m)
			out[id]["modulations"] = mods
	return {"profiles": out, "errors": errors}


static func _num(v) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and not is_nan(float(v)) and not is_inf(float(v))


## Kontrola jednoho profilu: limity, povinné „why“, známé cíle a operace. Vrací seznam chyb (prázdný = OK).
static func validate_profile(p) -> PackedStringArray:
	var e := PackedStringArray()
	if typeof(p) != TYPE_DICTIONARY:
		e.append("profil není slovník")
		return e
	var id = p.get("id", "")
	if typeof(id) != TYPE_STRING or not String(id).is_valid_identifier():
		e.append("neplatné id")
	if typeof(p.get("label_cs", null)) != TYPE_STRING or String(p.get("label_cs", "")).strip_edges() == "":
		e.append("chybí label_cs")
	if String(p.get("content_tag", "")) != "mental_health":
		e.append("content_tag musí být mental_health (respektuje nastavení obsahu)")
	var sev = p.get("severity", [0.0, 1.0])
	if typeof(sev) != TYPE_ARRAY or sev.size() != 2 or not _num(sev[0]) or not _num(sev[1]) \
			or float(sev[0]) < 0.0 or float(sev[1]) > 1.0 or float(sev[0]) > float(sev[1]):
		e.append("severity musí být [min, max] v 0..1")
	if p.has("legacy"):
		var lg = p["legacy"]
		if typeof(lg) != TYPE_DICTIONARY:
			e.append("legacy není slovník")
		else:
			for k in ["sensitivity", "threat_bias", "social", "dep"]:
				if not _num(lg.get(k, null)) or float(lg[k]) < 0.0 or float(lg[k]) > 1.0:
					e.append("legacy.%s musí být číslo 0..1" % k)
			if typeof(lg.get("panic", null)) != TYPE_BOOL:
				e.append("legacy.panic musí být ano/ne")
	var mods = p.get("modulations", [])
	if typeof(mods) != TYPE_ARRAY or mods.size() > 32:
		e.append("modulations musí být seznam (nejvýš 32)")
		return e
	for i in mods.size():
		var m = mods[i]
		var at := "modulations[%d]" % i
		if typeof(m) != TYPE_DICTIONARY:
			e.append(at + ": není slovník")
			continue
		var why = m.get("why", "")
		if typeof(why) != TYPE_STRING or String(why).strip_edges().length() < 6:
			e.append(at + ": chybí srozumitelné „why“ (co, o kolik a proč)")
		var op := String(m.get("op", ""))
		if not OPS.has(op):
			e.append(at + ": neznámá operace „%s“" % op)
			continue
		var sc := String(m.get("scale", "severity"))
		if sc != "severity" and sc != "none":
			e.append(at + ": scale musí být severity nebo none")
		var tgt := String(m.get("target", ""))
		match op:
			"add", "mul":
				if not tgt.begins_with("D.") or not DIMS.has(tgt.substr(2)):
					e.append(at + ": cíl %s musí být D.<dimenze>" % tgt)
				if not _num(m.get("amount", null)):
					e.append(at + ": amount není číslo")
				elif op == "add" and absf(float(m["amount"])) > MAX_ADD:
					e.append(at + ": |add| > %.2f" % MAX_ADD)
				elif op == "mul" and (float(m["amount"]) < MUL_MIN or float(m["amount"]) > MUL_MAX):
					e.append(at + ": mul mimo %.1f–%.1f" % [MUL_MIN, MUL_MAX])
			"threshold":
				if not THRESHOLDS.has(tgt):
					e.append(at + ": neznámý práh %s" % tgt)
				if not _num(m.get("amount", null)) or absf(float(m["amount"])) > MAX_THRESHOLD:
					e.append(at + ": |threshold| > %.2f" % MAX_THRESHOLD)
			"couple":
				var fr := String(m.get("from", ""))
				if not COUPLE_STATE.has(tgt):
					e.append(at + ": vazba smí měnit jen %s" % ", ".join(COUPLE_STATE.keys()))
				if not COUPLE_STATE.has(fr) and not (fr.begins_with("D.") and DIMS.has(fr.substr(2))):
					e.append(at + ": neznámý zdroj vazby %s" % fr)
				if fr == tgt:
					e.append(at + ": vazba sama na sebe")
				if not _num(m.get("w", null)) or absf(float(m["w"])) > MAX_COUPLE:
					e.append(at + ": |w| > %.2f" % MAX_COUPLE)
	return e


## Topologické pořadí vazeb všech profilů (Kahn). {"ok", "order": [vazby v pořadí], "cycle": [uzly]}.
static func coupling_order(profile_list: Array) -> Dictionary:
	var edges: Array = []
	for p in profile_list:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		for m in p.get("modulations", []):
			if typeof(m) == TYPE_DICTIONARY and String(m.get("op", "")) == "couple":
				edges.append(m)
	return order_edges(edges)


static func order_edges(edges: Array) -> Dictionary:
	var indeg := {}
	var out_e := {}
	for m in edges:
		var a := String(m.get("from", ""))
		var b := String(m.get("target", ""))
		indeg[a] = int(indeg.get(a, 0))
		indeg[b] = int(indeg.get(b, 0)) + 1
		if not out_e.has(a):
			out_e[a] = []
		out_e[a].append(m)
	var nodes: Array = indeg.keys()
	nodes.sort()
	var queue: Array = []
	for n in nodes:
		if int(indeg[n]) == 0:
			queue.append(n)
	var order: Array = []
	var seen := 0
	while not queue.is_empty():
		var n: String = queue.pop_front()
		seen += 1
		var outs: Array = out_e.get(n, [])
		for m in outs:
			order.append(m)
			var b := String(m["target"])
			indeg[b] = int(indeg[b]) - 1
			if int(indeg[b]) == 0:
				queue.append(b)
	if seen < nodes.size():
		var cyc: Array = []
		for n in nodes:
			if int(indeg[n]) > 0:
				cyc.append(n)
		return {"ok": false, "order": [], "cycle": cyc}
	return {"ok": true, "order": order, "cycle": []}


# ---------------------------------------------------------------- deterministická individualita

## Rovnoměrné číslo 0..1 z (seed, klíč) – CRC-32, stejné na všech platformách a peerech.
static func _u(seed: int, key: String) -> float:
	return float(LSX.crc32(("%d|%s" % [seed, key]).to_utf8_buffer())) / 4294967296.0


static func _jit(seed: int, key: String) -> float:
	return 1.0 + JITTER * (2.0 * _u(seed, key) - 1.0)


static func _idio(seed: int, dim: String) -> float:
	return IDIO * (_u(seed, "i1:" + dim) + _u(seed, "i2:" + dim) + _u(seed, "i3:" + dim) - 1.5)


# ---------------------------------------------------------------- výpočet

static func _f(v, def := 0.0) -> float:
	return float(v) if _num(v) else def


## Osobnost z rysů (bez explicitních hodnot).
static func traits_personality(traits: Array) -> Dictionary:
	var p := {}
	for a in Schema.HEXACO:
		p[a] = 0.0
	for t in traits:
		var offs: Dictionary = TRAIT_P.get(String(t), {})
		for a in offs:
			p[a] = clampf(float(p[a]) + float(offs[a]), -1.0, 1.0)
	return p


## Hlavní výpočet. cd = slovník CharacterData (validovaný; poškozená pole se berou jako výchozí).
## opts: mode "full"|"muted"|"off" (nastavení obsahu), individual (bool, výchozí true).
## Výsledek: {P, P_traits, D, D_legacy, residual, thresholds, couples (v topologickém pořadí), records, seed, mode}
static func compute(cd, opts := {}) -> Dictionary:
	var d: Dictionary = cd if typeof(cd) == TYPE_DICTIONARY else {}
	var pers = d.get("personality", {})
	if typeof(pers) != TYPE_DICTIONARY:
		pers = {}
	var mind = d.get("mind", {})
	if typeof(mind) != TYPE_DICTIONARY:
		mind = {}
	var mode := String(opts.get("mode", "full"))
	var individual := bool(opts.get("individual", true))
	var seed := int(_f(pers.get("psyche_seed", 0)))
	var traits: Array = []
	var tr_src = pers.get("traits", [])
	if typeof(tr_src) == TYPE_ARRAY:
		for t in tr_src:
			if typeof(t) == TYPE_STRING and TRAIT_P.has(t) and not traits.has(t):
				traits.append(t)
	var p_tr := traits_personality(traits)
	var p_eff := p_tr.duplicate()
	var explicit := {}
	var hx = pers.get("hexaco", {})
	if typeof(hx) == TYPE_DICTIONARY:
		for a in hx:
			if Schema.HEXACO.has(a) and _num(hx[a]):
				p_eff[a] = clampf(float(hx[a]), -1.0, 1.0)
				explicit[a] = true
	# Příspěvky: [dim, base, carried, source, why]
	var contrib: Array = []
	for row in P_TO_D:
		var a: String = row[0]
		if absf(float(p_eff[a])) > 1e-6:
			var src := "hexaco:" + a if explicit.has(a) else "p:" + a
			contrib.append([row[1], float(p_eff[a]) * float(row[2]), false, src,
				"osobnost %s %s" % [Schema.HEXACO[a].to_lower(), _sgn(float(p_eff[a]))] + (" (zadáno)" if explicit.has(a) else " (z rysů)")])
	for t in traits:
		var offs: Dictionary = TRAIT_D.get(t, {})
		for dim in offs:
			contrib.append([dim, float(offs[dim]), true, "trait:" + t, "rys %s" % Traits.label(t)])
	# Profily stavů.
	var thresholds := {}
	var couples: Array = []
	var mul := {}
	var preds = mind.get("predispositions", {})
	var profs := profiles()
	if mode != "off" and typeof(preds) == TYPE_DICTIONARY:
		var ids: Array = preds.keys()
		ids.sort()
		for id in ids:
			if not profs.has(id) or not _num(preds[id]):
				continue
			var prof: Dictionary = profs[id]
			var sv: Array = prof.get("severity", [0.0, 1.0])
			var sev := clampf(float(preds[id]), float(sv[0]), float(sv[1]))
			if float(preds[id]) <= 0.0:
				continue
			if mode == "muted":
				sev = minf(sev, 0.5)
			var carried := prof.has("legacy")
			for m in prof.get("modulations", []):
				var k := sev if String(m.get("scale", "severity")) == "severity" else 1.0
				var op := String(m["op"])
				var why := "%s: %s" % [String(prof["label_cs"]), String(m["why"])]
				match op:
					"add":
						var dim := String(m["target"]).substr(2)
						contrib.append([dim, float(m["amount"]) * k, carried, "cond:" + id, why])
					"mul":
						var dim2 := String(m["target"]).substr(2)
						var f := lerpf(1.0, float(m["amount"]), k)
						if not mul.has(dim2):
							mul[dim2] = []
						mul[dim2].append([f, carried, "cond:" + id, why])
					"threshold":
						var t := String(m["target"])
						thresholds[t] = clampf(float(thresholds.get(t, 0.0)) + float(m["amount"]) * k, -MAX_THRESHOLD, MAX_THRESHOLD)
					"couple":
						var c: Dictionary = m.duplicate()
						c["w"] = float(m["w"]) * k
						c["source"] = "cond:" + id
						couples.append(c)
	var ordered := order_edges(couples)
	var res := {"P": p_eff, "P_traits": p_tr, "seed": seed, "mode": mode, "thresholds": thresholds,
		"couples": ordered["order"] if bool(ordered["ok"]) else []}
	var D := {}
	var DL := {}
	var records: Array = []
	for dim in DIMS:
		var tot := 0.0
		var leg := 0.0
		var cond_tot := 0.0
		var cond_leg := 0.0
		for c in contrib:
			if c[0] != dim:
				continue
			var key := "%s>%s" % [c[3], dim]
			var v: float = float(c[1]) * (_jit(seed, key) if individual else 1.0)
			if String(c[3]).begins_with("cond:"):
				cond_tot += v
				if c[2]:
					cond_leg += float(c[1])
			else:
				tot += v
			records.append({"dim": dim, "delta": v, "base": float(c[1]), "source": c[3], "why": c[4], "carried": c[2]})
			if c[2]:
				if not String(c[3]).begins_with("cond:"):
					leg += float(c[1])
		# Osobnost z rysů je nesená (dnešní rysy) – v D_legacy jsou P→D příspěvky z rysové osobnosti.
		for row in P_TO_D:
			if row[1] == dim:
				leg += float(p_tr[row[0]]) * float(row[2])
		# Komorbidita: součet modulací profilů na dimenzi drží limit jednoho záznamu.
		cond_tot = clampf(cond_tot, -MAX_ADD, MAX_ADD)
		cond_leg = clampf(cond_leg, -MAX_ADD, MAX_ADD)
		var idio := _idio(seed, dim) if individual else 0.0
		if absf(idio) > 1e-6:
			records.append({"dim": dim, "delta": idio, "base": 0.0, "source": "individual", "why": "individualita postavy (seed)", "carried": false})
		var dev := tot + cond_tot + idio
		var dev_l := leg + cond_leg
		var mf := 1.0
		var mf_l := 1.0
		for mm in mul.get(dim, []):
			mf *= float(mm[0])
			if mm[1]:
				mf_l *= float(mm[0])
			records.append({"dim": dim, "delta": 0.0, "factor": float(mm[0]), "source": mm[2], "why": mm[3], "carried": mm[1]})
		dev *= clampf(mf, MUL_MIN, MUL_MAX)
		dev_l *= clampf(mf_l, MUL_MIN, MUL_MAX)
		D[dim] = clampf(0.5 + dev, 0.0, 1.0)
		DL[dim] = clampf(0.5 + dev_l, 0.0, 1.0)
	var resid := {}
	for dim in DIMS:
		resid[dim] = float(D[dim]) - float(DL[dim])
	res["D"] = D
	res["D_legacy"] = DL
	res["residual"] = resid
	res["records"] = records
	return res


static func _sgn(x: float) -> String:
	return ("+" if x >= 0.0 else "−") + ("%.2f" % absf(x)).replace(".", ",")


## Háčky pro MentalState (násobiče ořezané do HOOK_MIN..HOOK_MAX). Čte jen reziduum, viz hlavička.
static func hooks(r: Dictionary) -> Dictionary:
	var res: Dictionary = r.get("residual", {})
	var reg := float(res.get("regulation_capacity", 0.0))
	var thr := float(res.get("threat_sensitivity", 0.0))
	var soc := float(res.get("social_threat", 0.0))
	var imp := float(res.get("impulsivity", 0.0))
	return {
		# vyšší regulace → kratší doznívání aktivace (menší časová konstanta poklesu)
		"arousal_decay_tau": clampf(1.0 - 1.5 * reg, HOOK_MIN, HOOK_MAX),
		"threat_gain": clampf(1.0 + 2.0 * thr, HOOK_MIN, HOOK_MAX),
		"crowd_gain": clampf(1.0 + 2.0 * soc, HOOK_MIN, HOOK_MAX),
		"social_cost": clampf(0.5 * soc, -SOCIAL_COST_MAX, SOCIAL_COST_MAX),
		"unhealthy_appeal": clampf(1.0 + 2.0 * imp, HOOK_MIN, HOOK_MAX),
		"healthy_appeal": clampf(1.0 - imp, 0.85, 1.15),
		"panic_shift": float(r.get("thresholds", {}).get("T.panic", 0.0)) * 100.0,
		"couples": (r.get("couples", []) as Array).duplicate(true),
		"D": (r.get("D", {}) as Dictionary).duplicate(),
	}


## Neutrální háčky (bez CharacterData).
static func neutral_hooks() -> Dictionary:
	return {"arousal_decay_tau": 1.0, "threat_gain": 1.0, "crowd_gain": 1.0, "social_cost": 0.0,
		"unhealthy_appeal": 1.0, "healthy_appeal": 1.0, "panic_shift": 0.0, "couples": []}


## Háčky pro všechny tři režimy obsahu (MentalState si vybírá podle aktuálního nastavení).
static func hooks_by_mode(cd) -> Dictionary:
	var out := {}
	for m in ["full", "muted", "off"]:
		out[m] = hooks(compute(cd, {"mode": m}))
	return out


## Vazby: jeden krok (hours herních hodin) v topologickém pořadí. state: {"S.stress": 0..1, …}; D-zdroje
## se berou jako odchylka od průměru (2·(D − 0,5)). Vrací nový stav (vstup nemění).
static func couple_step(couples: Array, state: Dictionary, D: Dictionary, hours: float) -> Dictionary:
	var s := state.duplicate()
	for c in couples:
		var fr := String(c.get("from", ""))
		var to := String(c.get("target", ""))
		if not s.has(to):
			continue
		var src := 0.0
		if fr.begins_with("D."):
			src = 2.0 * (float(D.get(fr.substr(2), 0.5)) - 0.5)
		else:
			src = float(s.get(fr, 0.0))
		s[to] = clampf(float(s[to]) + float(c.get("w", 0.0)) * src * COUPLE_RATE * hours, 0.0, 1.0)
	return s


## Srozumitelné vysvětlení jedné dimenze: co, o kolik, proč (seřazeno podle velikosti vlivu).
static func explain(r: Dictionary, dim: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DIMS.has(dim):
		return out
	var D: Dictionary = r.get("D", {})
	out.append("%s: %s (%s)" % [DIMS[dim][0], _level(float(D.get(dim, 0.5))), DIMS[dim][1]])
	var recs: Array = []
	for rec in r.get("records", []):
		if rec["dim"] == dim:
			recs.append(rec)
	recs.sort_custom(func(a, b): return absf(float(a["delta"])) + absf(float(a.get("factor", 1.0)) - 1.0) \
		> absf(float(b["delta"])) + absf(float(b.get("factor", 1.0)) - 1.0))
	for rec in recs:
		if rec.has("factor"):
			out.append("  ×%s · %s" % [("%.2f" % float(rec["factor"])).replace(".", ","), rec["why"]])
		elif absf(float(rec["delta"])) >= 0.005:
			out.append("  %s · %s" % [_sgn(float(rec["delta"])), rec["why"]])
	return out


static func _level(v: float) -> String:
	if v < 0.3:
		return "výrazně nižší"
	if v < 0.43:
		return "nižší"
	if v <= 0.57:
		return "průměrná"
	if v <= 0.7:
		return "vyšší"
	return "výrazně vyšší"
