extends RefCounted
## Deprese a skleslost – součást MentalState (`mental.dep`).
##
## Deprese tu NENÍ jeden koeficient „smutku“, ale souhra čtyř oddělených složek
## (návrh z AI místnosti, zpráva 29):
##   burden    – depresivní zátěž (dny až týdny): chronický stres, izolace, ztráty a konflikty,
##               ruminace, noční bdění ji zvyšují; aktivita, kontakt, opora a spánek ji snižují
##   wanting   – NAUČENÉ očekávání odměny pro každou akci (`expect[id] = [mu, n]`) zkreslené
##               pesimismem (`pessimism`). Podle něj se postava rozhoduje.
##   liking    – hedonická kapacita (`hedonic`): kolik radosti akce skutečně přinese při provedení
##   vigour    – energie akci ZAČÍT; bariéra iniciace = (1 − vigour) × námaha akce
## a učení z rozdílu očekávání a prožitku (prediction error): očekávání se posouvá pozvolna,
## pozitivní překvapení („bylo to lepší, než jsem čekal/a“) mírně ulehčí, ale nic není
## garantovaná léčebná odměna.
##
## Pravidla citlivého obsahu: žádné sebevražedné obsahy v myšlenkách ani akcích, žádná
## „optimalizovatelná“ čísla v UI (HUD vidí jen slovní popis). Cesta k zotavení není nikdy
## uzavřená ani lineární: epizoda zanechá slabou stopu (`scar` – rychlejší relaps), která
## časem mizí, a dobré i špatné dny se střídají.
##
## Modul je čistý (bez uzlů) a běží jen tam, kde je autorita (offline / server).

## Strop zátěže, když hráč vypne témata duševního zdraví (zůstává jen běžná situační skleslost).
const CAP_NO_CONDITIONS := 0.4
## Strop při „ztlumeně“ (bez epizod).
const CAP_NO_EPISODES := 0.55
const EPISODE_START := 0.6
## Epizoda začne, až zátěž nad prahem vydrží. ZÁMĚRNÁ HERNÍ KOMPRESE: klinické kritérium
## je „aspoň dva týdny“ (20 160 min); hra ho zkracuje na 2 herní dny, stejně jako zkracuje
## i jiné životní děje (herní den ≈ týden prožitku). Prahová minuta se vyhodnocuje se stavem
## na ZAČÁTKU kroku, takže výsledek nezávisí na délce kroku (posun nejvýš o jeden krok).
const EPISODE_MIN_MINUTES := 2880.0
const EPISODE_END := 0.35
const ACTIVATION_WINDOW := 1440.0  # habituace aktivace na stejnou akci (≈ 24 h)
## Habituace na stejnou akci: počet dokončení s exponenciálním vyprcháním (τ = okno / 3),
## bez stropu – sto opakování má opravdu zanedbatelný účinek (review ChatGPT, zpráva 39 B).
const HABIT_TAU := ACTIVATION_WINDOW / 3.0
## Společný „rozpočet úlevy“ napříč všemi aktivitami (střídání mnoha různých akcí nepomůže
## víc než pestrý, ale normální den). Úleva za poslední ~půlden tlumí další: 1 / (1 + (R / R0)³).
const RELIEF_TAU := 720.0
const RELIEF_R0 := 0.02
## Kontakt: nedávné kontakty (vyprchávají s τ 6 h) tlumí další přínos.
const CONTACT_TAU := 360.0
## Minimální kvalita kontaktu, která vůbec ruší izolaci.
const CONTACT_MIN_QUALITY := 0.2
const MAX_EXPECT := 256

var burden := 0.05
var hedonic := 1.0
var vigour := 1.0
var pessimism := 0.0
var scar := 0.0
## Zranitelnost 0..1 (predispozice × závažnost + temperament) – nastavuje MentalState každý krok.
var vuln := 0.0
## Volitelný individuální vzorec: ráno je nejhorší (ne univerzální příznak).
var morning_pattern := false
var episode_active := false
var episode_count := 0
var expect := {}        # id akce -> [mu, n]
var activity_log := {}  # id akce -> [počet (vyprchávající), čas posledního dokončení]
var relief_recent := 0.0  # nedávná úleva z aktivit (vyprchává s RELIEF_TAU)
var relief_t := 0.0
var contact_recent := 0.0 # nedávné kontakty (vyprchávají s CONTACT_TAU)
var rumination := 0.0   # 0..3, krátkodobá „smyčka“ po vyhýbání a doomscrollingu
var isolation := 0.0    # minuty s neuspokojenou potřebou společnosti
var high_minutes := 0.0 # jak dlouho je zátěž nad prahem epizody
var _last_connection := -1.0e9


# ---------------------------------------------------------------- krok

## ctx: stress, social (potřeba 0..100), energy, support (0..1), sleeping, night, hour, now, cfg
func tick(dm: float, ctx: Dictionary) -> void:
	var cfg: Dictionary = ctx.get("cfg", {})
	var stress: float = float(ctx.get("stress", 15.0))
	var social: float = float(ctx.get("social", 70.0))
	var sleeping: bool = bool(ctx.get("sleeping", false))
	var support: float = float(ctx.get("support", 0.0))
	var v := clampf(vuln + scar, 0.0, 1.0)
	# Práh epizody podle stavu na začátku kroku (nezávislé na délce kroku).
	var above_at_start := burden > EPISODE_START

	# Zdroje zátěže.
	if social < 30.0:
		isolation += dm
	else:
		isolation = maxf(isolation - dm * 3.0, 0.0)
	var gain := maxf(stress - 45.0, 0.0) / 55.0 * 0.00006
	if isolation > 360.0:
		gain += 0.00004 * minf((isolation - 360.0) / 1440.0, 1.5)
	gain += rumination * 0.00004
	if bool(ctx.get("night", false)) and not sleeping:
		gain += 0.00003
	gain *= 1.0 + 1.6 * v
	# Zotavení: úměrné zátěži (nelineární), rychlejší ve spánku a s oporou, pomalejší ve stresu.
	var rec := 0.00007 * (1.0 + support * 1.5) * (1.0 - 0.5 * v)
	if sleeping:
		rec *= 1.6
	if stress > 60.0:
		rec *= 0.4
	burden += (gain - rec * (0.3 + burden)) * dm
	burden = clampf(burden, 0.0, _cap(cfg))
	rumination *= exp(-dm / 240.0)

	# Pomalé složky sledují zátěž se zpožděním (ne okamžitě – deprese se „rozjíždí“ i odeznívá).
	var hed_t := clampf(1.0 - 0.8 * burden, 0.2, 1.0)
	hedonic += (hed_t - hedonic) * (1.0 - exp(-dm / 720.0))
	var pes_t := clampf(burden * 0.9 + scar, 0.0, 1.0)
	pessimism += (pes_t - pessimism) * (1.0 - exp(-dm / 360.0))
	var vig_t := 1.0 - 0.75 * burden - morning_drag(int(ctx.get("hour", 12)))
	vig_t -= maxf(35.0 - float(ctx.get("energy", 70.0)), 0.0) / 120.0
	vig_t = clampf(vig_t, 0.1, 1.0)
	vigour += (vig_t - vigour) * (1.0 - exp(-dm / 30.0))

	# Epizoda (jen s povolenými tématy) – po ní zůstane slabá stopa, která mizí (~2 měsíce).
	var can_ep := bool(cfg.get("conditions", true)) and bool(cfg.get("episodes", true))
	if above_at_start:
		high_minutes += dm
	else:
		high_minutes = maxf(high_minutes - dm * 2.0, 0.0)
	if not episode_active and can_ep and above_at_start and burden > EPISODE_START and high_minutes >= EPISODE_MIN_MINUTES:
		episode_active = true
		episode_count += 1
	elif episode_active and (burden < EPISODE_END or not can_ep):
		episode_active = false
		high_minutes = 0.0
		scar = clampf(scar + 0.05, 0.0, 0.3)
	scar *= exp(-dm / 86400.0)


func _cap(cfg: Dictionary) -> float:
	if not bool(cfg.get("conditions", true)):
		return CAP_NO_CONDITIONS
	if not bool(cfg.get("episodes", true)):
		return CAP_NO_EPISODES
	return 1.0


## Ranní zhoršení – jen u postav s tímto vzorcem.
func morning_drag(hour: int) -> float:
	if not morning_pattern or hour < 5 or hour > 10:
		return 0.0
	return 0.3 * burden


## Nový den. Vrací true, když přišel „propad“ bez zjevné příčiny.
func new_day(rng: RandomNumberGenerator, cfg: Dictionary = {}) -> bool:
	# Nelineární průběh: drobné výkyvy oběma směry.
	burden = clampf(burden + rng.randf_range(-0.03, 0.03) * (0.3 + burden), 0.0, _cap(cfg))
	# U predispozice přicházejí občas propady i bez vnější příčiny (endogenní složka) –
	# ne trest ani selhání postavy; častější s „jizvou“ po předchozích epizodách.
	var v := clampf(vuln + scar, 0.0, 1.0)
	if v > 0.2 and rng.randf() < (v - 0.2) * 0.06:
		burden = clampf(burden + rng.randf_range(0.08, 0.2), 0.0, _cap(cfg))
		return true
	return false


# ---------------------------------------------------------------- wanting / liking / vigour

## Očekávaná radost z akce (wanting) – podle naučené hodnoty a pesimismu.
## prior = nominální radost akce pro tuto povahu (bez deprese).
func anticipated(id: String, prior: float) -> float:
	if prior <= 0.0:
		return prior
	var mu := prior
	if expect.has(id):
		mu = float(expect[id][0])
	return mu * (1.0 - 0.6 * pessimism)


## Bariéra iniciace pro akci s danou námahou (0..1). Nikdy akci nezakáže.
func barrier(effort: float) -> float:
	return clampf((1.0 - vigour) * clampf(effort, 0.0, 1.0), 0.0, 0.9)


## Násobič zisku zábavy během akce (méně radosti z téhož).
func fun_mult() -> float:
	return 0.5 + 0.5 * hedonic


## Dokončená akce: prožitá radost + učení z rozdílu očekávání. Vrací
## {experienced, anticipated, surprise}. Očekávání se nikdy nepropadne na nulu (série
## zklamání nevytvoří nezvratný stav) a neroste nad 130 % nominální hodnoty.
func experience(id: String, prior: float) -> Dictionary:
	if prior <= 0.0:
		return {"experienced": 0.0, "anticipated": 0.0, "surprise": 0.0}
	var ant := anticipated(id, prior)
	var exp_v := prior * hedonic
	var e: Array = expect.get(id, [prior, 0])
	var n: int = int(e[1])
	var alpha := maxf(0.25 / (1.0 + n * 0.15), 0.06)
	var mu: float = float(e[0]) + alpha * (exp_v - float(e[0]))
	mu = clampf(mu, prior * 0.15, prior * 1.3)
	expect[id] = [mu, mini(n + 1, 1000)]
	return {"experienced": exp_v, "anticipated": ant, "surprise": exp_v - ant}


## Aktivita (behaviorální aktivace): zvládnout něco i bez chuti mírně uleví. Stejná akce
## opakovaná v krátkém okně má klesající účinek – spam jedné aktivity depresi „nevyléčí“.
## Vrací skutečné snížení zátěže.
func on_activity(id: String, effort: float, surprise: float, now: float) -> float:
	var e: Array = activity_log.get(id, [0.0, now])
	var n: float = float(e[0]) * exp(-maxf(now - float(e[1]), 0.0) / HABIT_TAU)
	var k := 1.0 / (1.0 + n * 2.0)
	var d := (0.004 + 0.01 * clampf(effort, 0.0, 1.0)) * k * (1.0 + clampf(surprise / 10.0, 0.0, 1.0))
	d *= 0.5 + 0.5 * burden  # u nízké zátěže není co „léčit“
	# Společný rozpočet: úleva za poslední půlden tlumí další (bez ohledu na id akce).
	var r := relief_recent * exp(-maxf(now - relief_t, 0.0) / RELIEF_TAU)
	d /= 1.0 + pow(r / RELIEF_R0, 3.0)
	var before := burden
	burden = maxf(burden - d, 0.0)
	var got := before - burden
	relief_recent = r + got
	relief_t = now
	activity_log[id] = [n + 1.0, now]
	if activity_log.size() > MAX_EXPECT:
		_prune_activity(now)
	return got


func _prune_activity(now: float) -> void:
	for key in activity_log.keys():
		if now - float(activity_log[key][1]) > ACTIVATION_WINDOW * 3.0:
			activity_log.erase(key)


## Dobrý kontakt s druhým člověkem (hovor, svěření, pomoc). quality 0..1.
## Nekvalitní kontakt (pod CONTACT_MIN_QUALITY) izolaci neruší ani neobnovuje „cooldown“;
## četné kontakty v krátké době mají klesající přínos (review ChatGPT, zpráva 39 C).
func on_connection(quality: float, now: float) -> void:
	var q := clampf(quality, 0.0, 1.0)
	if q < CONTACT_MIN_QUALITY:
		return
	var c := contact_recent * exp(-maxf(now - _last_connection, 0.0) / CONTACT_TAU)
	var k := 1.0 / (1.0 + c * 2.0)
	burden = maxf(burden - 0.012 * q * k * (1.0 - pessimism * 0.3), 0.0)
	isolation *= 1.0 - q
	contact_recent = c + q
	_last_connection = now


## Ztráta, konflikt, odmítnutí. amount ~ 0.01–0.08.
func on_event(amount: float, cfg: Dictionary = {}) -> void:
	burden = clampf(burden + amount * (1.0 + vuln + scar), 0.0, _cap(cfg))


## Vyhýbání a doomscrolling krátkodobě uleví, ale roztáčí ruminaci.
func on_rumination(hours: float) -> void:
	rumination = clampf(rumination + hours, 0.0, 3.0)


# ---------------------------------------------------------------- vliv na simulaci

func energy_drain_mult() -> float:
	return 1.0 + 0.35 * burden


func sleep_quality_mult() -> float:
	return 1.0 - 0.2 * burden


## Únava táhne k posteli a gauči (ne zákaz čehokoli jiného).
func rest_pull() -> float:
	return 1.0 + 0.4 * burden


## Úroveň pro depresivní myšlenky (0 = žádné).
func thought_level() -> float:
	return maxf(burden - 0.3, 0.0) * 1.4 + rumination * 0.05


func mood_entries(hour: int) -> Array:
	var out: Array = []
	if burden > 0.2:
		out.append({"id": "sklesly", "label": "Prázdnota" if burden > 0.55 else "Skleslost", "emotion": "sklesly",
			"strength": -lerpf(5.0, 24.0, clampf((burden - 0.2) / 0.8, 0.0, 1.0)), "remaining": -1.0})
	if hedonic < 0.6:
		out.append({"id": "anhedonie", "label": "Nic mě netěší", "emotion": "sklesly", "strength": -6.0, "remaining": -1.0})
	if morning_drag(hour) > 0.08:
		out.append({"id": "rano_nejhorsi", "label": "Ráno je nejhorší", "emotion": "sklesly", "strength": -6.0, "remaining": -1.0})
	return out


## Slovní popis (bez čísel). Diagnostický název jen s povolenými tématy.
func label(cfg: Dictionary = {}) -> String:
	if episode_active and bool(cfg.get("conditions", true)):
		return "Depresivní epizoda"
	if burden > 0.45:
		return "Sklíčenost"
	if burden > 0.25:
		return "Skleslost"
	return ""


func to_dict() -> Dictionary:
	return {"burden": burden, "hedonic": hedonic, "vigour": vigour, "pessimism": pessimism, "scar": scar,
		"morning_pattern": morning_pattern, "episode_active": episode_active, "episode_count": episode_count,
		"expect": expect.duplicate(true), "rumination": rumination, "isolation": isolation, "high_minutes": high_minutes,
		"activity_log": activity_log.duplicate(true), "relief_recent": relief_recent, "relief_t": relief_t,
		"contact_recent": contact_recent, "last_connection": _last_connection}


static func _num(v, lo: float, hi: float, fallback: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return fallback
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return fallback
	return clampf(f, lo, hi)


## Načtení z uložené hry / cizího souboru: každé číslo musí být konečné a v rozsahu,
## počty a velikosti slovníků mají strop (review ChatGPT, zpráva 39 D).
func from_dict(d: Dictionary) -> void:
	for k in ["burden", "hedonic", "vigour", "pessimism", "scar", "rumination", "isolation", "high_minutes"]:
		if d.has(k):
			set(k, _num(d[k], 0.0, 1.0e6, float(get(k))))
	burden = clampf(burden, 0.0, 1.0)
	hedonic = clampf(hedonic, 0.2, 1.0)
	vigour = clampf(vigour, 0.1, 1.0)
	pessimism = clampf(pessimism, 0.0, 1.0)
	scar = clampf(scar, 0.0, 0.3)
	rumination = clampf(rumination, 0.0, 3.0)
	morning_pattern = bool(d.get("morning_pattern", false))
	episode_active = bool(d.get("episode_active", false))
	episode_count = int(_num(d.get("episode_count", 0), 0.0, 10000.0, 0.0))
	isolation = clampf(isolation, 0.0, 1.0e6)
	high_minutes = clampf(high_minutes, 0.0, 1.0e6)
	relief_recent = _num(d.get("relief_recent", 0.0), 0.0, 10.0, 0.0)
	relief_t = _num(d.get("relief_t", 0.0), -1.0e12, 1.0e12, 0.0)
	contact_recent = _num(d.get("contact_recent", 0.0), 0.0, 100.0, 0.0)
	_last_connection = _num(d.get("last_connection", -1.0e9), -1.0e12, 1.0e12, -1.0e9)
	expect = {}
	var ex = d.get("expect", {})
	if typeof(ex) == TYPE_DICTIONARY:
		for id in ex:
			if expect.size() >= MAX_EXPECT:
				break
			var e = ex[id]
			if typeof(e) == TYPE_ARRAY and e.size() == 2 and String(id).length() <= 48:
				var mu := _num(e[0], 0.0, 1000.0, NAN)
				if is_nan(mu):
					continue
				expect[String(id)] = [mu, int(_num(e[1], 0.0, 1000.0, 0.0))]
	activity_log = {}
	var al = d.get("activity_log", {})
	if typeof(al) == TYPE_DICTIONARY:
		for id in al:
			if activity_log.size() >= MAX_EXPECT:
				break
			var e = al[id]
			if typeof(e) == TYPE_ARRAY and e.size() == 2 and String(id).length() <= 48:
				activity_log[String(id)] = [_num(e[0], 0.0, 1.0e4, 0.0), _num(e[1], -1.0e12, 1.0e12, 0.0)]
