extends RefCounted
## Duševní stav postavy – stres, úzkost, panické ataky, copingy a rušivé myšlenky.
##
## Úzkost NENÍ jedno číslo „debuffu“, ale souhra tří složek:
##   threat      – vnímaná hrozba / nejistota v situaci (rychle vzniká i mizí, zkresluje ji povaha)
##   arousal     – tělesná aktivace (srdce, dech, napětí): stoupá rychle, klesá pomalu
##   sensitivity – citlivost na spouštěče (pomalá, týdny): roste vyhýbáním a chronickým stresem,
##                 klesá zkušeností („zvládl/a jsem to“) a oporou blízkých
## a dvou zdrojů zvládání:
##   regulation  – momentální kapacita se regulovat (únava, hlad, alkohol ji snižují)
##   support     – nedávná opora od blízkých (mizí během hodin)
##   mastery     – pocit, že situace jsou zvládnutelné (dlouhodobý)
##
## Diagnóza je PREDISPOZICE se závažností (conditions), ne nálepka ani šablona povahy.
## Stav kolísá (dobré a špatné dny), má spouštěče, epizody i relapsy a nikdy není „vyléčený
## na 100 %“ ani beznadějný: citlivost jde vždy snížit a zvládnutelnost zvýšit.
##
## Copingy mají kompromisy (žádný není nejlepší ve všem) a účinek klesá s opakováním v krátkém
## okně (anti-farming); po delší pauze se obnoví. Nic se nedá „grindovat“.
##
## Deprese a skleslost žijí v podmodulu `dep` (depression.gd): zátěž, naučené očekávání
## (wanting), prožitá radost (liking), energie začít (vigour) a učení z rozdílu očekávání.
##
## Modul je čistý (bez uzlů): sim_agent mu předává kontext a čte výsledky. Běží jen tam,
## kde je autorita (offline / server). Nastavení obsahu dostává jako slovník `cfg`.

const Grammar := preload("res://scripts/core/grammar_cs.gd")
const Depression := preload("res://scripts/sim/depression.gd")

const PsycheModel := preload("res://scripts/psyche/psyche_model.gd")

## Diagnózy (predispozice) – od běhu 20 DATA v res://data/conditions/<id>.json (PsycheModel). Tady jen
## pohled na blok „legacy“ (čísla dnešní mechaniky: sensitivity, threat_bias, social, panic, dep) + popisky,
## aby zbytek kódu (MentalState.CONDITIONS[id]["…"]) zůstal beze změny. Neplatný profil se nenačte (push_error).
static var CONDITIONS: Dictionary = _load_conditions()


static func _load_conditions() -> Dictionary:
	var out := {}
	var profs: Dictionary = PsycheModel.profiles()
	for id in profs:
		var p: Dictionary = profs[id]
		if typeof(p.get("legacy")) != TYPE_DICTIONARY:
			continue   # profil bez dnešní mechaniky (další osy) působí jen přes PsycheModel
		var e: Dictionary = (p["legacy"] as Dictionary).duplicate()
		e["label"] = String(p.get("label_cs", id))
		e["desc"] = String(p.get("desc_cs", ""))
		out[id] = e
	return out


## Copingy: krátkodobá úleva × dlouhodobý dopad × cena. Čísla jsou plné účinky
## (násobí se habituací, regulací a kontextem). Klíče:
##   arousal / stress – okamžitá změna; sens / mastery – dlouhodobá změna
##   peak_eff – účinnost při velmi vysoké aktivaci (>70); daily – plný účinek jen 1× za den
const COPINGS := {
	"breathe": {"label": "Dechové cvičení", "arousal": -18.0, "stress": -4.0, "sens": 0.0, "mastery": 0.008,
		"peak_eff": 0.55, "healthy": true},
	"walk": {"label": "Procházka", "arousal": -14.0, "stress": -12.0, "sens": -0.004, "mastery": 0.004,
		"peak_eff": 0.8, "healthy": true},
	"journal": {"label": "Psaní deníku", "arousal": -6.0, "stress": -9.0, "sens": -0.008, "mastery": 0.01,
		"peak_eff": 0.35, "healthy": true, "daily": true},
	"confide": {"label": "Svěřit se", "arousal": -20.0, "stress": -15.0, "sens": -0.006, "mastery": 0.006,
		"peak_eff": 0.9, "healthy": true, "support": 0.4},
	"doomscroll": {"label": "Doomscrolling", "arousal": -9.0, "stress": 2.0, "sens": 0.004, "mastery": -0.004,
		"peak_eff": 0.7, "healthy": false},
	"hide": {"label": "Schovat se pod peřinu", "arousal": -26.0, "stress": -6.0, "sens": 0.012, "mastery": -0.03,
		"peak_eff": 1.0, "healthy": false},
	"drink": {"label": "Pivo na nervy", "arousal": -22.0, "stress": -7.0, "sens": 0.003, "mastery": -0.01,
		"peak_eff": 1.0, "healthy": false, "alcohol": 0.25},
}

const HABITUATION_WINDOW := 360.0  # minuty
const HABITUATION_K := 0.65
const PANIC_THRESHOLD := 78.0
const PANIC_END := 55.0
const PANIC_MIN_MINUTES := 5.0
const PANIC_MAX_MINUTES := 25.0
const PANIC_COOLDOWN := 360.0
## Opakované ataky: každá ataka za posledních ~3 dny prodlouží refrakterní dobu (6 h → nejvýš 24 h);
## tělo po sérii atak „nemá z čeho brát“ – zůstává vyčerpané a otupělé, ne v nekonečné smyčce.
const PANIC_RECENT_WINDOW := 4320.0
const PANIC_COOLDOWN_STEP := 0.75
const PANIC_COOLDOWN_MAX := 1440.0
## Vyčerpání po atace: snížený cíl aktivace na pár hodin.
const PANIC_EXHAUST_MINUTES := 180.0
const PANIC_EXHAUST_AROUSAL := 15.0
## Měkký strop stresu: nad STRESS_SOFT se další stres přidává jen částečně (člověk „otupí“).
const STRESS_SOFT := 70.0
## Spontánní vlny úzkosti za den při závažnosti 1.0 (škáluje se kvadraticky se závažností).
const SURGE_PER_DAY := 0.18
## Váha neuspokojených potřeb ve stresu.
## Váha neuspokojených potřeb ve spánku (násobí UNMET_WEIGHT): tělo ano, sociální a ostatní ne.
const SLEEP_UNMET := {"hunger": 0.5, "energy": 0.0}
const UNMET_WEIGHT := {"hunger": 1.0, "energy": 1.0, "hygiene": 0.4, "fun": 0.4, "social": 0.5, "comfort": 0.4}
## Alkohol: každá další dávka v jednom dni uleví méně a láká méně (kocovina a „už mi to nepomáhá“).
const DRINK_DAY_RELIEF_K := 0.5
const DRINK_DAY_APPEAL_K := 1.2
## Okno, ve kterém se dávky sčítají („dnes už toho bylo dost“) – ~16 h.
const DRINK_WINDOW := 960.0
const MAX_THOUGHTS := 6

## Rušivé myšlenky podle kontextu. Vždy subjektivní interpretace (UI je označí „myšlenka, ne fakt“).
## {g} = rodová koncovka (a/""), {name} = jméno osoby z kontextu.
const THOUGHTS := {
	"social": [
		"Všichni si všimli, jak divně mluvím.",
		"Určitě si o mně myslí, že jsem trapn{y}.",
		"Proč jsem tam vůbec chodil{g}?",
		"Nesnášejí mě, jen to neříkají nahlas.",
	],
	"after_chat": [
		"Asi jsem řekl{g} něco hloupého.",
		"{name} se tvářil{ng} divně. Zlobí se na mě?",
		"Mluvil{g} jsem moc. Zase.",
	],
	"body": [
		"Srdce mi buší. Co když je to něco vážného?",
		"Nemůžu se pořádně nadechnout.",
		"Musím odsud pryč. Hned.",
	],
	"future": [
		"Co když se to celé pokazí?",
		"Nezvládnu to. Nikdy jsem nic nezvládl{g}.",
		"Zítra to bude ještě horší.",
	],
	"conflict": [
		"Měl{g} jsem mlčet.",
		"Teď mě nenávidí. Všechno jsem zkazil{g}.",
		"Proč se vždycky všechno posere zrovna mně?",
	],
	"night": [
		"Proč si pořád přehrávám, co jsem dneska řekl{g}?",
		"Už zase nemůžu usnout. Zítra budu troska.",
	],
	"stigma": [
		"Možná mají pravdu a jen dělám scény.",
		"Příště radši nic neřeknu.",
	],
	# Deprese: vyhaslost, sebekritika, beznaděj ohledně dne – nikdy sebevražedné obsahy.
	"low": [
		"Proč bych vstával{a}? Stejně se nic nezmění.",
		"Dřív mě to bavilo. Kam se to všechno podělo?",
		"Všichni to nějak zvládaj. Jen já ne.",
		"Zase jsem dneska nic neudělal{a}.",
		"Nemám sílu ani na to, abych se zvedl{a}.",
		"Je to jedno. Všechno je to jedno.",
	],
	"low_morning": [
		"Další den. Zase.",
		"Ještě pět minut. Ještě hodinu. Ještě…",
	],
	"mild": [
		"Něco mi nesedí, nevím co.",
		"Jsem nějak mimo a nevím proč.",
	],
}

var stress := 15.0
var arousal := 10.0
var threat := 0.0
var sensitivity := 0.15
var mastery := 0.5
var support := 0.0
var conditions := {}  # id -> závažnost 0..1
var trait_vuln := 0.0  # zranitelnost z temperamentu (Úzkostlivý)
var day_factor := 0.0  # -1 (špatný den) .. 1 (dobrý den)
var alcohol := 0.0
var tolerance := 0.0
var rebound := 0.0

var panic_active := false
var panic_elapsed := 0.0
var panic_cooldown := 0.0
var panic_count := 0
var panic_times: Array = []  # časy začátků atak (posledních pár dní)
var panic_exhaust := 0.0
var drink_times: Array = []  # časy posledních dávek (klouzavé okno DRINK_WINDOW)
var surge_count := 0
var _now := 0.0
var coping_log := {}   # id -> Array[float] časů použití
var coping_counts := {}
var last_daily := {}   # id -> den posledního plného účinku
var thoughts: Array = []  # [{"t": minuty, "text": String, "kind": String}]
var female := false
## Gramatický rod postavy (tvary sloves v myšlenkách).
var grammar := "m"
var rng: RandomNumberGenerator
var _thought_cd := 0.0
## Deprese a skleslost (wanting / liking / vigour / zátěž).
var dep
## Vliv povahy na zranitelnost depresí (Traits „dep_vuln“, může být záporný = ochranný).
var trait_dep := 0.0
var _hour := 12
## Háčky PsycheModel pro režimy obsahu {"full"|"muted"|"off": {...}} – jen reziduum individuality (viz
## psyche_model.gd); bez CharacterData neutrální (staré chování beze změny).
var psy_hooks := {}
var _couple_acc := 0.0


func _init(p_rng: RandomNumberGenerator = null, p_grammar: Variant = false) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	grammar = Grammar.norm(p_grammar) if typeof(p_grammar) == TYPE_STRING else ("f" if bool(p_grammar) else "m")
	female = grammar == "f"
	dep = Depression.new()


## Zranitelnost depresí 0..1 (predispozice, komorbidní úzkost, temperament).
func dep_vulnerability(cfg: Dictionary = {}) -> float:
	return clampf(_cond_param("dep", cfg) + trait_vuln * 0.5 + trait_dep, 0.0, 1.0)


## Nastaví háčky psychiky (PsycheModel.hooks_by_mode); {} = neutrální.
func set_psyche(by_mode: Dictionary) -> void:
	psy_hooks = by_mode.duplicate(true) if typeof(by_mode) == TYPE_DICTIONARY else {}


## Režim obsahu z cfg: conditions=false → off, episodes=false → muted, jinak full (cfg["mode"] má přednost).
static func cfg_mode(cfg: Dictionary) -> String:
	if cfg.has("mode"):
		return String(cfg["mode"])
	if not bool(cfg.get("conditions", true)):
		return "off"
	return "full" if bool(cfg.get("episodes", true)) else "muted"


func _hk(key: String, cfg: Dictionary, def: Variant) -> Variant:
	if psy_hooks.is_empty():
		return def
	var h: Dictionary = psy_hooks.get(cfg_mode(cfg), psy_hooks.get("full", {}))
	return h.get(key, def)


# ---------------------------------------------------------------- zranitelnost

## Celková zranitelnost 0..1 (diagnózy × závažnost + temperament). cfg["conditions"]=false ji vypne.
func vulnerability(cfg: Dictionary = {}) -> float:
	var v := trait_vuln
	if bool(cfg.get("conditions", true)):
		for id in conditions:
			v += float(conditions[id]) * float(CONDITIONS.get(id, {}).get("sensitivity", 0.0)) * 1.6
	return clampf(v, 0.0, 1.0)


func _cond_param(key: String, cfg: Dictionary) -> float:
	if not bool(cfg.get("conditions", true)):
		return 0.0
	var s := 0.0
	for id in conditions:
		s += float(conditions[id]) * float(CONDITIONS.get(id, {}).get(key, 0.0))
	return s


func can_panic(cfg: Dictionary = {}) -> bool:
	if not bool(cfg.get("episodes", true)) or not bool(cfg.get("conditions", true)):
		return false
	for id in conditions:
		if bool(CONDITIONS.get(id, {}).get("panic", false)) and float(conditions[id]) > 0.15:
			return true
	return false


## Výchozí citlivost, ke které se stav pomalu vrací (nikdy 0 – zranitelnost nezmizí,
## ale ani nezamyká: zkušenost a opora ji drží níž).
func baseline_sensitivity(cfg: Dictionary = {}) -> float:
	return 0.08 + 0.45 * vulnerability(cfg)


## Efektivní citlivost – zhoršená špatným dnem a únavou.
func effective_sensitivity(cfg: Dictionary = {}) -> float:
	var s := sensitivity
	if not bool(cfg.get("conditions", true)):
		s = minf(s, 0.2)
	s += maxf(-day_factor, 0.0) * 0.12
	return clampf(s, 0.0, 1.0)


func regulation(energy: float, hunger: float) -> float:
	var r := 0.25 + 0.45 * energy / 100.0 + 0.3 * hunger / 100.0
	r *= 1.0 - alcohol * 0.35
	return clampf(r, 0.1, 1.0)


# ---------------------------------------------------------------- krok simulace

## ctx: energy, hunger, needs (Dictionary), sleeping, night, now (min), cfg (Dictionary)
func tick(dm: float, ctx: Dictionary) -> void:
	var cfg: Dictionary = ctx.get("cfg", {})
	var energy: float = float(ctx.get("energy", 70.0))
	var hunger: float = float(ctx.get("hunger", 70.0))
	var sleeping: bool = bool(ctx.get("sleeping", false))
	var reg := regulation(energy, hunger)
	var s_eff := effective_sensitivity(cfg)
	_hour = int(ctx.get("hour", 12))
	_now = float(ctx.get("now", _now))
	panic_exhaust = maxf(panic_exhaust - dm, 0.0)

	# Vnímaná hrozba rychle odeznívá (když se nic neděje, situace se „uklidní“).
	threat *= exp(-dm / 25.0)

	# Stres: neuspokojené potřeby přidávají, klid a spánek ubírají.
	var unmet := 0.0
	var nd: Dictionary = ctx.get("needs", {})
	for k in nd:
		var v: float = float(nd[k])
		if v < 25.0:
			# Tělo (hlad, únava) stresuje naplno; zanedbaná hygiena, nuda nebo samota méně.
			var wgt := float(UNMET_WEIGHT.get(String(k), 0.5))
			if sleeping:
				# Ve spánku samota, nuda ani hygiena nestresují; hlad jen napůl (běh 23: osamělá postava v depresi
				# jinak přes noc nabírala ~17 bodů stresu „ze samoty“ a nikdy se nedostala z vysokého stresu).
				wgt *= float(SLEEP_UNMET.get(String(k), 0.0))
			unmet += (25.0 - v) / 25.0 * wgt
	if unmet > 0.0:
		var add := unmet * 0.045 * dm * stress_gain_factor()
		stress += add
		stress_sources["needs"] = float(stress_sources.get("needs", 0.0)) + add
	var calm := 0.012 if not sleeping else 0.07
	calm *= reg * (1.0 + support)
	stress -= calm * dm * (0.5 + stress / 100.0)
	stress = clampf(stress, 0.0, 100.0)

	# Tělesná aktivace směřuje k cíli: rychle nahoru, pomalu dolů.
	var target := 8.0 + stress * 0.3 + threat * 75.0 * (0.4 + s_eff) + rebound * 30.0
	target -= support * 18.0
	target -= (reg - 0.5) * 10.0
	if sleeping:
		target *= 0.6
	if panic_exhaust > 0.0:
		target -= PANIC_EXHAUST_AROUSAL * panic_exhaust / PANIC_EXHAUST_MINUTES
	target = clampf(target, 0.0, 100.0)
	var tau := 6.0 if target > arousal else (40.0 / (0.6 + reg)) * float(_hk("arousal_decay_tau", cfg, 1.0))
	if panic_active:
		tau = 20.0 / (0.6 + reg + support)  # ataka sama odezní (typicky 5–15 min, ne hodiny)
		if bool(ctx.get("grounding", false)):
			tau *= 0.6  # dýchání, svěření nebo někdo vedle zkrátí ataku (ne vždy, ne hned)
	arousal += (target - arousal) * (1.0 - exp(-dm / tau))
	arousal = clampf(arousal, 0.0, 100.0)

	# Pomalé složky.
	var base := baseline_sensitivity(cfg)
	sensitivity += (base - sensitivity) * (1.0 - exp(-dm / 4320.0))  # ~3 dny
	if stress > 60.0:
		sensitivity += 0.000012 * (stress - 60.0) * dm  # chronický stres „rozkurážuje“ spouštěče
	sensitivity = clampf(sensitivity, 0.02, 1.0)
	mastery += (0.5 - mastery) * (1.0 - exp(-dm / 10080.0))  # ~týden
	mastery = clampf(mastery, 0.0, 1.0)
	support *= exp(-dm / 360.0)

	# Alkohol se odbourává; odbourané se mění v „rebound“ (ranní úzkost po pití).
	if alcohol > 0.0:
		var burn := minf(alcohol, 0.0018 * dm)
		alcohol -= burn
		rebound = clampf(rebound + burn * (1.0 + tolerance), 0.0, 1.0)
	rebound *= exp(-dm / 900.0)  # „hangxiety“ druhý den ráno
	tolerance *= exp(-dm / 20160.0)  # tolerance mizí pomalu (~2 týdny)

	# Deprese / skleslost (pomalá dynamika, vlastní modul).
	dep.vuln = dep_vulnerability(cfg)
	dep.tick(dm, {"stress": stress, "social": float(nd.get("social", 70.0)), "energy": energy,
		"support": support, "sleeping": sleeping, "night": bool(ctx.get("night", false)), "hour": _hour,
		"now": float(ctx.get("now", 0.0)), "cfg": cfg})

	# Úzkostná porucha: občasná vlna úzkosti „z čista jasna“ (bez vnějšího spouštěče) – u těžké predispozice
	# pár za měsíc. Ne každá vlna skončí atakou; zvládnutelnost a opora ji tlumí.
	var anx := float(conditions.get("anxiety", 0.0)) if bool(cfg.get("conditions", true)) else 0.0
	if anx > 0.0 and not sleeping:
		var lam_s := anx * anx * SURGE_PER_DAY / 1440.0 * (1.2 - mastery * 0.6)
		if rng.randf() < 1.0 - exp(-lam_s * dm):
			threat = clampf(threat + rng.randf_range(0.3, 0.6), 0.0, 1.0)
			arousal = clampf(maxf(arousal, 50.0 + 32.0 * anx * rng.randf_range(0.6, 1.25)), 0.0, 100.0)
			surge_count += 1
			# Vlna může přerůst v ataku – pravděpodobnost podle závažnosti, zvládnutelnosti a citlivosti.
			var p_att := anx * (0.25 + 0.5 * (1.0 - mastery)) * (0.5 + s_eff)
			if not panic_active and panic_cooldown <= 0.0 and can_panic(cfg) and rng.randf() < p_att:
				_start_panic()

	# Panická ataka.
	panic_cooldown = maxf(panic_cooldown - dm, 0.0)
	if panic_active:
		panic_elapsed += dm
		if (panic_elapsed >= PANIC_MIN_MINUTES and arousal < PANIC_END) or panic_elapsed >= PANIC_MAX_MINUTES:
			end_panic()
	elif arousal >= PANIC_THRESHOLD + float(_hk("panic_shift", cfg, 0.0)) and panic_cooldown <= 0.0 and not sleeping and can_panic(cfg):
		# Hazard nezávislý na délce kroku: p = 1 − e^(−λ·dm).
		var lam := 0.035 * s_eff * (arousal - PANIC_THRESHOLD - float(_hk("panic_shift", cfg, 0.0)) + 4.0) / 10.0
		if rng.randf() < 1.0 - exp(-lam * dm):
			_start_panic()

	# Vazby profilů (couple) – jednou za herní hodinu v pevném topologickém pořadí (nemůže oscilovat).
	var couples: Array = _hk("couples", cfg, [])
	if not couples.is_empty():
		_couple_acc += dm
		while _couple_acc >= 60.0:
			_couple_acc -= 60.0
			var st := PsycheModel.couple_step(couples, {"S.stress": stress / 100.0, "S.arousal": arousal / 100.0,
				"S.threat": threat, "S.burden": dep.burden}, _hk("D", cfg, {}), 1.0)
			stress = float(st["S.stress"]) * 100.0
			arousal = float(st["S.arousal"]) * 100.0
			threat = float(st["S.threat"])
			dep.burden = float(st["S.burden"])

	# Rušivé myšlenky.
	_thought_cd -= dm
	var rate: float = float(cfg.get("thought_rate", 1.0))
	if rate > 0.0 and _thought_cd <= 0.0:
		var level := maxf(arousal - 35.0, 0.0) / 65.0 + maxf(stress - 55.0, 0.0) / 90.0
		var dlev: float = dep.thought_level()
		if level + dlev > 0.0 and rng.randf() < 1.0 - exp(-(level + dlev) * 0.05 * rate * dm):
			var kind := "body" if arousal > 65.0 else ("night" if bool(ctx.get("night", false)) else "future")
			if dlev > level and arousal <= 65.0:
				kind = "low_morning" if dep.morning_drag(_hour) > 0.05 else "low"
			if not bool(cfg.get("episodes", true)):
				kind = "mild"
			add_thought(kind, float(ctx.get("now", 0.0)), {}, cfg)


func new_day() -> void:
	# Dobré a špatné dny: náhodná procházka s návratem ke středu.
	day_factor = clampf(day_factor * 0.45 + rng.randf_range(-0.6, 0.6), -1.0, 1.0)
	dep.new_day(rng)


# ---------------------------------------------------------------- události

## Stresor: kind = argue / insulted / insult / stigma / jealousy / crowd / witness_conflict
## Kolik z přírůstku stresu se opravdu projeví (měkký strop nad STRESS_SOFT).
## Kolik dávek alkoholu za posledních ~16 h.
func recent_drinks(now: float) -> int:
	var n := 0
	for t in drink_times:
		if now - float(t) < DRINK_WINDOW and now >= float(t):
			n += 1
	return n


## Odkud stres přitekl (kumulativně, zdroj → body): „needs“, „crowd“, „argue“… Pro vysvětlení v UI („co mě
## stresuje“) a diagnostiku zátěžových testů; čte se a nuluje zvenku (take_stress_sources). Neukládá se.
var stress_sources := {}


func take_stress_sources() -> Dictionary:
	var d := stress_sources
	stress_sources = {}
	return d


func stress_gain_factor() -> float:
	if stress <= STRESS_SOFT:
		return 1.0
	return clampf((100.0 - stress) / (100.0 - STRESS_SOFT), 0.15, 1.0)


func on_stressor(kind: String, amount: float, cfg: Dictionary = {}) -> void:
	var bias := 1.0 + _cond_param("threat_bias", cfg) + trait_vuln * 0.6
	var social := _cond_param("social", cfg)
	var before := stress
	stress = clampf(stress + amount * (stress_gain_factor() if amount > 0.0 else 1.0), 0.0, 100.0)
	if stress > before:
		stress_sources[kind] = float(stress_sources.get(kind, 0.0)) + stress - before
	var th := amount / 40.0 * bias * float(_hk("threat_gain", cfg, 1.0))
	if kind == "crowd":
		th = amount / 40.0 * (0.3 + social * 1.5 + trait_vuln) * float(_hk("crowd_gain", cfg, 1.0))
	threat = clampf(threat + th, 0.0, 1.0)


## Výsledek dokončeného hovoru. arousal_start = aktivace na začátku (expozice).
## Vrací text myšlenky, pokud vznikla úzkostná interpretace, jinak "".
func on_social_completed(positive: bool, arousal_start: float, partner_name: String, partner_g: Variant,
		now: float, cfg: Dictionary = {}) -> String:
	var out := ""
	# Expozice: zůstat v situaci, která je nepříjemná, je zkušenost – ne garantovaná odměna.
	if arousal_start > 45.0:
		if positive:
			mastery = clampf(mastery + 0.04, 0.0, 1.0)
			sensitivity = clampf(sensitivity - 0.012 * (1.0 + support), 0.02, 1.0)
		else:
			mastery = clampf(mastery + 0.01, 0.0, 1.0)  # „zvládl/a jsem to, i když to nebylo hezké“
			sensitivity = clampf(sensitivity + 0.004, 0.02, 1.0)
	if positive:
		dep.on_connection(1.0, now)
	else:
		dep.on_event(0.01, cfg)
	# Úzkostná interpretace i po dobrém hovoru (subjektivní, ne pravda).
	var bias := _cond_param("threat_bias", cfg) + trait_vuln * 0.5
	if positive and bias > 0.1 and rng.randf() < clampf(bias * (0.25 + arousal / 150.0), 0.0, 0.8):
		threat = clampf(threat + 0.12, 0.0, 1.0)
		out = add_thought("after_chat", now, {"name": partner_name, "grammar": Grammar.norm(partner_g) if typeof(partner_g) == TYPE_STRING else ("f" if bool(partner_g) else "m")}, cfg)
	elif not positive:
		out = add_thought("conflict", now, {}, cfg)
	return out


## Habituační faktor: kolik účinku zbývá při opakovaném použití v krátkém okně.
func habituation(id: String, now: float) -> float:
	var log: Array = coping_log.get(id, [])
	var n := 0
	for t in log:
		if now - float(t) < HABITUATION_WINDOW:
			n += 1
	return 1.0 / (1.0 + n * HABITUATION_K)


## Použije coping. fraction = jaká část akce proběhla (0..1). ctx: now, energy, hunger, day,
## rel (vztah k partnerovi pro confide, -100..100), dismissed (partner odbyl), cfg.
## Vrací slovník skutečných změn (pro testy a UI).
func apply_coping(id: String, fraction: float, ctx: Dictionary) -> Dictionary:
	var def: Dictionary = COPINGS.get(id, {})
	if def.is_empty():
		return {}
	var now: float = float(ctx.get("now", 0.0))
	var f := clampf(fraction, 0.0, 1.0) * habituation(id, now)
	f *= 0.6 + 0.4 * regulation(float(ctx.get("energy", 70.0)), float(ctx.get("hunger", 70.0)))
	if arousal > 70.0:
		f *= float(def.get("peak_eff", 1.0))
	var long_f := f
	if bool(def.get("daily", false)):
		var day: int = int(ctx.get("day", 0))
		if int(last_daily.get(id, -1)) == day:
			long_f *= 0.15  # deník podruhé za den už skoro nic nepřidá
		else:
			last_daily[id] = day
	var res := {"arousal": 0.0, "stress": 0.0, "sens": 0.0, "mastery": 0.0, "support": 0.0}
	var d_ar: float = float(def["arousal"]) * f
	var d_st: float = float(def["stress"]) * f
	var d_se: float = float(def["sens"]) * long_f
	var d_ma: float = float(def["mastery"]) * long_f
	if id == "confide":
		var rel: float = float(ctx.get("rel", 0.0))
		var trust := clampf(0.35 + rel / 100.0, 0.1, 1.2)
		var frac := clampf(fraction, 0.0, 1.0)
		if bool(ctx.get("dismissed", false)):
			# Odbytí / stigma: místo úlevy stud a větší nejistota – úměrně tomu, kolik rozhovoru proběhlo
			# (samotné odmítnutí už zachytil moodlet a vztah při začátku rozhovoru).
			d_ar = 6.0 * frac
			d_st = 8.0 * frac
			d_se = 0.006 * frac
			d_ma = -0.02 * frac
			threat = clampf(threat + 0.2 * frac, 0.0, 1.0)
			dep.on_event(0.02 * frac, ctx.get("cfg", {}))
		else:
			d_ar *= trust
			d_st *= trust
			# Opora také podléhá habituaci – opakované svěřování ji nefarmí.
			var sup: float = float(def.get("support", 0.0)) * trust * frac * habituation(id, now)
			support = clampf(support + sup, 0.0, 1.0)
			res["support"] = sup
			dep.on_connection(clampf(trust, 0.0, 1.0) * frac, now)
	# Vyhýbání a doomscrolling krátce uleví, ale roztáčí ruminaci (deprese).
	if id == "hide" or id == "doomscroll":
		dep.on_rumination((1.0 if id == "hide" else 0.5) * clampf(fraction, 0.0, 1.0))
	if id == "drink":
		# Tolerance: čím častěji, tím menší úleva; alkohol se počítá vždy celý.
		var recent := recent_drinks(now)
		var day_k := 1.0 / (1.0 + DRINK_DAY_RELIEF_K * recent)
		d_ar *= (1.0 - tolerance * 0.7) * day_k
		d_st *= (1.0 - tolerance * 0.7) * day_k
		# Do okna se počítá i nedopitá dávka (Gemini, běh 23: opakované přerušení pod 0,3 by obcházelo limit).
		if fraction > 0.1:
			drink_times.append(now)
			while drink_times.size() > 12:
				drink_times.pop_front()
		alcohol = clampf(alcohol + float(def["alcohol"]) * clampf(fraction, 0.0, 1.0), 0.0, 1.0)
		tolerance = clampf(tolerance + 0.04 * clampf(fraction, 0.0, 1.0), 0.0, 1.0)
	arousal = clampf(arousal + d_ar, 0.0, 100.0)
	stress = clampf(stress + d_st, 0.0, 100.0)
	sensitivity = clampf(sensitivity + d_se, 0.02, 1.0)
	mastery = clampf(mastery + d_ma, 0.0, 1.0)
	res["arousal"] = d_ar
	res["stress"] = d_st
	res["sens"] = d_se
	res["mastery"] = d_ma
	if fraction > 0.3:
		var log: Array = coping_log.get(id, [])
		log.append(now)
		while log.size() > 8:
			log.pop_front()
		coping_log[id] = log
		coping_counts[id] = int(coping_counts.get(id, 0)) + 1
	return res


## Podpora od jiné postavy během ataky / krize (helper_rel = vztah pomáhajícího k postavě).
func receive_support(helper_rel: float, accept_mult := 1.0, now := -1.0e9) -> void:
	var k := clampf(0.4 + helper_rel / 120.0, 0.15, 1.0) * accept_mult
	dep.on_connection(0.6 * k, now)
	support = clampf(support + 0.3 * k, 0.0, 1.0)
	arousal = clampf(arousal - 10.0 * k, 0.0, 100.0)
	threat = clampf(threat - 0.2 * k, 0.0, 1.0)


func _start_panic() -> void:
	panic_active = true
	panic_elapsed = 0.0
	panic_count += 1
	panic_times.append(_now)
	while panic_times.size() > 12:
		panic_times.pop_front()
	arousal = maxf(arousal, 92.0)


func end_panic() -> void:
	if not panic_active:
		return
	panic_active = false
	var recent := 0
	for t in panic_times:
		if _now - float(t) < PANIC_RECENT_WINDOW:
			recent += 1
	panic_cooldown = minf(PANIC_COOLDOWN * (1.0 + PANIC_COOLDOWN_STEP * maxf(recent - 1, 0)), PANIC_COOLDOWN_MAX)
	panic_exhaust = PANIC_EXHAUST_MINUTES
	# Po atace zůstává vyčerpání a strach z další ataky (malý nárůst citlivosti).
	sensitivity = clampf(sensitivity + 0.01, 0.02, 1.0)
	stress = clampf(stress + 6.0, 0.0, 100.0)


# ---------------------------------------------------------------- myšlenky

func add_thought(kind: String, now: float, ctx: Dictionary = {}, cfg: Dictionary = {}) -> String:
	if float(cfg.get("thought_rate", 1.0)) <= 0.0:
		return ""
	var pool: Array = THOUGHTS.get(kind, THOUGHTS["mild"])
	var text: String = pool[rng.randi_range(0, pool.size() - 1)]
	text = Grammar.form(text, grammar)
	text = text.replace("{name}", String(ctx.get("name", "Někdo")).split(" ")[0])
	var ng = ctx.get("grammar", "f" if bool(ctx.get("female", false)) else "m")
	text = text.replace("{ng}", Grammar.past(ng))
	# Stejnou myšlenku hned znovu nepřidávat.
	if not thoughts.is_empty() and thoughts[-1]["text"] == text:
		return ""
	thoughts.append({"t": now, "text": text, "kind": kind})
	while thoughts.size() > MAX_THOUGHTS:
		thoughts.pop_front()
	_thought_cd = rng.randf_range(20.0, 45.0)
	return text


# ---------------------------------------------------------------- vliv na zbytek simulace

## Násobič úbytku energie (napětí vyčerpává).
func energy_drain_mult() -> float:
	return (1.0 + maxf(arousal - 30.0, 0.0) / 140.0) * dep.energy_drain_mult()


## Kvalita spánku 0.45..1 (úzkost a alkohol zhoršují spánek).
func sleep_quality() -> float:
	var q := 1.0 - maxf(arousal - 35.0, 0.0) / 65.0 * 0.45 - alcohol * 0.25
	q *= dep.sleep_quality_mult()
	return clampf(q, 0.45, 1.0)


## Jak náročné jsou teď sociální akce (0 = běžné, 1 = velmi) – nikdy je nezamyká.
func social_difficulty(cfg: Dictionary = {}) -> float:
	var social := _cond_param("social", cfg) + trait_vuln * 0.5
	return clampf((arousal / 100.0) * (0.3 + social) + threat * social + float(_hk("social_cost", cfg, 0.0)), 0.0, 1.0)


## Chuť na coping (pro utility AI). Nezdravé copingy lákají víc, když je postava vyčerpaná
## (nízká regulace) nebo impulzivní; zdravé, když má kapacitu.
func coping_appeal(id: String, energy: float, hunger: float, now: float, impulsive := false, cfg: Dictionary = {}) -> float:
	var def: Dictionary = COPINGS.get(id, {})
	if def.is_empty():
		return 0.0
	var need := maxf(arousal - 30.0, 0.0) * 0.55 + maxf(stress - 42.0, 0.0) * 0.35
	if need <= 0.0:
		return 0.0
	var reg := regulation(energy, hunger)
	var k := habituation(id, now)
	if bool(def.get("healthy", false)):
		k *= (0.5 + reg * 0.7 + mastery * 0.3) * float(_hk("healthy_appeal", cfg, 1.0))
	else:
		k *= (0.5 + (1.0 - reg) * 0.9 + (0.5 if impulsive else 0.0)) * float(_hk("unhealthy_appeal", cfg, 1.0))
		if id == "drink":
			k *= 1.0 + tolerance * 0.8  # návyk: čím častěji, tím víc to táhne
			var rd := recent_drinks(now)
			k /= 1.0 + DRINK_DAY_APPEAL_K * rd * rd  # dnes už toho bylo dost
	return need * k


## Moodlety plynoucí z duševního stavu (pro Mood.evaluate).
func mood_entries() -> Array:
	var out: Array = []
	if panic_active:
		out.append({"id": "panika", "label": "Panická ataka", "emotion": "uzkostny", "strength": -32.0, "remaining": -1.0})
	elif arousal > 55.0:
		out.append({"id": "uzkost", "label": "Úzkost", "emotion": "uzkostny",
			"strength": -lerpf(8.0, 24.0, (arousal - 55.0) / 45.0), "remaining": -1.0})
	elif arousal > 38.0:
		out.append({"id": "nervozita", "label": "Nervozita", "emotion": "napjaty", "strength": -6.0, "remaining": -1.0})
	if stress > 60.0:
		out.append({"id": "stres", "label": "Ve stresu", "emotion": "napjaty",
			"strength": -lerpf(8.0, 20.0, (stress - 60.0) / 40.0), "remaining": -1.0})
	if rebound > 0.12:
		out.append({"id": "rebound", "label": "Kocovina a úzkost", "emotion": "nesvuj", "strength": -10.0, "remaining": -1.0})
	if alcohol > 0.2:
		out.append({"id": "opily", "label": "Přiopilý", "emotion": "spokojeny", "strength": 5.0, "remaining": -1.0})
	if support > 0.35:
		out.append({"id": "opora", "label": "Cítí oporu", "emotion": "spokojeny", "strength": 8.0, "remaining": -1.0})
	out.append_array(dep.mood_entries(_hour))
	return out


## Slovní popis stavu (pro HUD) – žádná diagnostická čísla navenek.
func state_label(cfg: Dictionary = {}) -> String:
	var anx := ""
	if panic_active:
		return "Panická ataka"
	if arousal > 65.0:
		anx = "Silná úzkost"
	elif arousal > 45.0:
		anx = "Úzkost"
	elif arousal > 30.0 or stress > 55.0:
		anx = "Nervozita"
	var low: String = dep.label(cfg)
	if anx != "" and low != "":
		return anx + " · " + low.to_lower()
	if low != "":
		return low
	return anx if anx != "" else "Klid"


## Data pro soukromý detail (vidí jen vlastník postavy).
func detail(cfg: Dictionary = {}) -> Dictionary:
	var th: Array = []
	for e in thoughts.slice(-3):
		th.append([float(e["t"]), String(e["text"])])
	var conds: Array = []
	if bool(cfg.get("conditions", true)):
		for id in conditions:
			conds.append(String(CONDITIONS.get(id, {}).get("label", id)))
	return {"stress": int(round(stress)), "arousal": int(round(arousal)), "label": state_label(cfg),
		"panic": panic_active, "thoughts": th, "conditions": conds,
		"low": int(round(dep.burden * 100.0)), "anhedonia": dep.hedonic < 0.6,
		"day": "špatný den" if day_factor < -0.35 else ("dobrý den" if day_factor > 0.35 else "")}


func to_dict() -> Dictionary:
	return {"stress": stress, "arousal": arousal, "threat": threat, "sensitivity": sensitivity,
		"mastery": mastery, "support": support, "conditions": conditions.duplicate(),
		"trait_vuln": trait_vuln, "day_factor": day_factor, "alcohol": alcohol, "tolerance": tolerance,
		"rebound": rebound, "panic_cooldown": panic_cooldown, "panic_exhaust": panic_exhaust, "drink_times": drink_times.duplicate(), "coping_log": coping_log.duplicate(true),
		"last_daily": last_daily.duplicate(), "trait_dep": trait_dep, "dep": dep.to_dict()}


func from_dict(d: Dictionary) -> void:
	for k in ["stress", "arousal", "threat", "sensitivity", "mastery", "support", "trait_vuln",
			"day_factor", "alcohol", "tolerance", "rebound", "panic_cooldown", "panic_exhaust", "trait_dep"]:
		if d.has(k):
			set(k, float(d[k]))
	conditions = d.get("conditions", {}).duplicate()
	coping_log = d.get("coping_log", {}).duplicate(true)
	last_daily = d.get("last_daily", {}).duplicate()
	drink_times = (d.get("drink_times", []) as Array).duplicate() if typeof(d.get("drink_times", [])) == TYPE_ARRAY else []
	panic_active = false
	if typeof(d.get("dep")) == TYPE_DICTIONARY:
		dep.from_dict(d["dep"])
