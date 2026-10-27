extends RefCounted
## Vnitřní hlas (psychika I, 27. 10. 2026) – soukromý proud myšlenek postavy nad existujícím modelem
## rušivých myšlenek (MentalState.thoughts) a ruminace (Depression.rumination).
##
## Myšlenka NIKDY není náhodná výplň: vzniká z dat – z vyhodnocení události (urážka, odmítnutí, nezdar,
## podpora), ze stop sociální paměti, z aktuálního stavu (stres, hrozba, depresivní zátěž) a z rysů
## (vnitřní přesvědčení self_defectiveness, optimismus). Šablona se vybírá podle tématu; jméno je jen
## popisek osoby, o které myšlenka je.
##
## Smyčky ruminace (`loops`): opakované negativní přemítání o křivdě, nezdaru, obavě nebo o sobě.
##   - síla smyčky roste v nečinnosti, v klidu a při bdění v noci, slábne rozptýlením (zábava, pohyb,
##     zájem, lidé), oporou (svěření), řešením (omluva, psaní deníku) a spánkem;
##   - stojí spánek, energii a náladu a živí existující ruminaci deprese;
##   - mění jen náklady akcí: řešení a opora lákají víc, nic se nevynucuje.
## Naděje a dobré myšlenky vznikají stejně z dat (opora, usmíření, dobrý zážitek).
##
## Pasivní beznaděj („nechci tu být“) je VÝHRADNĚ soukromý, negrafický stav myšlenek a jen při výslovném
## zapnutí citlivého obsahu (sh_ed, výchozí vypnuto) a plných tématech duševního zdraví. Žádné metody,
## plány ani čísla, nikdy akce ani autonomní chování, nikdy viditelné jiným postavám ani hráčům a nikdy
## v síťových datech. Zvyšuje užitek obrátit se na někoho / vyhledat pomoc; vlastník hry v tu chvíli
## uvidí krizovou pomoc (116 123, findahelpline.com). Slábne s oporou, spánkem, nižším stresem a zotavením.

const TOPICS := ["grievance", "failure", "worry", "self_critical"]
const MAX_LOOPS := 4
## Pod touto silou se smyčka rozpustí.
const LOOP_END := 0.05
## Práh, od kterého se pasivní beznaděj vůbec projeví (a ukáže se krizová pomoc vlastníkovi).
const HOPELESS_SHOW := 0.35

## Šablony myšlenek podle tématu ({name} = osoba). Gramatický rod přes Grammar ({g}).
const TEXT := {
	"grievance": ["Pořád si přehrávám, co mi {name} řekl{ng}.", "Proč mi to {name} udělal{ng}?",
		"Mělo mi to být jedno, ale není."],
	"failure": ["Zase jsem to nezvládl{g}.", "Kdybych to udělal{g} jinak…", "Tohle jsem fakt pokazil{g}."],
	"worry": ["Co když se to zítra pokazí?", "Pořád mám pocit, že na něco zapomínám.", "Nevím, jak to všechno stihnu."],
	"self_critical": ["Jsem prostě nedostatečn{y}.", "Ostatní to zvládají líp než já.", "Zase jsem ten problém já."],
	"hope": ["Možná to nakonec dobře dopadne.", "Dneska to bylo lepší, než jsem čekal{g}.", "Nejsem v tom úplně bez lidí."],
	"warm": ["{name} mi dneska fakt pomohl{ng}.", "S {name} mi bylo dobře.", "Jsem rád{a}, že {name} je tady."],
	"relief": ["Dobře, že jsme si to vyříkali.", "Už to tolik nebolí."],
	"hopeless": ["Nevidím, jak by to mohlo být lepší.", "Kéž bych tu chvíli nemusel{g} být.", "Je toho na mě moc."],
}

## Styl (mind.thoughts, 0,5 = průměr → násobič 1): síla ruminace, starostí a naděje.
var rum_k := 1.0
var worry_k := 1.0
var hope_k := 1.0

var loops: Array = []
## Pasivní beznaděj 0..1 – jen při opt-in citlivém obsahu, jinak vždy 0.
var hopelessness := 0.0
## Zobrazila se vlastníkovi krizová pomoc v aktuální vlně? (aby se notice neopakoval každý krok)
var crisis_shown := false
var _last_hope_t := -1.0e9
var positive_count := 0


func strength_total() -> float:
	var s := 0.0
	for l in loops:
		s += float(l["strength"])
	return clampf(s, 0.0, 2.0)


func strongest() -> Dictionary:
	var best := {}
	for l in loops:
		if best.is_empty() or float(l["strength"]) > float(best["strength"]):
			best = l
	return best


func configure(style: Variant) -> void:
	var s: Dictionary = style if typeof(style) == TYPE_DICTIONARY else {}
	rum_k = _style(s, "rumination")
	worry_k = _style(s, "worry")
	hope_k = _style(s, "hope")


static func _style(s: Dictionary, key: String) -> float:
	var v = s.get(key, 0.5)
	var f := float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)) else 0.5
	return lerpf(0.3, 1.7, clampf(f, 0.0, 1.0))


## Spouštěč: událost otevře nebo posílí smyčku (téma, o kom, jak silně). Vrací text myšlenky nebo "".
## self_belief = mind.self_defectiveness – zvyšuje sebekritickou odezvu na nezdar a odmítnutí.
func trigger(topic: String, about: String, about_name: String, amount: float, now: float, k: float,
		self_belief: float = 0.0) -> String:
	if k <= 0.0 or not TOPICS.has(topic) or not is_finite(amount) or amount <= 0.0:
		return ""
	amount = clampf(amount * (worry_k if topic == "worry" else rum_k), 0.0, 1.0) * k
	_bump(topic, about, about_name, amount, now)
	# Vnitřní přesvědčení: nezdar a odmítnutí se snáz obrátí proti sobě.
	if self_belief > 0.0 and topic in ["failure", "grievance"]:
		_bump("self_critical", "", "", amount * 0.8 * self_belief, now)
	return template(topic, about_name)


func _bump(topic: String, about: String, about_name: String, amount: float, now: float) -> void:
	for l in loops:
		if l["topic"] == topic and l["about"] == about:
			l["strength"] = clampf(float(l["strength"]) + amount * (1.0 - float(l["strength"])), 0.0, 1.0)
			l["last"] = now
			return
	loops.append({"topic": topic, "about": about, "name": about_name.substr(0, 40), "strength": clampf(amount, 0.0, 1.0),
		"start": now, "last": now})
	if loops.size() > MAX_LOOPS:
		loops.sort_custom(func(x, y): return float(x["strength"]) > float(y["strength"]))
		loops = loops.slice(0, MAX_LOOPS)


## Dobrá zkušenost (opora, usmíření, dobrý zážitek) – naděje; uvolní související smyčky.
func positive(kind: String, about: String, about_name: String, now: float, k: float) -> String:
	if k <= 0.0:
		return ""
	for l in loops:
		if (about != "" and l["about"] == about) or (kind == "hope" and l["topic"] in ["worry", "self_critical"]):
			l["strength"] = float(l["strength"]) * (0.6 if kind != "hope" else 0.85)
	hopelessness *= 0.85
	_prune()
	if now - _last_hope_t < 120.0 / hope_k:
		return ""
	_last_hope_t = now
	positive_count += 1
	return template(kind, about_name)


## Řešení konkrétní smyčky (omluva tomu, o kom je; psaní deníku = všechny trochu).
func resolve(about: String, factor: float) -> void:
	for l in loops:
		if about == "" or l["about"] == about:
			l["strength"] = float(l["strength"]) * clampf(1.0 - factor, 0.0, 1.0)
	_prune()


func _prune() -> void:
	var keep: Array = []
	for l in loops:
		if float(l["strength"]) >= LOOP_END:
			keep.append(l)
	loops = keep


func template(kind: String, about_name: String) -> String:
	var pool: Array = TEXT.get(kind, [])
	if pool.is_empty():
		return ""
	# Deterministicky podle počtu smyček a jména (žádná náhoda): výběr šablony je jen stylistický.
	var idx := absi(hash(about_name + kind + str(loops.size()))) % pool.size()
	return String(pool[idx]).replace("{name}", about_name.split(" ")[0] if about_name != "" else "někdo")


## Krok. ctx: idle (nečinnost), quiet, night_awake, sleeping, distraction (0..1 – zábava, pohyb, zájem,
## lidé), stress, burden (depresivní zátěž), support, rejection (distress 0..1), self_belief,
## allow_hopeless (opt-in citlivý obsah + plná témata).
func tick(dm: float, ctx: Dictionary, k: float) -> void:
	if dm <= 0.0:
		return
	if k <= 0.0:
		loops.clear()
		hopelessness = 0.0
		crisis_shown = false
		return
	var sleeping := bool(ctx.get("sleeping", false))
	var distraction := clampf(float(ctx.get("distraction", 0.0)), 0.0, 1.0)
	var stress := float(ctx.get("stress", 15.0))
	var support := clampf(float(ctx.get("support", 0.0)), 0.0, 1.0)
	for l in loops:
		var s := float(l["strength"])
		var grow := 0.0
		if bool(ctx.get("night_awake", false)):
			grow += 0.003
		elif bool(ctx.get("idle", false)) or bool(ctx.get("quiet", false)):
			grow += 0.0012
		grow *= (0.5 + stress / 100.0) * (1.0 - s) * rum_k
		var decay := 1.0 / 720.0 + distraction / 240.0 + support / 300.0 + (1.0 / 240.0 if sleeping else 0.0)
		l["strength"] = clampf(s + grow * dm - s * (1.0 - exp(-decay * dm)), 0.0, 1.0)
	_prune()
	# Pasivní beznaděj: jen opt-in. Cíl ze zátěže, sebeobrazu, odmítnutí a smyček; opora, spánek a klid tlumí.
	if not bool(ctx.get("allow_hopeless", false)):
		hopelessness = 0.0
		crisis_shown = false
		return
	var burden := float(ctx.get("burden", 0.0))
	var tgt := maxf(burden - 0.55, 0.0) * 1.6 + 0.25 * float(ctx.get("self_belief", 0.0)) * maxf(burden - 0.4, 0.0) * 2.0 \
		+ 0.2 * float(ctx.get("rejection", 0.0)) + 0.15 * maxf(strength_total() - 0.8, 0.0) + maxf(stress - 70.0, 0.0) / 150.0
	tgt *= 1.0 - 0.6 * support
	tgt = clampf(tgt, 0.0, 1.0)
	var tau := 720.0 if tgt > hopelessness else (240.0 if sleeping or support > 0.2 else 480.0)
	hopelessness += (tgt - hopelessness) * (1.0 - exp(-dm / tau))
	if hopelessness < HOPELESS_SHOW * 0.6:
		crisis_shown = false


## Náklady akcí (omezené): ruminace táhne k řešení a k lidem, kterým věří (svěřit se, deník, procházka,
## omluva), beznaděj zvyšuje užitek obrátit se na někoho a vyhledat pomoc. Nic se nevynucuje ani nezakazuje.
func action_weight(act: Dictionary, k: float) -> float:
	if k <= 0.0 or (loops.is_empty() and hopelessness <= 0.0):
		return 1.0
	var id := String(act.get("id", ""))
	var r := strength_total()
	var m := 1.0
	match id:
		"confide":
			m *= 1.0 + 0.35 * r + 0.8 * hopelessness
		"journal", "go_walk":
			m *= 1.0 + 0.3 * r
		"seek_help":
			m *= 1.0 + 0.5 * r + 1.5 * hopelessness
		"doomscroll":
			m *= 1.0 + 0.2 * r
	if (act.get("tags", []) as Array).has("sleep"):
		m *= 1.0 - 0.15 * minf(r, 1.0)
	return clampf(m, 0.5, 2.5)


## Bariéra pro akci „vyhledat pomoc“: bez důvodu ji AI nevolí (hráč ji smí zadat kdykoli).
func help_need() -> float:
	return clampf(maxf(strength_total() - 0.9, 0.0) * 0.5 + hopelessness, 0.0, 1.0)


func sleep_quality_mult() -> float:
	return 1.0 - 0.08 * minf(strength_total(), 1.0) - 0.1 * hopelessness


func energy_drain_mult() -> float:
	return 1.0 + 0.05 * minf(strength_total(), 1.0)


## Kolik ruminace přidat do Depression.rumination za herní minutu.
func rumination_feed() -> float:
	return 0.0006 * minf(strength_total(), 1.5)


func mood_entries(k: float) -> Array:
	var out: Array = []
	if k <= 0.0:
		return out
	var s := strongest()
	if not s.is_empty() and float(s["strength"]) > 0.45:
		var label := "Pořád na to myslím"
		match String(s["topic"]):
			"worry":
				label = "Starosti se točí dokola"
			"self_critical":
				label = "Vnitřní kritik nedá pokoj"
		out.append({"id": "iv_ruminace", "label": label, "emotion": "napjaty",
			"strength": -lerpf(2.0, 6.0, clampf((float(s["strength"]) - 0.45) / 0.55, 0.0, 1.0)) * k, "remaining": -1.0})
	return out


## Soukromý popis pro vlastníka offline (slova, žádná čísla). Beznaděj jen jako opatrná věta + kde je pomoc.
func private_lines(k: float, crisis_lines: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0:
		return out
	var s := strongest()
	if not s.is_empty() and float(s["strength"]) > 0.35:
		var what := {"grievance": "křivda", "failure": "nezdar", "worry": "starost", "self_critical": "kritika sebe sama"}
		var who := (" (" + String(s["name"]).split(" ")[0] + ")") if String(s["name"]) != "" else ""
		out.append("V hlavě se točí dokola: %s%s. Pomáhá rozptýlení, svěřit se nebo věc vyřešit." % [what[s["topic"]], who])
	if hopelessness >= HOPELESS_SHOW:
		out.append("Přicházejí myšlenky beznaděje. Teď je důležité nebýt na to sám – obrátit se na někoho blízkého nebo na odbornou pomoc.")
		for line in crisis_lines:
			if typeof(line) == TYPE_ARRAY and line.size() >= 2:
				out.append("%s: %s" % [String(line[0]), String(line[1])])
	return out


func to_dict() -> Dictionary:
	return {"loops": loops.duplicate(true), "hopelessness": hopelessness, "crisis_shown": crisis_shown,
		"last_hope_t": _last_hope_t, "positive_count": positive_count}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 8:
		return false
	for key in d:
		if not ["loops", "hopelessness", "crisis_shown", "last_hope_t", "positive_count"].has(key):
			return false
	var lp = d.get("loops", [])
	if typeof(lp) != TYPE_ARRAY or lp.size() > MAX_LOOPS:
		return false
	for l in lp:
		if typeof(l) != TYPE_DICTIONARY or l.size() > 8:
			return false
		if typeof(l.get("topic")) != TYPE_STRING or not TOPICS.has(l["topic"]):
			return false
		if typeof(l.get("about")) != TYPE_STRING or String(l["about"]).length() > 64:
			return false
		if typeof(l.get("name", "")) != TYPE_STRING or String(l.get("name", "")).length() > 40:
			return false
		for key in ["strength"]:
			if typeof(l.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(l[key])) or float(l[key]) < 0.0 or float(l[key]) > 1.0:
				return false
		for key in ["start", "last"]:
			if typeof(l.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(l[key])):
				return false
	var h = d.get("hopelessness", 0.0)
	if typeof(h) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(h)) or float(h) < 0.0 or float(h) > 1.0:
		return false
	if d.has("crisis_shown") and typeof(d["crisis_shown"]) != TYPE_BOOL:
		return false
	if d.has("last_hope_t") and (typeof(d["last_hope_t"]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d["last_hope_t"]))):
		return false
	if d.has("positive_count") and (typeof(d["positive_count"]) not in [TYPE_FLOAT, TYPE_INT] or float(d["positive_count"]) < 0.0):
		return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	loops = []
	for l in d.get("loops", []):
		loops.append({"topic": String(l["topic"]), "about": String(l["about"]), "name": String(l.get("name", "")),
			"strength": float(l["strength"]), "start": float(l["start"]), "last": float(l["last"])})
	hopelessness = float(d.get("hopelessness", 0.0))
	crisis_shown = bool(d.get("crisis_shown", false))
	_last_hope_t = float(d.get("last_hope_t", -1.0e9))
	positive_count = int(d.get("positive_count", 0))
