extends RefCounted
## Obsedantně-kompulzivní smyčka (psychika E, 27. 10. 2026): obsese → nutkavá činnost → krátká úleva →
## posílení. Predispozice mind.predispositions.ocd (závažnost 0..1) a téma mind.ocd_theme (kontrolování,
## čistota, pořádek) – téma neurčuje povahu, jen to, čeho se pochybnost týká.
##
##   obsession – vtíravá pochybnost 0..1; spouštěče podle tématu (použitý sporák, večer, jídlo a kontakt,
##               narušený pořádek) a nejistota/stres; v nečinnosti se sama vrací tím rychleji, čím silnější
##               je naučený návyk
##   habit     – síla naučené smyčky 0..1: každá nutkavá činnost přinese krátkou úlevu, ale návyk posílí
##   resisted  – kolikrát postava nutkání odolala; odolání (postupná expozice) návyk oslabuje
## Nutkavou činnost volí jen AI za autonomní postavu; hráč ji může zrušit nebo zadat „odolat nutkání“.
## Nic se nevynucuje a žádná volba není dominantní: odolání krátce stojí napětí, rituál stojí čas a návyk.

const THEMES := ["checking", "contamination", "order"]
const COMPULSION_LABEL := {"checking": "Znovu kontroluje sporák a dveře", "contamination": "Znovu si důkladně myje ruce",
	"order": "Rovná a přerovnává věci"}
const THOUGHT := {"checking": ["Vypnul{g} jsem ten sporák?", "Zamkl{g} jsem? Radši se ještě podívám."],
	"contamination": ["Pořád mám na rukou něco špinavého.", "Co když jsem na sebe něco zanesl{g}?"],
	"order": ["Musí to být přesně srovnané, jinak to nejde.", "Něco tu není na svém místě."]}
const STATE_KEYS := ["obsession", "habit", "resisted", "rituals", "ritual_times", "last_evening"]

var severity := 0.0
var theme := "checking"
var obsession := 0.0
var habit := 0.0
var resisted := 0
var rituals := 0
var ritual_times: Array = []
var last_evening := -1


func is_empty() -> bool:
	return severity <= 0.0


func configure(sev: Variant, th: Variant, keep_state: bool) -> void:
	severity = clampf(float(sev), 0.0, 1.0) if typeof(sev) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(sev)) else 0.0
	theme = String(th) if typeof(th) == TYPE_STRING and THEMES.has(th) else "checking"
	if not keep_state:
		obsession = 0.0
		habit = 0.15 * severity
		resisted = 0
		rituals = 0
		ritual_times = []
		last_evening = -1


## Spouštěč z dat (akce, místo, večer). Vrací myšlenku nebo "".
func trigger(amount: float, k: float, rng: RandomNumberGenerator) -> String:
	if k <= 0.0 or severity <= 0.0 or amount <= 0.0:
		return ""
	obsession = clampf(obsession + amount * severity * k * (0.6 + habit), 0.0, 1.0)
	var pool: Array = THOUGHT[theme]
	return String(pool[rng.randi_range(0, pool.size() - 1)])


## Akce, po které se u daného tématu ozve pochybnost.
func trigger_for_action(action_id: String, tags: Array) -> float:
	match theme:
		"checking":
			return 0.45 if action_id == "cook" else 0.0
		"contamination":
			if action_id in ["snack", "cook"] or tags.has("social"):
				return 0.3
		"order":
			if tags.has("cooking") or tags.has("social"):
				return 0.2
	return 0.0


## Krok: vrací přírůstek stresu z nevyřešené obsese.
func tick(dm: float, ctx: Dictionary, k: float) -> float:
	if dm <= 0.0:
		return 0.0
	if k <= 0.0 or severity <= 0.0:
		obsession = 0.0
		return 0.0
	var sleeping := bool(ctx.get("sleeping", false))
	var busy := float(ctx.get("distraction", 0.0))
	# Pochybnost se v nečinnosti vrací (návyk), rozptýlení a spánek ji tlumí, nejistota a stres živí.
	var back := 0.0006 * severity * habit * (1.0 if not sleeping else 0.2)
	back += maxf(float(ctx.get("stress", 15.0)) - 55.0, 0.0) / 45.0 * 0.0004 * severity
	back += float(ctx.get("threat", 0.0)) * 0.0004 * severity
	var fade := 1.0 / 720.0 + busy / 240.0 + (1.0 / 180.0 if sleeping else 0.0)
	obsession = clampf(obsession + back * dm * (1.0 - obsession) - obsession * (1.0 - exp(-fade * dm)), 0.0, 1.0)
	habit = clampf(habit - dm / 43200.0 * 0.05, 0.05 * severity, 1.0)  # bez rituálů návyk velmi pomalu slábne
	if sleeping:
		return 0.0
	return obsession * 0.03 * dm * k


## Večerní kontrola (téma kontrolování): jednou za večer pochybnost, zda je všechno zavřené.
func evening(day: int, hour: int, k: float, rng: RandomNumberGenerator) -> String:
	if theme != "checking" or hour < 21 or day == last_evening:
		return ""
	last_evening = day
	return trigger(0.35, k, rng)


## Nutkavá činnost: krátká úleva, ale posílení návyku. Vrací úlevu ve stresu (záporně).
func on_ritual(now: float, k: float) -> float:
	var relief := obsession * 0.7
	obsession *= 0.3
	habit = clampf(habit + 0.05 * k, 0.0, 1.0)
	rituals += 1
	ritual_times.append(now)
	while ritual_times.size() > 16:
		ritual_times.pop_front()
	return -10.0 * relief * k


## Odolání nutkání (postupná expozice a prevence rituálu): krátké napětí teď, slabší smyčka potom.
func on_resist(k: float) -> float:
	var tension := 8.0 * obsession * k
	obsession *= 0.8
	habit = clampf(habit - 0.04 * k, 0.05 * severity, 1.0)
	resisted += 1
	return tension


func rituals_today(now: float) -> int:
	var n := 0
	for t in ritual_times:
		if now - float(t) < 1440.0:
			n += 1
	return n


## Brána autonomní volby: rituál až s pochybností, odolání až když je čemu odolávat.
func gate(kind: String) -> float:
	if severity <= 0.0:
		return 0.0
	if kind == "ritual":
		return obsession if obsession > 0.25 else 0.0
	if kind == "resist":
		return obsession if obsession > 0.2 else 0.0
	return 0.0


## Násobiče chuti: rituál táhne úměrně obsesi a návyku, odolání víc s pocitem zvládání a oporou.
func action_weight(act: Dictionary, k: float, mastery: float, support: float) -> float:
	if k <= 0.0 or severity <= 0.0:
		return 1.0
	match String(act.get("id", "")):
		"compulsion":
			return clampf(1.0 + 10.0 * obsession * (0.5 + habit) * k, 1.0, 8.0)
		"resist_urge":
			return clampf((0.3 + mastery + support) * (1.0 + 2.0 * obsession) * k, 0.2, 3.0)
	return 1.0


func mood_entries(k: float, now: float) -> Array:
	var out: Array = []
	if k <= 0.0 or severity <= 0.0:
		return out
	if obsession > 0.4:
		out.append({"id": "ocd_obsese", "label": "Nejde mi to z hlavy", "emotion": "uzkostny",
			"strength": -lerpf(4.0, 14.0, (obsession - 0.4) / 0.6) * k, "remaining": -1.0})
	if rituals_today(now) >= 5:
		out.append({"id": "ocd_cas", "label": "Smyčka mi bere spoustu času", "emotion": "nesvuj",
			"strength": -5.0 * k, "remaining": -1.0})
	return out


func private_lines(k: float) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0 or severity <= 0.0:
		return out
	if obsession > 0.4:
		out.append("Vtíravá pochybnost se vrací. Rituál uleví jen na chvíli; odolat je těžké, ale smyčku oslabuje.")
	return out


func to_dict() -> Dictionary:
	return {"obsession": obsession, "habit": habit, "resisted": resisted, "rituals": rituals,
		"ritual_times": ritual_times.duplicate(), "last_evening": last_evening}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 8:
		return false
	for key in d:
		if not STATE_KEYS.has(key):
			return false
	for key in ["obsession", "habit"]:
		if d.has(key) and (typeof(d[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[key])) or float(d[key]) < 0.0 or float(d[key]) > 1.0):
			return false
	for key in ["resisted", "rituals", "last_evening"]:
		if d.has(key):
			var value = d[key]
			if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
				return false
			var n := float(value)
			var lower := -1.0 if key == "last_evening" else 0.0
			if n < lower or n > 1.0e7 or n != floorf(n):
				return false
	var rt = d.get("ritual_times", [])
	if typeof(rt) != TYPE_ARRAY or rt.size() > 16:
		return false
	for t in rt:
		if typeof(t) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(t)):
			return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	obsession = float(d.get("obsession", 0.0))
	habit = float(d.get("habit", habit))
	resisted = int(d.get("resisted", 0))
	rituals = int(d.get("rituals", 0))
	ritual_times = (d.get("ritual_times", []) as Array).duplicate()
	last_evening = int(d.get("last_evening", -1))
