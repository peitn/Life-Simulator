extends RefCounted
## Infidelity – nevěra, podezření a žárlivost v partnerství.
##
## Proč: Romance (scripts/sim/romance.gd) je monogamní stav dvojice. Skutečný život ale monogamii
## občas porušuje: začne to nevinným flirtem, mezi dvěma lidmi přeskočí jiskra, pak tajná schůzka.
## Partner/ka si všimne změn, zaslechne drb, nebo je přistihne. Následuje konfrontace – přiznání,
## zapírání, usvědčení ze lži, nebo trapná žárlivá scéna bez důvodu. Zrada má trvalé následky
## (důvěra, zášť, spokojenost ve vztahu, dusno doma), ale cesta dál – rozchod i odpuštění – je na
## postavách (AI) nebo na hráči. Hra nic z toho neodměňuje body ani úspěchy.
##
## Model (vše jen na autoritě, uvnitř HouseholdDynamics; žádná náhoda zde – hody dodává volající):
## - JISKRA (spark) dvojice 0..1 z opětovaného flirtu (klesající výnos, nejvýš jednou za FLIRT_GAP),
##   vyhasíná s časovou konstantou SPARK_TAU. Bez jiskry žádná tajná schůzka („z ničeho nic“ to nejde).
## - ROMÁNEK (affair) dvojice: počet schůzek, kdo koho zrazuje (partner v době schůzky), kdo už o tom ví.
## - PODEZŘENÍ partnera P vůči A ("P>A"): v 0..1 (vyhasíná SUSP_TAU), důkazy ev 0..1 (nevyhasínají
##   tak rychle – co člověk viděl, to viděl), nápověda s kým.
## - Intimita (fade-to-black, adult_consensual_sex) se zadaným člověkem mimo jeho vztah = nevěra.
##
## Zobrazení: nic explicitního. Tajná schůzka je náznak (fade-to-black), repliky jsou dospělé, ale
## bez popisu. Všechny postavy v tomto modulu musí být dospělé (pojistka i pro poškozená data).

const Romance := preload("res://scripts/sim/romance.gd")

## Jiskra.
const SPARK_FLIRT := 0.22
const SPARK_TAU := 10080.0          # 7 dní
const SPARK_AFFAIR_MIN := 0.4       # minimum pro tajnou schůzku
const SPARK_DATE := 0.12            # schůzka jiskru přiživí
const FLIRT_GAP := 90.0
## Podezření a důkazy.
const SUSP_TAU := 30240.0           # 21 dní
const EV_TAU := 86400.0             # 60 dní
const SUSP_CONFRONT := 0.35         # od kdy AI konfrontuje
const SUSP_SEEN_FLIRT := 0.25
const EV_SEEN_FLIRT := 0.35
const SUSP_BEHAVIOR := 0.06         # po každé schůzce (vymlouvání, telefon, pozdní příchody)
const SUSP_RUMOR := 0.55            # × víra v drb
const EV_RUMOR := 0.7               # × víra v drb
const EV_LIE_PROOF := 0.6           # nad tím se zapírání neudrží
## Konfrontace.
const CONFRONT_GAP := 1440.0        # AI nekonfrontuje častěji než jednou denně
const INNOCENT_DAMP := 0.4          # podezření po zjištění „nic tam není“
const DENIED_DAMP := 0.85           # zapřeno (a nedokázáno): podezření trochu opadne
## AI.
const AI_FLIRT_EVERY := 720.0
const AI_DATE_EVERY := 2880.0
const AI_FLIRT_REL := 25.0
const AI_DATE_REL := 40.0
const AI_TEMPT_MIN := 0.35
const PARTNER_NEAR := 15.0
## Limity (hostile save / server).
const MAX_SPARKS := 256
const MAX_AFFAIRS := 128
const MAX_SUSP := 256
const MAX_NAME := 64
const MAX_KNOWN := 8
const FLIRT_OUTCOMES := ["reciprocated", "brushed_off", "uncomfortable", "own_partner"]
const CONFRONT_OUTCOMES := ["confess", "denied", "caught_lying", "innocent"]

var sparks := {}     # "A|B" -> {"v", "t", "last_flirt"}
var affairs := {}    # "A|B" -> {"since", "last", "dates", "betrays": {jméno: partner}, "known_by": [jména]}
var suspicion := {}  # "P>A" -> {"v", "ev", "t", "hint", "last_confront"}
var _last_ai := {}   # jméno -> {"flirt": t, "date": t}
var _last_gc := -1.0e12
## Odbytí: "A>B" -> kdy B odbyl(a) flirt od A (AI pak 3 dny nezkouší znovu; Grok #551).
var rebuffs := {}
const REBUFF_PAUSE := 4320.0
## Uklidnění: příjemný kontakt s partnerem podezření (ne důkazy) zmírní.
const REASSURE := 0.9
var stats := {}


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {"flirts": 0, "reciprocated": 0, "brushed_off": 0, "uncomfortable": 0, "own_partner": 0,
		"dates": 0, "date_refused": 0, "intimate": 0, "caught": 0, "confrontations": 0,
		"confess": 0, "denied": 0, "caught_lying": 0, "innocent": 0, "rumor_hints": 0}


static func susp_key(p: String, a: String) -> String:
	return p + ">" + a


static func _valid_name(n) -> bool:
	return typeof(n) == TYPE_STRING and String(n) != "" and String(n).length() <= MAX_NAME \
		and not String(n).contains("|") and not String(n).contains(">")


static func _fin(v, lo: float, hi: float, dflt: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return dflt
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return dflt
	return clampf(f, lo, hi)


static func _decay(v: float, t0: float, now: float, tau: float) -> float:
	# Zpětný chod času (rewind) nic „nevrací“ ani nezesiluje: dt < 0 = beze změny.
	var dt := now - t0
	if dt <= 0.0:
		return v
	return v * exp(-dt / tau)


# ------------------------------------------------------------------ jiskra

func spark(a: String, b: String, now: float) -> float:
	var r: Dictionary = sparks.get(Romance.key(a, b), {})
	if r.is_empty():
		return 0.0
	return _decay(float(r["v"]), float(r["t"]), now, SPARK_TAU)


func _add_spark(a: String, b: String, amount: float, now: float) -> void:
	var k := Romance.key(a, b)
	if not sparks.has(k):
		if sparks.size() >= MAX_SPARKS:
			_gc(now)
			if sparks.size() >= MAX_SPARKS:
				_evict_weakest(sparks, "|", now)  # audit Gemini: nová jiskra vytlačí nejslabší, nezahodí se
		sparks[k] = {"v": 0.0, "t": now, "last_flirt": -1.0e9}
	var r: Dictionary = sparks[k]
	var v := spark(a, b, now)
	r["v"] = clampf(v + amount * (1.0 - v), 0.0, 1.0)
	r["t"] = maxf(float(r["t"]), now)


## Šance, že druhý flirt opětuje. rel/trust/mood cíle; taken_t = cíl je zadaný (s někým jiným),
## loyal_t 0..1 = jeho věrnost (poctivost + spokojenost ve vlastním vztahu).
static func flirt_p(rel_t: float, trust_t: float, mood_t: float, taken_t: bool, loyal_t: float) -> float:
	var p := 0.15 + 0.6 * clampf((rel_t + 10.0) / 90.0, 0.0, 1.0) + 0.1 * clampf(trust_t / 100.0, 0.0, 1.0)
	p += clampf(mood_t, -100.0, 100.0) / 500.0
	if taken_t:
		p *= clampf(1.0 - 0.85 * loyal_t, 0.05, 1.0)
	return clampf(p, 0.02, 0.92)


## Flirt `a` → `b`. fits_ba = přitahuje `b` člověk jako `a`? (Romance.fits(pa, pb)). Výsledek:
## "own_partner" (flirt s vlastním partnerem – vždy vítaný, jiskru nepočítá), "uncomfortable"
## (nesoulad přitažlivosti: druhému je to nepříjemné), "reciprocated", "brushed_off".
func resolve_flirt(a: String, b: String, ro, fits_ba: bool, p: float, roll: float, now: float) -> String:
	if a == "" or b == "" or a == b:
		return "uncomfortable"
	stats["flirts"] += 1
	var outcome := ""
	if ro != null and ro.together(a, b):
		outcome = "own_partner"
	elif not fits_ba:
		outcome = "uncomfortable"
	elif roll < clampf(p, 0.0, 1.0):
		outcome = "reciprocated"
		var r: Dictionary = sparks.get(Romance.key(a, b), {})
		var last := float(r.get("last_flirt", -1.0e9))
		if r.is_empty() or now - last >= FLIRT_GAP or last > now:
			_add_spark(a, b, SPARK_FLIRT, now)
			var r2: Dictionary = sparks.get(Romance.key(a, b), {})
			if not r2.is_empty():
				r2["last_flirt"] = now
	else:
		outcome = "brushed_off"
	if outcome in ["brushed_off", "uncomfortable"]:
		if rebuffs.size() >= MAX_SPARKS and not rebuffs.has(susp_key(a, b)):
			_prune_rebuffs(now)
		if rebuffs.size() < MAX_SPARKS or rebuffs.has(susp_key(a, b)):
			rebuffs[susp_key(a, b)] = now
		var rs: Dictionary = sparks.get(Romance.key(a, b), {})
		if not rs.is_empty():
			rs["v"] = spark(a, b, now) * 0.7  # odbytí jiskru zchladí
			rs["t"] = maxf(float(rs["t"]), now)
	stats[outcome] += 1
	return outcome


func rebuffed(a: String, b: String, now: float) -> bool:
	var t := float(rebuffs.get(susp_key(a, b), -1.0e12))
	return t <= now and now - t < REBUFF_PAUSE


func _prune_rebuffs(now: float) -> void:
	for k in rebuffs.keys():
		if now - float(rebuffs[k]) >= REBUFF_PAUSE or float(rebuffs[k]) > now:
			rebuffs.erase(k)
	if rebuffs.size() >= MAX_SPARKS:
		var ks: Array = rebuffs.keys()
		ks.sort_custom(func(x, y): return float(rebuffs[x]) < float(rebuffs[y]) or (float(rebuffs[x]) == float(rebuffs[y]) and str(x) < str(y)))
		rebuffs.erase(ks[0])


## Je flirt/schůzka `a` s `b` zradou? Vrací {jméno: zrazený partner} pro oba (prázdný řetězec = ne).
static func betrayals(a: String, b: String, ro) -> Dictionary:
	var out := {a: "", b: ""}
	if ro == null:
		return out
	var pa: String = ro.partner_of(a)
	var pb: String = ro.partner_of(b)
	if pa != "" and pa != b:
		out[a] = pa
	if pb != "" and pb != a:
		out[b] = pb
	return out


# ------------------------------------------------------------------ tajná schůzka

## Smí `a` navrhnout tajnou schůzku `b`? "" = ano, jinak: "self" / "own_partner" (spolu chodí – stačí
## rande) / "free" (nikdo z nich není zadaný – to je obyčejné pozvání na rande) / "no_spark" / "not_now".
func date_block(a: String, b: String, ro, now: float) -> String:
	if a == "" or b == "" or a == b:
		return "self"
	if ro != null and ro.together(a, b):
		return "own_partner"
	var bt := betrayals(a, b, ro)
	if String(bt[a]) == "" and String(bt[b]) == "":
		return "free"
	if spark(a, b, now) < SPARK_AFFAIR_MIN:
		return "no_spark"
	var af: Dictionary = affairs.get(Romance.key(a, b), {})
	if not af.is_empty() and now - float(af["last"]) < 120.0 and float(af["last"]) <= now:
		return "not_now"
	return ""


## Výsledek návrhu tajné schůzky: "yes" / "no" (nebo blokace z date_block – pak se nic nemění).
## fits_ba jako u flirtu; p = šance, že `b` kývne (volající: flirt_p × jiskra).
func resolve_date(a: String, b: String, ro, fits_ba: bool, p: float, roll: float, now: float) -> String:
	var block := date_block(a, b, ro, now)
	if block != "":
		return block
	if not fits_ba or roll >= clampf(p, 0.0, 1.0):
		stats["date_refused"] += 1
		var r: Dictionary = sparks.get(Romance.key(a, b), {})
		if not r.is_empty():
			r["v"] = spark(a, b, now) * 0.6  # odmítnutí jiskru zchladí
			r["t"] = maxf(float(r["t"]), now)
		return "no"
	_note_affair(a, b, ro, now)
	_add_spark(a, b, SPARK_DATE, now)
	stats["dates"] += 1
	return "yes"


func _note_affair(a: String, b: String, ro, now: float) -> Dictionary:
	var k := Romance.key(a, b)
	if not affairs.has(k):
		if affairs.size() >= MAX_AFFAIRS:
			_drop_oldest_affair()
		affairs[k] = {"since": now, "last": now, "dates": 0, "betrays": {}, "known_by": []}
	var af: Dictionary = affairs[k]
	af["last"] = maxf(float(af["last"]), now)
	af["dates"] = mini(int(af["dates"]) + 1, 100000)
	var bt := betrayals(a, b, ro)
	for who in [a, b]:
		if String(bt[who]) != "":
			(af["betrays"] as Dictionary)[who] = String(bt[who])
	return af


func _drop_oldest_affair() -> void:
	var oldest := ""
	var t := INF
	var ks: Array = affairs.keys()
	ks.sort()
	for k in ks:
		if float(affairs[k]["last"]) < t:
			t = float(affairs[k]["last"])
			oldest = k
	if oldest != "":
		affairs.erase(oldest)


## Intimní chvíle (fade-to-black) mezi `a` a `b`: pokud je kdokoli z nich zadaný s někým třetím,
## je to nevěra (románek se eviduje, i bez předchozí jiskry). Vrací zradu {jméno: partner}.
func note_intimacy(a: String, b: String, ro, now: float) -> Dictionary:
	var bt := betrayals(a, b, ro)
	if String(bt.get(a, "")) == "" and String(bt.get(b, "")) == "":
		return {}
	_note_affair(a, b, ro, now)
	_add_spark(a, b, SPARK_DATE, now)
	stats["intimate"] += 1
	return bt


## S kým má `a` tajný románek, o kterém zrazený `p` ještě neví ("" = s nikým). Nejčerstvější.
func secret_lover(a: String, p: String) -> String:
	var best := ""
	var t := -INF
	var ks: Array = affairs.keys()
	ks.sort()
	for k in ks:
		var af: Dictionary = affairs[k]
		if String((af["betrays"] as Dictionary).get(a, "")) != p or (af["known_by"] as Array).has(p):
			continue
		var names: PackedStringArray = String(k).split("|")
		if names.size() != 2 or not a in names:
			continue
		if float(af["last"]) > t:
			t = float(af["last"])
			best = names[1] if names[0] == a else names[0]
	return best


func affair_dates(a: String, b: String) -> int:
	return int(affairs.get(Romance.key(a, b), {}).get("dates", 0))


## Zrazený `p` se o románku `a` s `lover` dozvěděl (přistižení / přiznání / usvědčení).
func mark_known(p: String, a: String, lover: String, now: float) -> void:
	var af: Dictionary = affairs.get(Romance.key(a, lover), {})
	if not af.is_empty():
		var kb: Array = af["known_by"]
		if not kb.has(p):
			kb.append(p)
			while kb.size() > MAX_KNOWN:
				kb.pop_front()
	# Podezření se mění ve vědění: dál už nežene AI ke konfrontacím (to, co ví, řeší vztah – rozchod,
	# studená válka, odpuštění –, ne další výslechy). Nový románek ale zase podezření založí.
	var s := _susp(p, a, true, now)
	if not s.is_empty():
		s["v"] = 0.0
		s["ev"] = 0.0
		s["t"] = maxf(float(s["t"]), now)
		s["hint"] = lover


# ------------------------------------------------------------------ podezření

func _susp(p: String, a: String, create: bool, now: float) -> Dictionary:
	var k := susp_key(p, a)
	if suspicion.has(k):
		return suspicion[k]
	if not create or p == a or p == "" or a == "":
		return {}
	if suspicion.size() >= MAX_SUSP:
		_gc(now)
		if suspicion.size() >= MAX_SUSP:
			_evict_weakest(suspicion, ">", now)
	var r := {"v": 0.0, "ev": 0.0, "t": now, "hint": "", "last_confront": -1.0e9}
	suspicion[k] = r
	return r


func suspicion_of(p: String, a: String, now: float) -> float:
	var r: Dictionary = suspicion.get(susp_key(p, a), {})
	if r.is_empty():
		return 0.0
	return _decay(float(r["v"]), float(r["t"]), now, SUSP_TAU)


func evidence_of(p: String, a: String, now: float) -> float:
	var r: Dictionary = suspicion.get(susp_key(p, a), {})
	if r.is_empty():
		return 0.0
	return _decay(float(r["ev"]), float(r["t"]), now, EV_TAU)


func hint_of(p: String, a: String) -> String:
	return String(suspicion.get(susp_key(p, a), {}).get("hint", ""))


## `p` si všiml(a) něčeho na `a` (vlastní partner/ka): podezření a důkaz se skládají (ne sčítají
## lineárně – desátý drobný náznak už tolik nepřidá). hint = s kým (může být i mylná).
func notice(p: String, a: String, d_susp: float, d_ev: float, hint: String, now: float) -> float:
	var r := _susp(p, a, true, now)
	if r.is_empty():
		return 0.0
	var v := suspicion_of(p, a, now)
	var ev := evidence_of(p, a, now)
	r["v"] = clampf(1.0 - (1.0 - v) * (1.0 - clampf(d_susp, 0.0, 1.0)), 0.0, 1.0)
	r["ev"] = clampf(1.0 - (1.0 - ev) * (1.0 - clampf(d_ev, 0.0, 1.0)), 0.0, 1.0)
	r["t"] = maxf(float(r["t"]), now)
	if _valid_name(hint) and hint != p and hint != a:
		r["hint"] = hint
	return float(r["v"])


## Drb „zahýbá“ o `a` se donesl k jeho/jejímu partnerovi `p` s vírou belief. trust_pa 0..100 = důvěra
## `p` k `a`: kdo partnerovi hodně věří, drbu dá menší váhu (drb nesmí být levný způsob, jak rozbít
## vztah zvenčí; Grok #551).
func on_rumor(p: String, a: String, belief: float, lover_hint: String, now: float, trust_pa := 50.0) -> float:
	stats["rumor_hints"] += 1
	var b := clampf(belief, 0.0, 1.0) * clampf(1.25 - clampf(trust_pa, 0.0, 100.0) / 100.0, 0.35, 1.0)
	return notice(p, a, SUSP_RUMOR * b, EV_RUMOR * b, lover_hint, now)


## Příjemný kontakt `p` s partnerem `a` (rozhovor, společná chvíle): podezření opadne (×0,9), důkazy ne.
func reassure(p: String, a: String, now: float) -> void:
	var r: Dictionary = suspicion.get(susp_key(p, a), {})
	if r.is_empty():
		return
	r["v"] = suspicion_of(p, a, now) * REASSURE
	r["ev"] = evidence_of(p, a, now)
	r["t"] = maxf(float(r["t"]), now)


# ------------------------------------------------------------------ konfrontace

## Šance na přiznání. honesty 0..1 (HEXACO), guilt 0..1 (vina vůči partnerovi), ev 0..1 (důkazy).
static func confess_p(honesty: float, guilt: float, ev: float) -> float:
	return clampf(0.1 + 0.4 * clampf(honesty, 0.0, 1.0) + 0.25 * clampf(guilt, 0.0, 1.0) + 0.3 * clampf(ev, 0.0, 1.0), 0.05, 0.95)


## Výsledek konfrontace `p` → `a` (partner/ka). Vrací {"outcome", "lover", "dates", "evidence"}.
## outcome: "innocent" (žádný románek – žárlivá scéna bez důvodu), "confess", "caught_lying" (zapírá, ale
## důkazy mluví jasně), "denied" (zapřel(a) a nedá se to dokázat).
func resolve_confront(p: String, a: String, honesty: float, guilt: float, roll: float, now: float) -> Dictionary:
	stats["confrontations"] += 1
	var lover := secret_lover(a, p)
	var ev := evidence_of(p, a, now)
	var r := _susp(p, a, true, now)
	if not r.is_empty():
		r["last_confront"] = now
	var out := {"outcome": "", "lover": lover, "dates": 0, "evidence": ev}
	if lover == "":
		out["outcome"] = "innocent"
		if not r.is_empty():
			r["v"] = suspicion_of(p, a, now) * INNOCENT_DAMP
			r["ev"] = 0.0
			r["t"] = maxf(float(r["t"]), now)
			r["hint"] = ""
	else:
		out["dates"] = affair_dates(a, lover)
		if roll < confess_p(honesty, guilt, ev):
			out["outcome"] = "confess"
		elif ev >= EV_LIE_PROOF:
			out["outcome"] = "caught_lying"
		else:
			out["outcome"] = "denied"
			if not r.is_empty():
				r["v"] = suspicion_of(p, a, now) * DENIED_DAMP
				r["ev"] = evidence_of(p, a, now)
				r["t"] = maxf(float(r["t"]), now)
		if out["outcome"] in ["confess", "caught_lying"]:
			mark_known(p, a, lover, now)
	stats[String(out["outcome"])] += 1
	return out


func confront_block(p: String, a: String, ro, now: float) -> String:
	if p == "" or a == "" or p == a:
		return "self"
	if ro == null or not ro.together(p, a):
		return "not_partners"
	var r: Dictionary = suspicion.get(susp_key(p, a), {})
	if not r.is_empty() and now - float(r["last_confront"]) < 60.0 and float(r["last_confront"]) <= now:
		return "not_now"
	return ""


# ------------------------------------------------------------------ AI

## Pokušení 0..1: nespokojenost ve vztahu, nízká poctivost (HEXACO 0..1), impulzivita (0..1).
## Spokojený a poctivý člověk nezahýbá skoro nikdy – ale „nikdy“ to není ani u něj.
static func temptation(sat_own: float, honesty: float, impulsive: float) -> float:
	return clampf((0.5 - sat_own) * 1.6 + (0.45 - honesty) * 1.2 + 0.35 * clampf(impulsive, 0.0, 1.0), 0.0, 1.0)


func note_ai(a: String, what: String, now: float) -> void:
	if not _last_ai.has(a):
		if _last_ai.size() >= MAX_SPARKS:
			return
		_last_ai[a] = {"flirt": -1.0e12, "date": -1.0e12}
	_last_ai[a][what] = now


func _ai_recent(a: String, what: String, every: float, now: float) -> bool:
	var t := float(_last_ai.get(a, {}).get(what, -1.0e12))
	return now - t < every and t <= now


## AI flirt: jen s tím, koho postava sama přitahuje a o kom ví, že je přitažlivost vzájemná (jako u
## pozvání na rande); zadaná postava jen při pokušení (Infidelity.temptation z profilu postavy).
func ai_flirt_score(sim, other, base: float, ro, now: float) -> float:
	var a := String(sim.sim_name)
	var b := String(other.sim_name)
	if _ai_recent(a, "flirt", AI_FLIRT_EVERY, now):
		return 0.0
	if other.has_method("romance_owned_by_player") and other.romance_owned_by_player():
		return 0.0
	var pa: Dictionary = sim.romance_profile()
	var pb: Dictionary = other.romance_profile()
	if bool(pa.get("aromantic", false)) or not Romance.fits(pb, pa) or not Romance.fits(pa, pb):
		return 0.0  # AI flirtuje jen tam, kde přitažlivost sedí oběma směry (hráč smí cokoli – i trapas)
	var rel: float = float(sim.relationships.get(b, 0.0))
	if ro != null and ro.together(a, b):
		return base * 3.0 * clampf(0.5 + rel / 100.0, 0.2, 1.5)
	if rel < AI_FLIRT_REL or rebuffed(a, b, now):
		return 0.0  # po odbytí AI 3 dny nedotírá
	var close := clampf((rel - AI_FLIRT_REL) / (100.0 - AI_FLIRT_REL), 0.05, 1.0)
	var mine: String = ro.partner_of(a) if ro != null else ""
	if mine == "":
		return base * 2.0 * close
	var tp: Dictionary = sim.infidelity_profile(mine)
	var t := temptation(float(tp.get("sat", 0.55)), float(tp.get("honesty", 0.5)), float(tp.get("impulsive", 0.0)))
	if t < AI_TEMPT_MIN:
		return 0.0
	return base * 2.0 * close * t


func ai_date_score(sim, other, base: float, ro, now: float) -> float:
	var a := String(sim.sim_name)
	var b := String(other.sim_name)
	if date_block(a, b, ro, now) != "" or _ai_recent(a, "date", AI_DATE_EVERY, now):
		return 0.0
	if other.has_method("romance_owned_by_player") and other.romance_owned_by_player():
		return 0.0
	if not Romance.fits(other.romance_profile(), sim.romance_profile()):
		return 0.0
	if float(sim.relationships.get(b, 0.0)) < AI_DATE_REL:
		return 0.0
	var mine: String = ro.partner_of(a) if ro != null else ""
	var t := 0.6  # volný člověk, který jde za zadaným: pokušení je hlavně na druhé straně
	if mine != "":
		var tp: Dictionary = sim.infidelity_profile(mine)
		t = temptation(float(tp.get("sat", 0.55)), float(tp.get("honesty", 0.5)), float(tp.get("impulsive", 0.0)))
		if t < AI_TEMPT_MIN:
			return 0.0
		# Utajení: AI si tajnou schůzku nedá, když je její partner/ka nablízku a vzhůru.
		if sim.has_method("partner_nearby") and sim.partner_nearby(mine, PARTNER_NEAR):
			return 0.0
	var lover_mine: String = ro.partner_of(b) if ro != null else ""
	if lover_mine != "" and other.has_method("partner_nearby") and other.partner_nearby(lover_mine, PARTNER_NEAR):
		return 0.0
	return base * 10.0 * spark(a, b, now) * t


func ai_confront_score(sim, other, base: float, ro, now: float) -> float:
	var p := String(sim.sim_name)
	var a := String(other.sim_name)
	if confront_block(p, a, ro, now) != "":
		return 0.0
	var r: Dictionary = suspicion.get(susp_key(p, a), {})
	if r.is_empty() or now - float(r["last_confront"]) < CONFRONT_GAP and float(r["last_confront"]) <= now:
		return 0.0
	var v := suspicion_of(p, a, now)
	if v < SUSP_CONFRONT:
		return 0.0
	return base * 12.0 * v * (1.0 + 0.5 * float(sim.infidelity_profile(a).get("jealous", 0.0)))


# ------------------------------------------------------------------ údržba a pohledy

## Úklid vyhaslých jisker a podezření (románky zůstávají – historie má následky).
func _gc(now: float) -> void:
	for k in sparks.keys():
		var names: PackedStringArray = String(k).split("|")
		if names.size() != 2 or spark(names[0], names[1], now) < 0.02:
			sparks.erase(k)
	for k in suspicion.keys():
		var names2: PackedStringArray = String(k).split(">")
		if names2.size() != 2:
			suspicion.erase(k)
			continue
		if suspicion_of(names2[0], names2[1], now) < 0.02 and evidence_of(names2[0], names2[1], now) < 0.02:
			suspicion.erase(k)


## Plná tabulka i po úklidu: vyhodí záznam s nejnižší aktuální hodnotou (u podezření v + ev);
## při shodě rozhoduje klíč (deterministicky).
func _evict_weakest(table: Dictionary, sep: String, now: float) -> void:
	var worst := ""
	var worst_v := INF
	var ks: Array = table.keys()
	ks.sort()
	for k in ks:
		var names: PackedStringArray = String(k).split(sep)
		if names.size() != 2:
			worst = k
			break
		var val := spark(names[0], names[1], now) if sep == "|" else suspicion_of(names[0], names[1], now) + evidence_of(names[0], names[1], now)
		if val < worst_v:
			worst_v = val
			worst = k
	if worst != "":
		table.erase(worst)


func tick(now: float) -> void:
	if now - _last_gc >= 1440.0 or now < _last_gc:
		_last_gc = now
		if sparks.size() + suspicion.size() > 0:
			_gc(now)


## Soukromé věty pro vlastníka postavy `a` (HUD; bez čísel; s kým je podezření, se neprozrazuje).
func private_lines(a: String, ro, now: float) -> PackedStringArray:
	var out := PackedStringArray()
	var mine: String = ro.partner_of(a) if ro != null else ""
	if mine != "":
		var lover := secret_lover(a, mine)
		if lover != "":
			out.append("Tajný románek: %s (%s o tom neví)" % [lover.split(" ")[0], mine.split(" ")[0]])
		var v := suspicion_of(a, mine, now)
		# Jména bez skloňování (1. pád za dvojtečkou) – čeština jinak potřebuje tvary, které nemáme.
		if v >= 0.6:
			out.append("Skoro jistě mi něco tají: %s." % mine.split(" ")[0])
		elif v >= SUSP_CONFRONT:
			out.append("Něco mi nesedí: %s." % mine.split(" ")[0])
	return out


func to_dict() -> Dictionary:
	return {"sparks": sparks.duplicate(true), "affairs": affairs.duplicate(true), "suspicion": suspicion.duplicate(true),
		"last_ai": _last_ai.duplicate(true), "rebuffs": rebuffs.duplicate(true), "stats": stats.duplicate(true)}


## Obnova z uložené hry. Cizí/poškozená data se tiše zahodí (nikdy nespadne, nikdy nepřekročí limity).
func from_dict(d) -> void:
	sparks = {}
	affairs = {}
	suspicion = {}
	_last_ai = {}
	rebuffs = {}
	reset_stats()
	if typeof(d) != TYPE_DICTIONARY:
		return
	var sp = d.get("sparks", {})
	if typeof(sp) == TYPE_DICTIONARY:
		var ks: Array = sp.keys()
		ks.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks:
			if sparks.size() >= MAX_SPARKS or typeof(k) != TYPE_STRING:
				continue
			var names: PackedStringArray = String(k).split("|")
			if names.size() != 2 or not _valid_name(names[0]) or not _valid_name(names[1]) or names[0] == names[1]:
				continue
			var r = sp[k]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			sparks[Romance.key(names[0], names[1])] = {"v": _fin(r.get("v"), 0.0, 1.0, 0.0),
				"t": _fin(r.get("t"), -1.0e9, 1.0e12, 0.0), "last_flirt": _fin(r.get("last_flirt"), -1.0e9, 1.0e12, -1.0e9)}
	var af = d.get("affairs", {})
	if typeof(af) == TYPE_DICTIONARY:
		var ks2: Array = af.keys()
		ks2.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks2:
			if affairs.size() >= MAX_AFFAIRS or typeof(k) != TYPE_STRING:
				continue
			var names: PackedStringArray = String(k).split("|")
			if names.size() != 2 or not _valid_name(names[0]) or not _valid_name(names[1]) or names[0] == names[1]:
				continue
			var r = af[k]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var betrays := {}
			if typeof(r.get("betrays")) == TYPE_DICTIONARY:
				for who in names:
					var pv = r["betrays"].get(who)
					if _valid_name(pv) and not String(pv) in names:
						betrays[who] = String(pv)
			if betrays.is_empty():
				continue  # románek bez zrady není nevěra – nemá co dělat v uložení
			var known: Array = []
			if typeof(r.get("known_by")) == TYPE_ARRAY:
				for n in r["known_by"]:
					if known.size() < MAX_KNOWN and _valid_name(n) and not known.has(String(n)):
						known.append(String(n))
			var since := _fin(r.get("since"), -1.0e9, 1.0e12, 0.0)
			affairs[Romance.key(names[0], names[1])] = {"since": since,
				"last": maxf(since, _fin(r.get("last"), -1.0e9, 1.0e12, since)),
				"dates": int(_fin(r.get("dates"), 0.0, 100000.0, 1.0)), "betrays": betrays, "known_by": known}
	var su = d.get("suspicion", {})
	if typeof(su) == TYPE_DICTIONARY:
		var ks3: Array = su.keys()
		ks3.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks3:
			if suspicion.size() >= MAX_SUSP or typeof(k) != TYPE_STRING:
				continue
			var names: PackedStringArray = String(k).split(">")
			if names.size() != 2 or not _valid_name(names[0]) or not _valid_name(names[1]) or names[0] == names[1]:
				continue
			var r = su[k]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var hint := String(r.get("hint", "")) if typeof(r.get("hint")) == TYPE_STRING else ""
			if hint != "" and (not _valid_name(hint) or hint in names):
				hint = ""
			suspicion[k] = {"v": _fin(r.get("v"), 0.0, 1.0, 0.0), "ev": _fin(r.get("ev"), 0.0, 1.0, 0.0),
				"t": _fin(r.get("t"), -1.0e9, 1.0e12, 0.0), "hint": hint,
				"last_confront": _fin(r.get("last_confront"), -1.0e9, 1.0e12, -1.0e9)}
	var la = d.get("last_ai", {})
	if typeof(la) == TYPE_DICTIONARY:
		for n in la:
			if _last_ai.size() >= MAX_SPARKS or not _valid_name(n) or typeof(la[n]) != TYPE_DICTIONARY:
				continue
			_last_ai[n] = {"flirt": _fin(la[n].get("flirt"), -1.0e12, 1.0e12, -1.0e12),
				"date": _fin(la[n].get("date"), -1.0e12, 1.0e12, -1.0e12)}
	var rb = d.get("rebuffs", {})
	if typeof(rb) == TYPE_DICTIONARY:
		var ks4: Array = rb.keys()
		ks4.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks4:
			if rebuffs.size() >= MAX_SPARKS or typeof(k) != TYPE_STRING:
				continue
			var nm: PackedStringArray = String(k).split(">")
			if nm.size() != 2 or not _valid_name(nm[0]) or not _valid_name(nm[1]) or nm[0] == nm[1]:
				continue
			var tv := _fin(rb[k], -1.0e12, 1.0e12, NAN)
			if is_finite(tv):
				rebuffs[k] = tv
	var st = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in stats:
			if st.has(k):
				stats[k] = int(_fin(st[k], 0.0, 1.0e9, 0.0))
