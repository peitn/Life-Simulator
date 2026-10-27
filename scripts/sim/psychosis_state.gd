extends RefCounted
## Psychotické prožívání (psychika H, 27. 10. 2026) – respektující, bez stereotypů a NIKDY bez vazby na násilí.
##
## Predispozice mind.predispositions.psychosis (0..1) a sklony mind.psychosis (0..1): neobvyklé vjemy
## (hallucination), přesvědčení o ohrožení (persecutory), o výjimečném poslání (grandiose), vztahovačnost
## (reference) a výchozí náhled (insight, 0,5 = průměr).
##   activity   – míra psychotického prožívání 0..1; epizoda začíná nenápadně (prodrom), má průběh a odeznívá
##   conviction – jistota bludného přesvědčení 0..1 (roste s aktivitou a klesá s náhledem a oporou)
##   insight    – aktuální náhled: s aktivitou klesá, opora, spánek a odborná pomoc ho vracejí
## Spouštěče: ztráta spánku, extrémní stres, tlak některých látek (psychika F). Zotavení: spánek, klid,
## opora, vyhledání pomoci a čas. Vjemy a přesvědčení jsou soukromé (jen vlastník offline, popsané jako
## prožitek postavy); ostatní vidí jen chování (víc stažení, ostražitost). Účinky jsou omezené násobiče –
## sklon k hádkám, urážkám ani nátlaku se NIKDY nezvyšuje; hráč není nikdy zamčený.

const AXES := ["hallucination", "persecutory", "grandiose", "reference", "insight"]
const PERCEPTIONS := ["Slyší hlas, který komentuje, co dělá.", "Zahlédne v koutě pohyb, který tam nikdo jiný nevidí.",
	"Slyší své jméno, i když nikdo nemluví.", "Má pocit, že se věci kolem jemně posouvají."]
const BELIEF := {"persecutory": "Postava je přesvědčená, že ji někdo sleduje a chce jí ublížit.",
	"grandiose": "Postava je přesvědčená, že má výjimečné poslání.",
	"reference": "Postava má pocit, že zprávy a rozhovory kolem se týkají jí."}
const STATE_KEYS := ["activity", "target", "episode_left", "conviction", "insight_now", "sleep_debt", "perceptions",
	"episodes", "help_t"]

var severity := 0.0
var axes := {}
var activity := 0.0
var target := 0.0
var episode_left := 0.0
var conviction := 0.0
var insight_now := 0.5
var sleep_debt := 0.0
var perceptions: Array = []
var episodes := 0
var help_t := -1.0e9


func a(id: String) -> float:
	return float(axes.get(id, 0.5 if id == "insight" else 0.0))


func is_empty() -> bool:
	return severity <= 0.0 and activity <= 0.0


func configure(sev: Variant, ax: Variant, keep_state: bool) -> void:
	severity = clampf(float(sev), 0.0, 1.0) if typeof(sev) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(sev)) else 0.0
	axes = {}
	if typeof(ax) == TYPE_DICTIONARY:
		for id in ax:
			if AXES.has(id) and typeof(ax[id]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(ax[id])):
				axes[String(id)] = clampf(float(ax[id]), 0.0, 1.0)
	if not keep_state:
		activity = 0.0
		target = 0.0
		episode_left = 0.0
		conviction = 0.0
		insight_now = a("insight")
		sleep_debt = 0.0
		perceptions = []
		episodes = 0
		help_t = -1.0e9


## Druh přesvědčení: nejsilnější sklon (při shodě deterministicky podle pořadí).
func belief_kind() -> String:
	var best := ""
	var bv := 0.0
	for id in ["persecutory", "reference", "grandiose"]:
		if a(id) > bv:
			bv = a(id)
			best = id
	return best


## Krok. ctx: sleeping, night, stress, support, push (látky). k: full 1, muted 0,5 (bez vjemů a bludů), off 0.
func tick(dm: float, now: float, ctx: Dictionary, k: float, rng: RandomNumberGenerator) -> void:
	if dm <= 0.0:
		return
	var sleeping := bool(ctx.get("sleeping", false))
	if bool(ctx.get("night", false)) and not sleeping:
		sleep_debt = minf(sleep_debt + dm, 2880.0)
	elif sleeping:
		sleep_debt = maxf(sleep_debt - dm * 1.5, 0.0)
	else:
		sleep_debt = maxf(sleep_debt - dm * 0.1, 0.0)
	if k <= 0.0 or severity <= 0.0:
		activity *= exp(-dm / 120.0)
		conviction *= exp(-dm / 120.0)
		if activity < 0.01:
			activity = 0.0
			conviction = 0.0
		perceptions.clear()
		return
	var stress := float(ctx.get("stress", 15.0))
	var support := clampf(float(ctx.get("support", 0.0)), 0.0, 1.0)
	var push := clampf(float(ctx.get("push", 0.0)), 0.0, 1.0)
	var debt := clampf(sleep_debt / 600.0, 0.0, 1.0)
	if episode_left <= 0.0:
		var trig := 1.0 + 3.0 * debt + maxf(stress - 75.0, 0.0) / 8.0 + 4.0 * push
		var lam := severity * 0.03 * trig / 1440.0
		if rng.randf() < 1.0 - exp(-lam * dm):
			target = clampf((0.5 + 0.5 * severity) * rng.randf_range(0.7, 1.0), 0.0, 1.0)
			episode_left = rng.randf_range(3.0, 7.0) * 1440.0
			episodes += 1
	else:
		var rate := 1.0 + support + (0.6 if sleeping else 0.0) + (0.8 if now - help_t < 2880.0 else 0.0) - 0.7 * debt
		episode_left = maxf(episode_left - dm * maxf(rate, 0.2), 0.0)
		if episode_left <= 0.0:
			target = 0.0
	var t := target
	if k < 1.0:
		t = minf(t, 0.3)
	# Prodrom: nástup je pozvolný (den), odeznívání pomalejší.
	var tau := 1440.0 if t > activity else 2160.0 / (1.0 + support)
	activity = clampf(activity + (t - activity) * (1.0 - exp(-dm / tau)), 0.0, 1.0)
	# Náhled: s aktivitou klesá, opora a nedávná pomoc ho vracejí.
	var ins_t := clampf(a("insight") * (1.0 - 0.6 * activity) + 0.3 * support + (0.25 if now - help_t < 2880.0 else 0.0), 0.0, 1.0)
	insight_now += (ins_t - insight_now) * (1.0 - exp(-dm / 360.0))
	var kind := belief_kind()
	var conv_t := 0.0
	if kind != "" and k >= 1.0:
		conv_t = clampf(activity * a(kind) * (1.0 - 0.7 * insight_now) * (1.0 - 0.4 * support) * 1.5, 0.0, 1.0)
	conviction += (conv_t - conviction) * (1.0 - exp(-dm / 720.0))
	# Neobvyklé vjemy: soukromé, jen při plných tématech; hazard úměrný aktivitě a sklonu.
	if k >= 1.0 and activity > 0.3 and a("hallucination") > 0.0 and not sleeping:
		var lam_h := activity * a("hallucination") * 0.02
		if rng.randf() < 1.0 - exp(-lam_h * dm):
			perceptions.append({"t": now, "text": PERCEPTIONS[rng.randi_range(0, PERCEPTIONS.size() - 1)]})
			while perceptions.size() > 3:
				perceptions.pop_front()


func on_help(now: float) -> void:
	help_t = now
	episode_left *= 0.6
	conviction *= 0.8


## Násobiče chuti (omezené). Nikdy nezvyšují hádky, urážky ani nátlak.
func action_weight(act: Dictionary, k: float) -> float:
	if k <= 0.0 or activity <= 0.0:
		return 1.0
	var tags: Array = act.get("tags", [])
	var id := String(act.get("id", ""))
	if tags.has("pressure") or tags.has("mean"):
		return 1.0
	var m := 1.0
	var kind := belief_kind()
	if tags.has("social") and kind == "persecutory":
		m *= 1.0 - 0.4 * conviction
	if id == "confide":
		m *= 1.0 + 0.4 * insight_now * activity
	if id == "seek_help":
		m *= 1.0 + 1.5 * insight_now * activity
	if id == "watch_tv" and kind == "reference":
		m *= 1.0 - 0.5 * conviction
	if kind == "grandiose" and (tags.has("social") or tags.has("fun")):
		m *= 1.0 + 0.3 * conviction
	if tags.has("quiet") or tags.has("rest"):
		m *= 1.0 + 0.2 * activity
	return clampf(m, 0.4, 2.5)


func threat_add() -> float:
	var kind := belief_kind()
	if kind == "persecutory" or kind == "reference":
		return 0.25 * conviction
	return 0.05 * activity


func sleep_quality_mult() -> float:
	return 1.0 - 0.2 * activity


func help_need() -> float:
	return clampf(activity - 0.35, 0.0, 1.0) * (0.4 + insight_now)


func mood_entries(k: float) -> Array:
	var out: Array = []
	if k <= 0.0:
		return out
	if activity > 0.15 and activity < 0.4:
		out.append({"id": "ps_zvlastni", "label": "Svět je nějak zvláštní", "emotion": "nesvuj", "strength": -3.0 * k, "remaining": -1.0})
	elif activity >= 0.4:
		out.append({"id": "ps_nejistota", "label": "Nevím, čemu věřit", "emotion": "uzkostny", "strength": -8.0 * k, "remaining": -1.0})
	if belief_kind() == "grandiose" and conviction > 0.4:
		out.append({"id": "ps_poslani", "label": "Mám důležité poslání", "emotion": "energicky", "strength": 3.0, "remaining": -1.0})
	return out


## Soukromý popis pro vlastníka offline: prožitek postavy, ne fakt; s nabídkou pomoci.
func private_lines(k: float) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0 or activity <= 0.15:
		return out
	for p in perceptions:
		out.append(String(p["text"]) + " (vjem, který ostatní nevnímají)")
	var kind := belief_kind()
	if kind != "" and conviction > 0.3:
		out.append(String(BELIEF[kind]) + (" Napůl tuší, že to může být nemocí." if insight_now > 0.4 else ""))
	if activity > 0.35:
		out.append("Pomáhá spánek, klid, blízký člověk a odborná pomoc. Je to zdravotní stav, ne selhání.")
	return out


func to_dict() -> Dictionary:
	return {"activity": activity, "target": target, "episode_left": episode_left, "conviction": conviction,
		"insight_now": insight_now, "sleep_debt": sleep_debt, "perceptions": perceptions.duplicate(true),
		"episodes": episodes, "help_t": help_t}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 12:
		return false
	for key in d:
		if not STATE_KEYS.has(key):
			return false
	for key in ["activity", "target", "conviction", "insight_now"]:
		if d.has(key) and (typeof(d[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[key])) or float(d[key]) < 0.0 or float(d[key]) > 1.0):
			return false
	for key in ["episode_left", "sleep_debt", "episodes"]:
		if d.has(key) and (typeof(d[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[key])) or float(d[key]) < 0.0 or float(d[key]) > 1.0e7):
			return false
	if d.has("help_t") and (typeof(d["help_t"]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d["help_t"]))):
		return false
	var p = d.get("perceptions", [])
	if typeof(p) != TYPE_ARRAY or p.size() > 3:
		return false
	for x in p:
		if typeof(x) != TYPE_DICTIONARY or typeof(x.get("text")) != TYPE_STRING or not PERCEPTIONS.has(x["text"]) \
				or typeof(x.get("t")) not in [TYPE_FLOAT, TYPE_INT]:
			return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	activity = float(d.get("activity", 0.0))
	target = float(d.get("target", 0.0))
	episode_left = float(d.get("episode_left", 0.0))
	conviction = float(d.get("conviction", 0.0))
	insight_now = float(d.get("insight_now", a("insight")))
	sleep_debt = float(d.get("sleep_debt", 0.0))
	perceptions = (d.get("perceptions", []) as Array).duplicate(true)
	episodes = int(d.get("episodes", 0))
	help_t = float(d.get("help_t", -1.0e9))
