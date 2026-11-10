extends RefCounted
## Drby a pomluvy (vztahy (c), 9. 11. 2026) – kdo co o kom ví, komu to řekl a čemu kdo věří.
##
## Čistý deterministický modul na AUTORITĚ (offline / host / dedikovaný server). Nezná uzly Godotu:
## pracuje se stabilními klíči postav (SimAgent.memory_key = uid z CharacterData) a s „profily“
## (slovníky), které mu předá adaptér v main.gd. Vlastní RNG se stavem v uložení → po načtení hry
## pokračuje bit po bitu stejně. Klientům se nic z toho neposílá (jen to, co postava řekne nahlas).
##
## Model:
##   drb (rumor)  – {subject, kind, truth, origin, severity, whom, t}; pravdivý drb vzniká JEN ze svědectví
##                  (observe), smyšlený jen u postavy s nízkou poctivostí (HEXACO H) a se zášť vůči subjektu.
##   znalost      – per postava: belief 0..1 (jak moc tomu věří), from (od koho to slyšela, "" = viděla sama),
##                  sev (vnímaná závažnost – při převyprávění roste), dist (zkreslení 0..1), told (komu to řekla),
##                  sources (různí vypravěči → sociální důkaz), applied (kolik víry už se promítlo do vztahu).
##   výměna       – při povedeném rozhovoru může každá strana říct jeden drb. Víra = důvěra k vypravěči ×
##                  věrohodnost (posluchač, který subjekt má rád, věří méně) × (1 − zkreslení·0,3); další zdroj
##                  víru skládá (1 − (1−a)(1−b·0,8)). Dopad na vztah posluchače k subjektu jen z PŘÍRŮSTKU víry,
##                  s denním stropem na dvojici – opakováním se nedá „farmit“.
##   odhalení     – kdo má subjekt rád, může mu říct „lidi o tobě říkají…“: subjekt se dozví, od koho to šlo
##                  (bezprostřední zdroj; původce jen když je to tatáž osoba) → zášť a ponížení; lež bolí jako
##                  křivda, pravda víc jako stud. Subjekt se brání → informátor víře ve lež věří méně.
##   vyvrácení    – vlastní dobrá zkušenost se subjektem oslabuje víru (lež rychleji než pravdu); bez
##                  připomínání víra vyhasíná (τ 12 dní) a zapomenuté drby zmizí.
##
## Citlivý obsah: drb o atace paniky jen v plném režimu duševního zdraví, o pití jen se zapnutými závislostmi
## (content z adaptéru). Účinek drbu o psychice záleží na stigmatizaci POSLUCHAČE – nestigmatizující posluchač
## si o subjektu nemyslí nic horšího (nemoc není prohřešek). Repliky citlivých druhů nahlas neříkají detail
## (soukromí v MP). Hra nic z toho neodměňuje: šíření drbů nemá herní bonus kromě krátkého pocitu drbny.

const Grammar := preload("res://scripts/core/grammar_cs.gd")

const VERSION := 2
## Starší uložení (v1) nemají podezřelé ani konfrontace – načtou se s prázdnými.
const MIN_VERSION := 1
## Katalog druhů. neg = záporný drb; content = "" | "mental_health" | "addiction"; about_listener = týká se
## posluchače (badmouth: „X o tobě mluví za zády“); fab = smí vzniknout smyšlením.
const KINDS := {
	"fight": {"sev": 0.3, "neg": true, "content": "", "about_listener": false, "fab": false,
		"self": "se pořád hádám", "line": "Víš, že se %s zase s někým hádal{g}? Bylo to slyšet přes celej barák."},
	"insult": {"sev": 0.5, "neg": true, "content": "", "about_listener": false, "fab": false,
		"self": "jsem někoho ošklivě urazil{g}", "line": "%s prý někoho sjel{g} jak psa. Fakt hnus."},
	"panic": {"sev": 0.4, "neg": true, "content": "mental_health", "about_listener": false, "fab": false,
		"self": "jsem měl{g} před ostatními ataku paniky", "line": "Víš, co se povídá? Jde o: %s."},
	"drinking": {"sev": 0.35, "neg": true, "content": "addiction", "about_listener": false, "fab": false,
		"self": "piju víc, než bych měl{g}", "line": "Víš, co se povídá? Jde o: %s."},
	"kind": {"sev": 0.3, "neg": false, "content": "", "about_listener": false, "fab": false,
		"self": "jsem někomu pomohl{g}, když bylo zle", "line": "%s je fakt dobrá duše. Pomohl{g}, když bylo nejhůř."},
	"badmouth": {"sev": 0.55, "neg": true, "content": "", "about_listener": true, "fab": true,
		"self": "o lidech mluvím za zády", "line": "Dej si bacha na: %s. Prý o tobě mluví za zády."},
	"steals": {"sev": 0.6, "neg": true, "content": "", "about_listener": false, "fab": true,
		"self": "beru ostatním věci", "line": "Prý %s bral{g} ostatním věci. Ale ode mě to nemáš."},
}
const MAX_RUMORS := 160
const MAX_KNOWN := 40
const MAX_TOLD := 12
const MAX_SOURCES := 4
const MAX_KEY := 64
const MAX_KNOWERS := 200
const MAX_NAMES := 240
const MAX_NAME := 40
## Víra pod touto hranicí: drb se nešíří; pod FORGET se zapomene.
const SHARE_MIN_BELIEF := 0.3
const FORGET_BELIEF := 0.06
const BELIEF_TAU_MIN := 12.0 * 1440.0
## Dopad na vztah (body vztahu −100..100).
const NEG_IMPACT := 14.0
const POS_IMPACT := 8.0
const EVENT_CAP := 8.0
const DAILY_PAIR_CAP := 12.0
const BOND_DAILY_CAP := 3.0
## Odhalení: zásah do vztahu subjektu ke zdroji.
const EXPOSE_BASE := 6.0
const EXPOSE_SEV := 12.0
## Podezřelí (od koho drb šel): platnost a limit na subjekt.
const MAX_SUSPECTS := 8
const SUSPECT_TTL_MIN := 14.0 * 1440.0
const STAT_KEYS := ["observed", "fabricated", "shared", "exposed", "debunked", "forgotten", "confronted", "retracted", "denied"]

var rng := RandomNumberGenerator.new()
var rumors := {}            # rid (int) → rumor
var know := {}              # key → {rid: entry}
var exposed := {}           # subject key → {rid: t}
var impact_day := {}        # "listener|subject" → [day, sum]
var names := {}             # key → {"n": jméno, "g": gramatika}
var suspects := {}          # subject key → {source key: {rid, t, kind, truth, origin}}
var stats := {"observed": 0, "fabricated": 0, "shared": 0, "exposed": 0, "debunked": 0, "forgotten": 0,
	"confronted": 0, "retracted": 0, "denied": 0}
var _next_id := 1
var _acc := 0.0


func _init(seed: int = 0x60551F) -> void:
	rng.seed = seed


# ---------------------------------------------------------------- pomocné

static func _key_ok(k: Variant) -> bool:
	return typeof(k) == TYPE_STRING and String(k) != "" and String(k).length() <= MAX_KEY


static func _f(v: Variant, def := 0.0) -> float:
	if typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)):
		return float(v)
	return def


static func content_ok(kind: String, content: Dictionary) -> bool:
	if not KINDS.has(kind):
		return false
	var c := String(KINDS[kind]["content"])
	return c == "" or bool(content.get(c, false))


func set_name(key: String, display: String, grammar: String) -> void:
	if not _key_ok(key):
		return
	if not names.has(key) and names.size() >= MAX_NAMES:
		_prune_names()
		if names.size() >= MAX_NAMES:
			return
	names[key] = {"n": display.substr(0, MAX_NAME), "g": Grammar.norm(grammar)}


func _knows(key: String) -> Dictionary:
	if not know.has(key):
		if know.size() >= MAX_KNOWERS:
			_evict_knower()
		know[key] = {}
	return know[key]


## Příliš mnoho znalců (dlouho běžící server): zapomene ten, kdo nejdéle nic neslyšel.
func _evict_knower() -> void:
	var worst := ""
	var wt := INF
	var ks: Array = know.keys()
	ks.sort()
	for k in ks:
		var latest := -INF
		for rid in know[k]:
			latest = maxf(latest, float(know[k][rid]["t"]))
		if latest < wt:
			wt = latest
			worst = k
	if worst != "":
		know.erase(worst)
		_gc()


## Jména jen pro subjekty existujících drbů (a nedávno přidané se nechají).
func _prune_names() -> void:
	var used := {}
	for rid in rumors:
		used[rumors[rid]["subject"]] = true
	for k in names.keys():
		if not used.has(k):
			names.erase(k)


func belief(key: String, rid: int) -> float:
	if not know.has(key) or not know[key].has(rid):
		return 0.0
	return float(know[key][rid]["belief"])


## Kolik lidí drbu o subjektu věří (≥ hranice šíření) a průměrná záporná váha – „pověst“ (jen pro autoritu).
func reputation(subject: String) -> Dictionary:
	var knowers := {}
	var neg := 0.0
	var pos := 0.0
	for k in know:
		if k == subject:
			continue
		for rid in know[k]:
			var r: Dictionary = rumors.get(rid, {})
			if r.is_empty() or r["subject"] != subject:
				continue
			var e: Dictionary = know[k][rid]
			if float(e["belief"]) < SHARE_MIN_BELIEF:
				continue
			knowers[k] = true
			if bool(KINDS[r["kind"]]["neg"]):
				neg += float(e["belief"]) * float(e["sev"])
			else:
				pos += float(e["belief"]) * float(e["sev"])
	return {"knowers": knowers.size(), "negative": neg, "positive": pos}


## Co se subjekt o sobě DOZVĚDĚL (soukromé, jen vlastníkovi): věty bez čísel.
func exposed_lines(subject: String, limit := 3) -> PackedStringArray:
	var out := PackedStringArray()
	if not exposed.has(subject):
		return out
	var ids: Array = exposed[subject].keys()
	ids.sort()
	ids.reverse()
	for rid in ids:
		if out.size() >= limit:
			break
		var r: Dictionary = rumors.get(rid, {})
		if r.is_empty():
			continue
		var g := String(names.get(subject, {}).get("g", "m"))
		out.append("Lidi si o mně povídají, že " + Grammar.form(String(KINDS[r["kind"]]["self"]), g) + ".")
	return out


## Replika nahlas. Citlivé druhy (psychika, závislost) detail neříkají – v MP ji slyší všichni.
func line_for(rid: int) -> String:
	var r: Dictionary = rumors.get(rid, {})
	if r.is_empty():
		return ""
	var nm: Dictionary = names.get(r["subject"], {"n": "?", "g": "m"})
	var full := String(nm["n"])
	var first := full.split(" ")[0] if full != "" else "?"
	return Grammar.form(String(KINDS[r["kind"]]["line"]) % first, String(nm["g"]))


# ---------------------------------------------------------------- vznik drbů

## Svědectví: `witness` viděl(a), jak `subject` udělal(a) `kind`. Pravdivý drb, svědek mu věří naplno.
## Stejný svědek + subjekt + druh do jednoho dne jen obnoví víru (žádné duplikáty). Vrací rid (0 = nic).
func observe(witness: String, subject: String, kind: String, now: float, content: Dictionary,
		sev_mult := 1.0, whom := "") -> int:
	if not _key_ok(witness) or not _key_ok(subject) or witness == subject or not KINDS.has(kind) \
			or bool(KINDS[kind]["fab"]) or not is_finite(now) or not content_ok(kind, content):
		return 0
	var sev := clampf(float(KINDS[kind]["sev"]) * clampf(_f(sev_mult, 1.0), 0.2, 2.0), 0.05, 1.0)
	var mine := _knows(witness)
	for rid in mine:
		var r: Dictionary = rumors.get(rid, {})
		if not r.is_empty() and r["subject"] == subject and r["kind"] == kind and r["origin"] == witness \
				and now - float(r["t"]) < 1440.0:
			mine[rid]["belief"] = 1.0
			mine[rid]["sev"] = maxf(float(mine[rid]["sev"]), sev)
			mine[rid]["t"] = now
			return int(rid)
	var rid := _new_rumor(subject, kind, true, witness, sev, now, whom)
	if rid == 0:
		return 0
	mine[rid] = _entry(1.0, "", now, sev, 0.0)
	mine[rid]["applied"] = 1.0  # svědek má vlastní zkušenost už ve vztahu (sociální paměť)
	_trim_known(witness)
	stats["observed"] = int(stats["observed"]) + 1
	return rid


func _new_rumor(subject: String, kind: String, truth: bool, origin: String, sev: float, now: float, whom: String) -> int:
	if rumors.size() >= MAX_RUMORS:
		_drop_weakest_rumor()
		if rumors.size() >= MAX_RUMORS:
			return 0
	var rid := _next_id
	_next_id += 1
	rumors[rid] = {"subject": subject, "kind": kind, "truth": truth, "origin": origin,
		"sev": sev, "t": now, "whom": whom.substr(0, MAX_KEY)}
	return rid


static func _entry(b: float, from: String, now: float, sev: float, dist: float) -> Dictionary:
	return {"belief": clampf(b, 0.0, 1.0), "from": from, "t": now, "sev": clampf(sev, 0.0, 1.0),
		"dist": clampf(dist, 0.0, 1.0), "told": [], "sources": ([from] if from != "" else []), "applied": 0.0}


# ---------------------------------------------------------------- výměna při rozhovoru

## Jeden směr výměny: `teller` může `listener`ovi říct jeden drb. Profily:
##   {key, honesty 0..1, extraversion 0..1, stigma 0..1, rel {key: −100..100}, grudge {key: 0..100}}
## facts = {"rel": {a: {listener: v}}} – skutečné vztahy ostatních K POSLUCHAČI (jen pro pravdivost pomluvy
## „mluví o tobě za zády“; stačí sloupec posluchače, ne celá matice).
## Vrací [] nebo [událost]: {type "shared", teller, listener, rid, subject, kind, fabricated, belief_gain,
## delta_rel (posluchač → subjekt), bond (posluchač → vypravěč)}.
func share(teller: Dictionary, listener: Dictionary, now: float, content: Dictionary, facts := {}) -> Array:
	var tk := String(teller.get("key", ""))
	var lk := String(listener.get("key", ""))
	if not _key_ok(tk) or not _key_ok(lk) or tk == lk or not is_finite(now):
		return []
	var honesty := clampf(_f(teller.get("honesty"), 0.5), 0.0, 1.0)
	var extra := clampf(_f(teller.get("extraversion"), 0.5), 0.0, 1.0)
	var trel: Dictionary = teller.get("rel", {}) if typeof(teller.get("rel")) == TYPE_DICTIONARY else {}
	var tgr: Dictionary = teller.get("grudge", {}) if typeof(teller.get("grudge")) == TYPE_DICTIONARY else {}
	var p_share := clampf(0.12 + 0.33 * extra + 0.35 * (1.0 - honesty), 0.05, 0.85)
	# 1) kandidáti z toho, co vypravěč ví
	var best_rid := 0
	var best_score := -1.0
	var mine: Dictionary = know.get(tk, {})
	var ids: Array = mine.keys()
	ids.sort()
	for rid in ids:
		var r: Dictionary = rumors.get(rid, {})
		var e: Dictionary = mine[rid]
		if r.is_empty() or float(e["belief"]) < SHARE_MIN_BELIEF or not content_ok(String(r["kind"]), content):
			continue
		var subj := String(r["subject"])
		if subj == tk or (e["told"] as Array).has(lk):
			continue
		var about_l: bool = bool(KINDS[r["kind"]]["about_listener"])
		if about_l and String(r["whom"]) != lk:
			continue
		if not about_l and subj == lk:
			continue
		var rel_ts := _f(trel.get(subj, 0.0))
		var score := float(e["sev"]) * float(e["belief"])
		if bool(KINDS[r["kind"]]["neg"]):
			score *= 1.0 + 0.5 * clampf(_f(tgr.get(subj, 0.0)) / 100.0, 0.0, 1.0) + clampf(-rel_ts / 200.0, -0.3, 0.5)
		else:
			score *= 0.5 + clampf(rel_ts / 100.0, 0.0, 1.0)
		if score > best_score:
			best_score = score
			best_rid = int(rid)
	var fabricated := false
	if best_rid != 0:
		if rng.randf() >= p_share * clampf(best_score * 1.6, 0.2, 1.0):
			return []
	else:
		# 2) smyšlená pomluva: jen nízká poctivost + silná zášť vůči někomu třetímu
		if honesty >= 0.35:
			return []
		var target := ""
		var animosity := 0.0
		var cand: Array = trel.keys()
		for g in tgr.keys():
			if not cand.has(g):
				cand.append(g)
		cand.sort()
		for c in cand:
			if typeof(c) != TYPE_STRING or c == tk or c == lk or not _key_ok(c):
				continue
			var a := maxf(-_f(trel.get(c, 0.0)), _f(tgr.get(c, 0.0)))
			if a > animosity:
				animosity = a
				target = c
		if target == "" or animosity < 35.0:
			return []
		var p_fab := (0.35 - honesty) / 0.35 * 0.35 * clampf(animosity / 100.0, 0.0, 1.0)
		if rng.randf() >= p_fab:
			return []
		var kind := "badmouth" if rng.randf() < 0.6 else "steals"
		var truth := false
		if kind == "badmouth":
			var fr: Dictionary = facts.get("rel", {}) if typeof(facts.get("rel")) == TYPE_DICTIONARY else {}
			var trow = fr.get(target, {})
			truth = typeof(trow) == TYPE_DICTIONARY and _f(trow.get(lk, 0.0)) < -25.0
		var sev := float(KINDS[kind]["sev"])
		best_rid = _new_rumor(target, kind, truth, tk, sev, now, lk if kind == "badmouth" else "")
		if best_rid == 0:
			return []
		var own := _knows(tk)
		own[best_rid] = _entry(1.0, "", now, sev, 0.0)
		own[best_rid]["applied"] = 1.0
		_trim_known(tk)
		fabricated = true
		stats["fabricated"] = int(stats["fabricated"]) + 1
	return [_transmit(best_rid, teller, listener, now, fabricated)]


func _transmit(rid: int, teller: Dictionary, listener: Dictionary, now: float, fabricated: bool) -> Dictionary:
	var tk := String(teller["key"])
	var lk := String(listener["key"])
	var r: Dictionary = rumors[rid]
	var subj := String(r["subject"])
	var te: Dictionary = know[tk][rid]
	var honesty := clampf(_f(teller.get("honesty"), 0.5), 0.0, 1.0)
	var lrel: Dictionary = listener.get("rel", {}) if typeof(listener.get("rel")) == TYPE_DICTIONARY else {}
	var rel_lt := _f(lrel.get(tk, 0.0))
	var rel_ls := _f(lrel.get(subj, 0.0))
	# Zkreslení: každé převyprávění přidá, nepoctivý vypravěč přifoukne víc. Závažnost roste se zkreslením.
	var dist := clampf(float(te["dist"]) + 0.08 + 0.14 * (1.0 - honesty), 0.0, 1.0)
	var sev := clampf(float(r["sev"]) * (1.0 + 0.6 * dist), 0.0, 1.0)
	var trust := clampf(0.55 + rel_lt / 180.0, 0.15, 0.95)
	var plaus := clampf(1.0 - rel_ls / 160.0, 0.35, 1.25)
	if not bool(KINDS[r["kind"]]["neg"]):
		plaus = clampf(1.0 + rel_ls / 300.0, 0.6, 1.25)
	var b_new := clampf(trust * plaus * (1.0 - 0.3 * dist) * float(te["belief"]), 0.0, 1.0)
	var mine := _knows(lk)
	var before := 0.0
	if mine.has(rid):
		var e: Dictionary = mine[rid]
		before = float(e["belief"])
		var srcs: Array = e["sources"]
		if not srcs.has(tk):
			# Sociální důkaz: nový nezávislý zdroj víru skládá.
			e["belief"] = clampf(1.0 - (1.0 - before) * (1.0 - b_new * 0.8), 0.0, 1.0)
			if srcs.size() < MAX_SOURCES:
				srcs.append(tk)
		else:
			e["belief"] = maxf(before, b_new)
		e["sev"] = maxf(float(e["sev"]), sev)
		e["dist"] = minf(float(e["dist"]), dist)
		e["t"] = now
	else:
		mine[rid] = _entry(b_new, tk, now, sev, dist)
		_trim_known(lk)
	var told: Array = te["told"]
	if not told.has(lk):
		told.append(lk)
		if told.size() > MAX_TOLD:
			told.remove_at(0)
	stats["shared"] = int(stats["shared"]) + 1
	var e2: Dictionary = mine.get(rid, {})
	var gain := 0.0
	var delta := 0.0
	if not e2.is_empty():
		gain = maxf(float(e2["belief"]) - float(e2["applied"]), 0.0)
		e2["applied"] = maxf(float(e2["applied"]), float(e2["belief"]))
		delta = _impact(String(r["kind"]), gain * float(e2["sev"]), rel_ls, clampf(_f(listener.get("stigma"), 0.0), 0.0, 1.0))
		delta = _cap_daily(lk, subj, delta, now)
	# Vztah k vypravěči: kdo drby nesnáší (vysoká H), toho to odradí; jinak sdílené tajemství sbližuje.
	# Denní strop 3 body na dvojici (drbáním se vztah „nevyfarmí“; review Gemini 9. 11.).
	var l_hon := clampf(_f(listener.get("honesty"), 0.5), 0.0, 1.0)
	var bond := _cap_daily_key("b|" + lk + "|" + tk, -1.5 if l_hon > 0.7 else 1.0, now, BOND_DAILY_CAP)
	return {"type": "shared", "teller": tk, "listener": lk, "rid": rid, "subject": subj, "kind": String(r["kind"]),
		"fabricated": fabricated, "truth": bool(r["truth"]), "belief": float(e2.get("belief", 0.0)),
		"belief_gain": gain, "delta_rel": delta, "bond": bond}


## Změna vztahu posluchače k subjektu z přírůstku víry × vnímané závažnosti.
static func _impact(kind: String, weight: float, rel_ls: float, stigma: float) -> float:
	if weight <= 0.0:
		return 0.0
	var d := 0.0
	if kind == "panic":
		# Nemoc není prohřešek: hůř si myslí jen stigmatizující posluchač.
		d = -NEG_IMPACT * weight * stigma
	elif bool(KINDS[kind]["neg"]):
		d = -NEG_IMPACT * weight * (1.0 - clampf(rel_ls, 0.0, 100.0) / 250.0)
	else:
		d = POS_IMPACT * weight
	return clampf(d, -EVENT_CAP, EVENT_CAP)


func _cap_daily(lk: String, subj: String, delta: float, now: float) -> float:
	return _cap_daily_key(lk + "|" + subj, delta, now, DAILY_PAIR_CAP)


func _cap_daily_key(k: String, delta: float, now: float, cap: float) -> float:
	if delta == 0.0:
		return 0.0
	var day := int(floor(now / 1440.0))
	# Úklid: záznamy ze starších dnů nic neomezují (dlouho běžící server nesmí bobtnat).
	if impact_day.size() >= 512:
		for old_k in impact_day.keys():
			if int(impact_day[old_k][0]) != day:
				impact_day.erase(old_k)
		if impact_day.size() >= 4000:
			return 0.0
	var rec: Array = impact_day.get(k, [day, 0.0])
	if int(rec[0]) != day:
		rec = [day, 0.0]
	var left := maxf(cap - float(rec[1]), 0.0)
	var d := clampf(delta, -left, left)
	rec[1] = float(rec[1]) + absf(d)
	impact_day[k] = rec
	return d


# ---------------------------------------------------------------- odhalení a vyvrácení

## `informer` (má subjekt rád) řekne `subject`u, co se o něm povídá. Vrací [] nebo [událost]:
## {type "exposed", informer, subject, rid, kind, source (od koho to informátor slyšel / "" viděl sám),
##  origin_known (subjekt ví i původce), truth, sev, delta_source (subjekt → zdroj), delta_informer}.
func expose(informer: Dictionary, subject: Dictionary, now: float, content: Dictionary) -> Array:
	var ik := String(informer.get("key", ""))
	var sk := String(subject.get("key", ""))
	if not _key_ok(ik) or not _key_ok(sk) or ik == sk or not know.has(ik):
		return []
	var irel: Dictionary = informer.get("rel", {}) if typeof(informer.get("rel")) == TYPE_DICTIONARY else {}
	var rel_is := _f(irel.get(sk, 0.0))
	if rel_is < 20.0:
		return []
	var mine: Dictionary = know[ik]
	var ids: Array = mine.keys()
	ids.sort()
	var pick := 0
	var pick_w := 0.0
	for rid in ids:
		var r: Dictionary = rumors.get(rid, {})
		if r.is_empty() or r["subject"] != sk or not bool(KINDS[r["kind"]]["neg"]) \
				or not content_ok(String(r["kind"]), content):
			continue
		if exposed.has(sk) and exposed[sk].has(rid):
			continue
		var e: Dictionary = mine[rid]
		# Svědek sám (from "") subjektu nic „neprozrazuje“ – mluví jen o tom, co slyšel od jiných.
		if String(e["from"]) == "":
			continue
		var w := float(e["sev"]) * maxf(float(e["belief"]), 0.3)
		if w > pick_w:
			pick_w = w
			pick = int(rid)
	if pick == 0:
		return []
	if rng.randf() >= clampf(0.25 + rel_is / 200.0, 0.0, 0.75):
		return []
	var r2: Dictionary = rumors[pick]
	var e2: Dictionary = mine[pick]
	if not exposed.has(sk):
		exposed[sk] = {}
	exposed[sk][pick] = now
	if exposed[sk].size() > MAX_KNOWN:
		var ks: Array = exposed[sk].keys()
		ks.sort()
		exposed[sk].erase(ks[0])
	stats["exposed"] = int(stats["exposed"]) + 1
	var source := String(e2["from"])
	_add_suspect(sk, source, pick, now)
	var sev := float(e2["sev"])
	# Subjekt se brání; lež informátora snáz přesvědčí.
	e2["belief"] = float(e2["belief"]) * (0.6 if not bool(r2["truth"]) else 0.85)
	var delta_source := -(EXPOSE_BASE + EXPOSE_SEV * sev)
	if bool(r2["truth"]):
		delta_source *= 0.7  # pravda: víc stud než křivda
	return [{"type": "exposed", "informer": ik, "subject": sk, "rid": pick, "kind": String(r2["kind"]),
		"source": source, "origin_known": source == String(r2["origin"]), "truth": bool(r2["truth"]),
		"sev": sev, "delta_source": delta_source, "delta_informer": 2.0}]


## Dobrá osobní zkušenost se subjektem oslabuje víru v záporné drby (lež rychleji). Vrací počet oslabených.
func contact(a: String, b: String) -> int:
	var n := 0
	for pair in [[a, b], [b, a]]:
		var k: String = pair[0]
		var other: String = pair[1]
		if not know.has(k):
			continue
		for rid in know[k]:
			var r: Dictionary = rumors.get(rid, {})
			if r.is_empty() or r["subject"] != other or not bool(KINDS[r["kind"]]["neg"]):
				continue
			var e: Dictionary = know[k][rid]
			if String(e["from"]) == "":
				continue  # co viděl sám, mu rozhovor nevymluví
			var before := float(e["belief"])
			e["belief"] = before * (0.85 if not bool(r["truth"]) else 0.95)
			n += 1
			if before >= SHARE_MIN_BELIEF and float(e["belief"]) < SHARE_MIN_BELIEF:
				stats["debunked"] = int(stats["debunked"]) + 1
	return n


# ---------------------------------------------------------------- čas a limity

## Vyhasínání víry po herních hodinách (nezávisle na délce kroku) a zapomínání.
func tick(dm: float) -> void:
	if dm <= 0.0 or not is_finite(dm):
		return
	_acc += dm
	if _acc < 60.0:
		return
	var step := _acc
	_acc = 0.0
	var k_decay := exp(-step / BELIEF_TAU_MIN)
	var keys: Array = know.keys()
	keys.sort()
	for k in keys:
		var drop: Array = []
		for rid in know[k]:
			var e: Dictionary = know[k][rid]
			e["belief"] = float(e["belief"]) * k_decay
			if float(e["belief"]) < FORGET_BELIEF:
				drop.append(rid)
		for rid in drop:
			know[k].erase(rid)
			stats["forgotten"] = int(stats["forgotten"]) + 1
		if know[k].is_empty():
			know.erase(k)
	_expire_suspects(step)
	_gc()


## Podezření stárnou s herním časem (nezávisle na absolutních časech v uložení).
func _expire_suspects(step: float) -> void:
	var subs: Array = suspects.keys()
	subs.sort()
	for s in subs:
		for src in (suspects[s] as Dictionary).keys():
			var e: Dictionary = suspects[s][src]
			e["age"] = float(e.get("age", 0.0)) + step
			if float(e["age"]) > SUSPECT_TTL_MIN:
				suspects[s].erase(src)
		if (suspects[s] as Dictionary).is_empty():
			suspects.erase(s)


## Drby, které nikdo nezná, zmizí (odhalení se pamatují dál jen dokud drb existuje).
func _gc() -> void:
	var alive := {}
	for k in know:
		for rid in know[k]:
			alive[rid] = true
	for rid in rumors.keys():
		if not alive.has(rid):
			rumors.erase(rid)
	for s in exposed.keys():
		for rid in exposed[s].keys():
			if not rumors.has(rid):
				exposed[s].erase(rid)
		if exposed[s].is_empty():
			exposed.erase(s)


func _trim_known(k: String) -> void:
	var mine: Dictionary = know.get(k, {})
	while mine.size() > MAX_KNOWN:
		var worst := -1
		var wb := 2.0
		var ids: Array = mine.keys()
		ids.sort()
		for rid in ids:
			if float(mine[rid]["belief"]) < wb:
				wb = float(mine[rid]["belief"])
				worst = int(rid)
		mine.erase(worst)


func _drop_weakest_rumor() -> void:
	var total := {}
	for k in know:
		for rid in know[k]:
			total[rid] = float(total.get(rid, 0.0)) + float(know[k][rid]["belief"])
	var worst := -1
	var wv := INF
	var ids: Array = rumors.keys()
	ids.sort()
	for rid in ids:
		var v := float(total.get(rid, 0.0))
		if v < wv:
			wv = v
			worst = int(rid)
	if worst < 0:
		return
	rumors.erase(worst)
	for k in know.keys():
		know[k].erase(worst)
		if know[k].is_empty():
			know.erase(k)
	_gc()


## Postava odešla ze světa natrvalo: její znalosti zmizí (drby o ní žijí dál u ostatních).
func forget_knower(key: String) -> void:
	know.erase(key)
	suspects.erase(key)
	for s in suspects.keys():
		suspects[s].erase(key)
		if suspects[s].is_empty():
			suspects.erase(s)
	_gc()


# ---------------------------------------------------------------- uložení

func to_dict() -> Dictionary:
	var rs: Array = []
	var ids: Array = rumors.keys()
	ids.sort()
	for rid in ids:
		var r: Dictionary = rumors[rid]
		rs.append({"id": int(rid), "subject": r["subject"], "kind": r["kind"], "truth": r["truth"],
			"origin": r["origin"], "sev": r["sev"], "t": r["t"], "whom": r["whom"]})
	var kn := {}
	for k in know:
		var arr: Array = []
		var rids: Array = know[k].keys()
		rids.sort()
		for rid in rids:
			var e: Dictionary = know[k][rid]
			arr.append({"rid": int(rid), "belief": e["belief"], "from": e["from"], "t": e["t"], "sev": e["sev"],
				"dist": e["dist"], "told": (e["told"] as Array).duplicate(), "sources": (e["sources"] as Array).duplicate(),
				"applied": e["applied"]})
		kn[k] = arr
	var ex := {}
	for s in exposed:
		var m := {}
		for rid in exposed[s]:
			m[str(rid)] = exposed[s][rid]
		ex[s] = m
	var su := {}
	for s in suspects:
		var m3 := {}
		for src in suspects[s]:
			var e: Dictionary = suspects[s][src]
			m3[src] = {"rid": int(e["rid"]), "t": e["t"], "kind": e["kind"], "truth": e["truth"], "origin": e["origin"],
				"age": float(e.get("age", 0.0))}
		su[s] = m3
	return {"v": VERSION, "rng_state": rng.state, "next_id": _next_id, "acc": _acc, "rumors": rs, "know": kn,
		"exposed": ex, "impact_day": impact_day.duplicate(true), "names": names.duplicate(true),
		"stats": stats.duplicate(), "suspects": su}


static func _n(v: Variant, lo: float, hi: float) -> bool:
	return typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


static func _key_list(v: Variant, max_n: int) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() > max_n:
		return false
	for x in v:
		if not _key_ok(x):
			return false
	return true


## Striktní validace (soubor může být podvržený). Neznámý klíč = neplatné.
static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for key in d:
		if not ["v", "rng_state", "next_id", "acc", "rumors", "know", "exposed", "impact_day", "names", "stats", "suspects"].has(key):
			return false
	if typeof(d.get("v")) != TYPE_INT or int(d["v"]) < MIN_VERSION or int(d["v"]) > VERSION:
		return false
	if int(d["v"]) < 2 and d.has("suspects"):
		return false
	if typeof(d.get("rng_state")) != TYPE_INT or not _n(d.get("next_id"), 1.0, 1.0e9) \
			or not _n(d.get("acc", 0.0), 0.0, 1.0e6):
		return false
	var rs = d.get("rumors")
	if typeof(rs) != TYPE_ARRAY or rs.size() > MAX_RUMORS:
		return false
	var ids := {}
	for r in rs:
		if typeof(r) != TYPE_DICTIONARY or r.size() != 8:
			return false
		if typeof(r.get("id")) != TYPE_INT or int(r["id"]) < 1 or int(r["id"]) >= int(d["next_id"]) or ids.has(int(r["id"])):
			return false
		ids[int(r["id"])] = true
		if not _key_ok(r.get("subject")) or not _key_ok(r.get("origin")) or typeof(r.get("kind")) != TYPE_STRING \
				or not KINDS.has(r["kind"]) or typeof(r.get("truth")) != TYPE_BOOL or not _n(r.get("sev"), 0.0, 1.0) \
				or not _n(r.get("t"), -1.0e12, 1.0e12) or typeof(r.get("whom")) != TYPE_STRING or String(r["whom"]).length() > MAX_KEY:
			return false
		# Pravdivý drb nemůže být druhu, který jde jen smyslet (krádeže zatím ve hře nejsou).
		if r["kind"] == "steals" and bool(r["truth"]):
			return false
	var kn = d.get("know")
	if typeof(kn) != TYPE_DICTIONARY or kn.size() > MAX_KNOWERS:
		return false
	for k in kn:
		if not _key_ok(k) or typeof(kn[k]) != TYPE_ARRAY or kn[k].size() > MAX_KNOWN:
			return false
		var seen := {}
		for e in kn[k]:
			if typeof(e) != TYPE_DICTIONARY or e.size() != 9:
				return false
			if typeof(e.get("rid")) != TYPE_INT or not ids.has(int(e["rid"])) or seen.has(int(e["rid"])):
				return false
			seen[int(e["rid"])] = true
			if not _n(e.get("belief"), 0.0, 1.0) or not _n(e.get("sev"), 0.0, 1.0) or not _n(e.get("dist"), 0.0, 1.0) \
					or not _n(e.get("applied"), 0.0, 1.0) or not _n(e.get("t"), -1.0e12, 1.0e12):
				return false
			if typeof(e.get("from")) != TYPE_STRING or String(e["from"]).length() > MAX_KEY or e["from"] == k:
				return false
			if not _key_list(e.get("told"), MAX_TOLD) or not _key_list(e.get("sources"), MAX_SOURCES):
				return false
	var ex = d.get("exposed")
	if typeof(ex) != TYPE_DICTIONARY or ex.size() > 256:
		return false
	for s in ex:
		if not _key_ok(s) or typeof(ex[s]) != TYPE_DICTIONARY or ex[s].size() > MAX_KNOWN:
			return false
		for rk in ex[s]:
			if typeof(rk) != TYPE_STRING or not rk.is_valid_int() or not ids.has(int(rk)) or not _n(ex[s][rk], -1.0e12, 1.0e12):
				return false
	var im = d.get("impact_day")
	if typeof(im) != TYPE_DICTIONARY or im.size() > 4096:
		return false
	for k in im:
		if typeof(k) != TYPE_STRING or String(k).length() > 2 * MAX_KEY + 3 or typeof(im[k]) != TYPE_ARRAY or im[k].size() != 2:
			return false
		if not _n(im[k][0], -1.0e9, 1.0e9) or not _n(im[k][1], 0.0, DAILY_PAIR_CAP + 0.001):
			return false
	var nm = d.get("names")
	if typeof(nm) != TYPE_DICTIONARY or nm.size() > MAX_NAMES:
		return false
	for k in nm:
		var v = nm[k]
		if not _key_ok(k) or typeof(v) != TYPE_DICTIONARY or v.size() != 2 or typeof(v.get("n")) != TYPE_STRING \
				or String(v["n"]).length() > MAX_NAME or not Grammar.valid(v.get("g")):
			return false
	var st = d.get("stats")
	if typeof(st) != TYPE_DICTIONARY or st.size() > STAT_KEYS.size():
		return false
	for k in st:
		if typeof(k) != TYPE_STRING or not STAT_KEYS.has(k) or not _n(st[k], 0.0, 1.0e12):
			return false
	var su = d.get("suspects", {})
	if typeof(su) != TYPE_DICTIONARY or su.size() > MAX_KNOWERS:
		return false
	for s in su:
		if not _key_ok(s) or typeof(su[s]) != TYPE_DICTIONARY or su[s].size() > MAX_SUSPECTS or su[s].is_empty():
			return false
		for src in su[s]:
			var e = su[s][src]
			if not _key_ok(src) or src == s or typeof(e) != TYPE_DICTIONARY or e.size() != 6:
				return false
			if typeof(e.get("rid")) != TYPE_INT or int(e["rid"]) < 1 or int(e["rid"]) >= int(d["next_id"]) \
					or not _n(e.get("t"), -1.0e12, 1.0e12) or typeof(e.get("kind")) != TYPE_STRING or not KINDS.has(e["kind"]) \
					or not bool(KINDS[e["kind"]]["neg"]) or typeof(e.get("truth")) != TYPE_BOOL or typeof(e.get("origin")) != TYPE_BOOL \
					or not _n(e.get("age"), 0.0, SUSPECT_TTL_MIN):
				return false
			if e["kind"] == "steals" and bool(e["truth"]):
				return false
	return true


func from_dict(d: Variant) -> bool:
	if not validate_snapshot(d):
		return false
	rumors = {}
	for r in d["rumors"]:
		rumors[int(r["id"])] = {"subject": String(r["subject"]), "kind": String(r["kind"]), "truth": bool(r["truth"]),
			"origin": String(r["origin"]), "sev": float(r["sev"]), "t": float(r["t"]), "whom": String(r["whom"])}
	know = {}
	for k in d["know"]:
		var m := {}
		for e in d["know"][k]:
			m[int(e["rid"])] = {"belief": float(e["belief"]), "from": String(e["from"]), "t": float(e["t"]),
				"sev": float(e["sev"]), "dist": float(e["dist"]), "told": (e["told"] as Array).duplicate(),
				"sources": (e["sources"] as Array).duplicate(), "applied": float(e["applied"])}
		if not m.is_empty():
			know[String(k)] = m
	exposed = {}
	for s in d["exposed"]:
		var m2 := {}
		for rk in d["exposed"][s]:
			m2[int(rk)] = float(d["exposed"][s][rk])
		if not m2.is_empty():
			exposed[String(s)] = m2
	impact_day = {}
	for k in d["impact_day"]:
		impact_day[String(k)] = [int(d["impact_day"][k][0]), float(d["impact_day"][k][1])]
	names = {}
	for k in d["names"]:
		names[String(k)] = {"n": String(d["names"][k]["n"]), "g": String(d["names"][k]["g"])}
	stats = {}
	for k in STAT_KEYS:
		stats[k] = 0
	for k in d["stats"]:
		stats[k] = int(d["stats"][k])
	suspects = {}
	var su: Dictionary = d.get("suspects", {})
	for s in su:
		var m3 := {}
		for src in su[s]:
			var e: Dictionary = su[s][src]
			m3[String(src)] = {"rid": int(e["rid"]), "t": float(e["t"]), "kind": String(e["kind"]),
				"truth": bool(e["truth"]), "origin": bool(e["origin"]), "age": float(e["age"])}
		suspects[String(s)] = m3
	_next_id = int(d["next_id"])
	_acc = float(d.get("acc", 0.0))
	rng.state = int(d["rng_state"])
	return true


# ---------------------------------------------------------------- konfrontace a popření (10. 11. 2026)

## Podezřelí: subjekt se při odhalení dozvěděl, od koho drb šel (bezprostřední zdroj). Jen ty smí konfrontovat.
## suspects[subject][source] = {rid, t, kind, truth, origin} – údaje se kopírují, aby konfrontace dávala
## smysl i poté, co drb sám vyhasl. Platnost SUSPECT_TTL, nejvýš MAX_SUSPECTS na subjekt.
func _add_suspect(subject: String, source: String, rid: int, now: float) -> void:
	if not _key_ok(subject) or not _key_ok(source) or subject == source or not rumors.has(rid):
		return
	if not suspects.has(subject):
		if suspects.size() >= MAX_KNOWERS:
			return
		suspects[subject] = {}
	var r: Dictionary = rumors[rid]
	suspects[subject][source] = {"rid": rid, "t": now, "kind": String(r["kind"]), "truth": bool(r["truth"]),
		"origin": String(r["origin"]) == source}
	while suspects[subject].size() > MAX_SUSPECTS:
		var oldest := ""
		var ot := INF
		var ks: Array = suspects[subject].keys()
		ks.sort()
		for k in ks:
			if float(suspects[subject][k]["t"]) < ot:
				ot = float(suspects[subject][k]["t"])
				oldest = k
		suspects[subject].erase(oldest)


func can_confront(subject: String, accused: String) -> bool:
	return suspects.has(subject) and suspects[subject].has(accused)


## Soukromé věty pro subjekt: od koho ty řeči šly (jen jména, bez čísel).
func suspect_lines(subject: String, limit := 2) -> PackedStringArray:
	var out := PackedStringArray()
	if not suspects.has(subject):
		return out
	var ks: Array = suspects[subject].keys()
	ks.sort()
	for k in ks:
		if out.size() >= limit:
			break
		var nm := String(names.get(k, {}).get("n", ""))
		if nm != "":
			out.append("Ty řeči o mně šly od: %s." % nm)
	return out


## Pravděpodobnosti výsledku konfrontace (pro test i ladění). Přizná poctivý a přívětivý obviněný;
## kdo lež sám vymyslel, přiznává hůř; hádka hrozí u nepřívětivých (obou stran).
static func confront_odds(acc_honesty: float, acc_agree: float, sub_agree: float, lied_origin: bool) -> Dictionary:
	var p_admit := clampf(0.15 + 0.55 * acc_honesty + 0.2 * acc_agree - (0.15 if lied_origin else 0.0), 0.05, 0.9)
	var p_esc := clampf(0.06 + 0.3 * (1.0 - acc_agree) + 0.2 * (1.0 - sub_agree), 0.05, 0.6)
	var p_escalate := (1.0 - p_admit) * p_esc
	return {"admit": p_admit, "escalate": p_escalate, "deny": maxf(1.0 - p_admit - p_escalate, 0.0)}


## `subject` si to vyříká s `accused` (musí být podezřelý). Podezření se spotřebuje (žádný spam).
## Vrací {} nebo událost {type "confront", subject, accused, rid, kind, outcome admit|deny|escalate, truth,
## origin, retracted (kolika posluchačům obviněný drb vyvrátil), delta_subject (subjekt → obviněný),
## delta_accused (obviněný → subjekt), guilt (vina obviněného)}.
func confront(subject: Dictionary, accused: Dictionary, now: float) -> Dictionary:
	var sk := String(subject.get("key", ""))
	var ak := String(accused.get("key", ""))
	if not _key_ok(sk) or not _key_ok(ak) or sk == ak or not is_finite(now) or not can_confront(sk, ak):
		return {}
	var s: Dictionary = suspects[sk][ak]
	suspects[sk].erase(ak)
	if suspects[sk].is_empty():
		suspects.erase(sk)
	var truth := bool(s["truth"])
	var origin := bool(s["origin"])
	var odds := confront_odds(clampf(_f(accused.get("honesty"), 0.5), 0.0, 1.0),
		clampf(_f(accused.get("agreeableness"), 0.5), 0.0, 1.0),
		clampf(_f(subject.get("agreeableness"), 0.5), 0.0, 1.0), origin and not truth)
	var roll := rng.randf()
	var outcome := "deny"
	if roll < float(odds["admit"]):
		outcome = "admit"
	elif roll < float(odds["admit"]) + float(odds["escalate"]):
		outcome = "escalate"
	var rid := int(s["rid"])
	var retracted := 0
	var d_sub := 0.0
	var d_acc := 0.0
	var guilt := 0.0
	match outcome:
		"admit":
			# Obviněný to odvolá u lidí, kterým to řekl: lež ztratí víc než pravda.
			if know.has(ak) and know[ak].has(rid):
				var te: Dictionary = know[ak][rid]
				for lk in te["told"]:
					if know.has(lk) and know[lk].has(rid):
						var e: Dictionary = know[lk][rid]
						var before := float(e["belief"])
						e["belief"] = before * (0.5 if not truth else 0.8)
						retracted += 1
						if before >= SHARE_MIN_BELIEF and float(e["belief"]) < SHARE_MIN_BELIEF:
							stats["debunked"] = int(stats.get("debunked", 0)) + 1
				if not truth:
					te["belief"] = float(te["belief"]) * 0.3
			stats["retracted"] = int(stats.get("retracted", 0)) + retracted
			d_sub = 3.0 if not truth else 4.0
			guilt = 6.0 + (8.0 if origin and not truth else 0.0)
		"deny":
			d_sub = -3.0 if not truth else -1.5
			d_acc = -2.0
			guilt = 3.0 if origin and not truth else 0.0
		"escalate":
			pass  # hádku (vztahy, stres, svědci → nové drby) řeší simulace postav
	stats["confronted"] = int(stats.get("confronted", 0)) + 1
	return {"type": "confront", "subject": sk, "accused": ak, "rid": rid, "kind": String(s["kind"]),
		"outcome": outcome, "truth": truth, "origin": origin, "retracted": retracted,
		"delta_subject": d_sub, "delta_accused": d_acc, "guilt": guilt}


## `subject` popírá před `listener`em záporné drby o sobě (ten nejsilnější, kterému posluchač věří).
## Subjekt neví, co posluchač ví – může narazit. Výsledky: nothing (posluchač nic neví), believed /
## doubted (víra klesla pod / zůstala nad hranicí šíření), caught (pravdu, kterou posluchač viděl sám,
## popřít nejde → „lže mi do očí“). Jednou denně na dvojici. Vrací {} nebo událost {type "deny", subject,
## listener, rid, kind, outcome, truth, belief, delta_rel (posluchač → subjekt; návrat části dopadu)}.
func deny(subject: Dictionary, listener: Dictionary, now: float, content: Dictionary) -> Dictionary:
	var sk := String(subject.get("key", ""))
	var lk := String(listener.get("key", ""))
	if not _key_ok(sk) or not _key_ok(lk) or sk == lk or not is_finite(now):
		return {}
	var base := {"type": "deny", "subject": sk, "listener": lk, "rid": 0, "kind": "", "outcome": "nothing",
		"truth": false, "belief": 0.0, "delta_rel": 0.0}
	if _cap_daily_key("d|" + lk + "|" + sk, 1.0, now, 1.0) <= 0.0:
		base["outcome"] = "repeat"
		return base
	var mine: Dictionary = know.get(lk, {})
	var ids: Array = mine.keys()
	ids.sort()
	var pick := 0
	var pw := 0.0
	for rid in ids:
		var r: Dictionary = rumors.get(rid, {})
		if r.is_empty() or r["subject"] != sk or not bool(KINDS[r["kind"]]["neg"]) or not content_ok(String(r["kind"]), content):
			continue
		var e: Dictionary = mine[rid]
		var w := float(e["belief"]) * float(e["sev"])
		if float(e["belief"]) >= FORGET_BELIEF and w > pw:
			pw = w
			pick = int(rid)
	if pick == 0:
		return base
	var r2: Dictionary = rumors[pick]
	var e2: Dictionary = mine[pick]
	var truth := bool(r2["truth"])
	base["rid"] = pick
	base["kind"] = String(r2["kind"])
	base["truth"] = truth
	if truth and String(e2["from"]) == "":
		base["outcome"] = "caught"
		base["belief"] = float(e2["belief"])
		base["delta_rel"] = -4.0
		stats["denied"] = int(stats.get("denied", 0)) + 1
		return base
	var lrel: Dictionary = listener.get("rel", {}) if typeof(listener.get("rel")) == TYPE_DICTIONARY else {}
	var trust := clampf(0.4 + _f(lrel.get(sk, 0.0)) / 150.0, 0.1, 0.9)
	var before := float(e2["belief"])
	e2["belief"] = before * (1.0 - (0.6 if not truth else 0.25) * trust)
	# Část dopadu na vztah se vrátí (úměrně tomu, o kolik víra klesla pod už promítnutou úroveň).
	var applied := float(e2["applied"])
	var back := maxf(applied - float(e2["belief"]), 0.0)
	e2["applied"] = minf(applied, float(e2["belief"]))
	var rec := 0.0
	if not (String(r2["kind"]) == "panic"):
		rec = clampf(NEG_IMPACT * 0.5 * back * float(e2["sev"]), 0.0, EVENT_CAP * 0.5)
	base["belief"] = float(e2["belief"])
	base["delta_rel"] = rec
	base["outcome"] = "believed" if float(e2["belief"]) < SHARE_MIN_BELIEF else "doubted"
	if before >= SHARE_MIN_BELIEF and float(e2["belief"]) < SHARE_MIN_BELIEF:
		stats["debunked"] = int(stats.get("debunked", 0)) + 1
	stats["denied"] = int(stats.get("denied", 0)) + 1
	return base
