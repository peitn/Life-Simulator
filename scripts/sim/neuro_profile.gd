extends RefCounted
## Neurodivergentní profil postavy (psychika A, 27. 10. 2026) – soukromé CharacterData.mind.neuro.
##
## Každá osa je samostatný spojitý posuvník 0..1 (0 = bez výrazné odlišnosti). Žádná diagnóza ani
## šablona: „ADHD“ nebo „autismus“ tu nejsou přepínače, ale kombinace os, takže dvě postavy se stejnou
## nálepkou se chovají měřitelně jinak (test rozmanitosti). Silné stránky (hyperfokus, hloubka zájmu,
## přímost) jsou osy stejně jako obtíže.
##
##   ADHD-like:  attention_drift, working_memory, task_initiation, action_impulsivity, hyperfocus, time_blindness
##   autistické: sens_sound / sens_light / sens_touch (citlivost po kanálech), social_energy, interest_depth
##               (+ interest_focus), direct_communication, masking_cost; potřeba rutiny = existující
##               dispozice D.predictability_need (nezdvojuje se, jen tady dostává živého spotřebitele)
##   další:      tic_tendency, reading_effort
##
## Zásady: všechny účinky jsou spojité násobiče nákladů, chuti a rychlostí (žádná binární brána), jsou
## omezené (žádná volba se nezakáže) a škálují se režimem obsahu k (full 1, muted 0,5, off 0 = beze změny).
## Hráčův příkaz se nikdy neodmítne: obtížné zahájení jen „stojí víc“ (zrušitelné váhání), roztěkanost
## a hyperfokus mění jen autonomní akce. Modul je čistý (bez uzlů) a deterministický (RNG mu dává volající).

const Schema := preload("res://scripts/character/character_schema.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

## Kam směřuje hluboký zájem: tagy nebo id akcí, které ho naplňují.
const INTEREST_MATCH := {
	"reading": {"tags": ["reading"], "ids": []},
	"cooking": {"tags": ["cooking"], "ids": []},
	"exercise": {"tags": ["exercise"], "ids": []},
	"screens": {"tags": [], "ids": ["watch_tv"]},
	"nature": {"tags": [], "ids": ["go_walk"]},
}
## Povinnosti, u kterých se projeví obtížné zahájení (zábava a zájem ne).
const CHORE_TAGS := ["cooking", "hygiene", "exercise", "repair"]
## Přetížení nad tímto prahem přidává stres a táhne do klidu.
const OVERLOAD_STRESS_FROM := 0.5
const STATE_KEYS := ["social_battery", "masking_load", "overload", "interest_last", "tic_count", "tic_cd"]

var axes := {}
var interest := "reading"
## Ručně nastavená dispozice mind.dispositions.predictability_need (0,5 = průměr → žádný vliv). Odvozená D
## z rysů se tu záměrně nebere: dřív neměla živého spotřebitele a výchozí postavy se nesmí změnit.
var predictability := 0.5

# --- dynamický stav (ukládá se)
## Sociální „baterka“ 1 = plná. Vybíjí ji jen osa social_energy, dobíjí samota a klid.
var social_battery := 1.0
## Únava z přizpůsobování se (maskování) – roste po hovorech s ne-blízkými lidmi.
var masking_load := 0.0
## Smyslové přetížení 0..1 – sčítá se z hluku, tlačenice a jasu podle citlivosti kanálů.
var overload := 0.0
var interest_last := -1.0e9
var tic_count := 0
var tic_cd := 0.0


func a(id: String) -> float:
	return float(axes.get(id, 0.0))


func is_empty() -> bool:
	return axes.is_empty() and absf(predictability - 0.5) < 1e-6


## explicit_d = mind.dispositions (jen ručně nastavené osy).
func configure(neuro: Variant, focus: Variant, explicit_d: Dictionary, keep_state: bool) -> void:
	axes = {}
	if typeof(neuro) == TYPE_DICTIONARY:
		for id in neuro:
			if Schema.NEURO_SLIDERS.has(id) and typeof(neuro[id]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(neuro[id])):
				var v := clampf(float(neuro[id]), 0.0, 1.0)
				if v > 0.0:
					axes[String(id)] = v
	interest = String(focus) if typeof(focus) == TYPE_STRING and INTEREST_MATCH.has(focus) else "reading"
	var pn = explicit_d.get("predictability_need", 0.5)
	predictability = clampf(float(pn), 0.0, 1.0) if typeof(pn) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(pn)) else 0.5
	if not keep_state:
		social_battery = 1.0
		masking_load = 0.0
		overload = 0.0
		interest_last = -1.0e9
		tic_count = 0
		tic_cd = 0.0


## Odchylka potřeby předvídatelnosti nad průměr (0..1); pod průměrem nic (flexibilita není trest).
func routine_need() -> float:
	return clampf((predictability - 0.5) * 2.0, 0.0, 1.0)


func is_interest(act: Dictionary) -> bool:
	var m: Dictionary = INTEREST_MATCH.get(interest, {})
	if (m.get("ids", []) as Array).has(String(act.get("id", ""))):
		return true
	for t in act.get("tags", []):
		if (m.get("tags", []) as Array).has(t):
			return true
	return false


static func _is_chore(act: Dictionary) -> bool:
	for t in act.get("tags", []):
		if CHORE_TAGS.has(t):
			return true
	return false


## Citlivost kanálu (0..1) – pro přetížení a SensoryProfile.
func channel(name: String) -> float:
	match name:
		"noise": return a("sens_sound")
		"bright_light": return a("sens_light")
		"crowd", "touch": return a("sens_touch")
	return 0.0


## Zisky kanálů pro SensoryProfile (násobí jeho sensory_factor). Prázdné = beze změny.
func channel_gains(k: float) -> Dictionary:
	var g := {}
	if k <= 0.0:
		return g
	if a("sens_sound") > 0.0:
		g["noise"] = 0.8 * k * a("sens_sound")
	if a("sens_light") > 0.0:
		g["bright_light"] = 0.8 * k * a("sens_light")
	if a("sens_touch") > 0.0:
		g["crowd"] = 0.6 * k * a("sens_touch")
		g["touch"] = 0.8 * k * a("sens_touch")
	return g


## Násobič chuti na akci pro utility AI (0,35..2). Všechny osy na 0 → přesně 1,0.
func action_weight(act: Dictionary, hour: int, k: float) -> float:
	if k <= 0.0 or (axes.is_empty() and overload <= 0.0):
		return 1.0
	var tags: Array = act.get("tags", [])
	var id := String(act.get("id", ""))
	var m := 1.0
	var interest_act := is_interest(act)
	var eff := ActionLibrary.effort(act)
	if _is_chore(act) and not interest_act:
		m *= 1.0 - 0.45 * k * a("task_initiation") * eff
	if interest_act:
		m *= 1.0 + 0.9 * k * a("interest_depth") + 0.3 * k * a("hyperfocus")
	elif tags.has("quiet") or tags.has("reading"):
		m *= 1.0 - 0.3 * k * a("attention_drift")
	if tags.has("fun"):
		m *= 1.0 + 0.25 * k * a("action_impulsivity") + 0.15 * k * a("attention_drift")
	if tags.has("coping_unhealthy"):
		m *= 1.0 + 0.3 * k * a("action_impulsivity")
	if tags.has("reading") or id == "journal":
		m *= 1.0 - 0.35 * k * a("reading_effort")
	var social := tags.has("social") and not tags.has("pressure")
	var drained := clampf(a("social_energy") * (1.0 - social_battery) + a("masking_cost") * masking_load, 0.0, 1.0)
	if social:
		m *= 1.0 - 0.5 * k * drained
		m *= 1.0 - 0.4 * k * overload
	elif tags.has("quiet") or tags.has("rest") or id == "hide":
		m *= 1.0 + 0.4 * k * drained + 0.6 * k * overload
	if id == "watch_tv":
		m *= 1.0 - 0.4 * k * overload * a("sens_sound")
	if tags.has("sleep") and (hour >= 22 or hour < 6):
		m *= 1.0 - 0.35 * k * a("time_blindness")
	return clampf(m, 0.35, 2.0)


## Výběr partnera: maskování dělá cizí a vzdálenější lidi náročnějšími (blízcí ne).
func target_weight(rel: float, act: Dictionary, k: float) -> float:
	if k <= 0.0 or a("masking_cost") <= 0.0 or not (act.get("tags", []) as Array).has("social"):
		return 1.0
	var distance := clampf(1.0 - rel / 60.0, 0.0, 1.0)
	return clampf(1.0 - 0.25 * k * a("masking_cost") * distance, 0.7, 1.0)


## Délka autonomní akce: hyperfokus a časová slepota ji natáhnou, pracovní paměť prodlouží vaření.
## Hráčem zadané akce se nemění (hráč rozhoduje sám).
func duration_mult(act: Dictionary, by_player: bool, k: float) -> float:
	if by_player or k <= 0.0 or axes.is_empty():
		return 1.0
	var tags: Array = act.get("tags", [])
	if tags.has("sleep") or tags.has("social") or bool(act.get("involuntary", false)) or bool(act.get("system", false)):
		return 1.0
	var m := 1.0
	if is_interest(act):
		m *= 1.0 + 0.6 * k * a("hyperfocus")
	elif tags.has("fun"):
		m *= 1.0 + 0.3 * k * a("hyperfocus")
	if tags.has("fun") or is_interest(act):
		m *= 1.0 + 0.25 * k * a("time_blindness")
	if tags.has("cooking"):
		m *= 1.0 + 0.3 * k * a("working_memory")
	return clampf(m, 1.0, 2.2)


## Hazard (za minutu), že autonomní soustředěná činnost „vyšumí“ (roztěkanost). Zájem a hyperfokus chrání.
func drift_hazard(act: Dictionary, by_player: bool, elapsed: float, k: float) -> float:
	if by_player or k <= 0.0 or a("attention_drift") <= 0.0 or elapsed < 8.0 or is_interest(act):
		return 0.0
	var tags: Array = act.get("tags", [])
	if not (tags.has("quiet") or tags.has("reading") or tags.has("cooking") or tags.has("fun")):
		return 0.0
	if tags.has("sleep") or tags.has("social") or bool(act.get("involuntary", false)) or not bool(act.get("interruptible", true)):
		return 0.0
	return 0.012 * k * a("attention_drift") * (1.0 - 0.6 * a("hyperfocus"))


## Bariéra zahájení pro hráčův příkaz (0..0,6) – jen u povinností; vede k zrušitelnému váhání, ne k odmítnutí.
func initiation_barrier(act: Dictionary, k: float) -> float:
	if k <= 0.0 or a("task_initiation") <= 0.0 or not _is_chore(act) or is_interest(act):
		return 0.0
	return clampf(0.6 * k * a("task_initiation") * ActionLibrary.effort(act), 0.0, 0.6)


## Šance na dobrý rozhovor: přímost u cizích lidí víc nedorozumění, u blízkých oceněná upřímnost.
func talk_bias(rel: float, k: float) -> float:
	var d := a("direct_communication")
	if k <= 0.0 or d <= 0.0:
		return 0.0
	if rel >= 50.0:
		return 0.03 * k * d
	if rel < 20.0:
		return -0.04 * k * d * clampf((20.0 - rel) / 40.0 + 0.5, 0.5, 1.0)
	return 0.0


## Přímý člověk výtku spolkne méně často (řekne ji, a tím se dá vyřešit).
func swallow_mult(k: float) -> float:
	return 1.0 - 0.5 * k * a("direct_communication")


## Dokončený rozhovor: sociální baterka, maskování. Vrací {"energy": Δ, "stress": Δ}.
func on_social_finished(rel: float, k: float) -> Dictionary:
	var out := {"energy": 0.0, "stress": 0.0}
	if k <= 0.0 or axes.is_empty():
		return out
	var se := a("social_energy")
	if se > 0.0:
		out["energy"] = -6.0 * k * se * (0.5 + (1.0 - social_battery))
		social_battery = clampf(social_battery - 0.25 * k * se, 0.0, 1.0)
	var mc := a("masking_cost")
	if mc > 0.0 and rel < 60.0:
		var dist := clampf(1.0 - rel / 60.0, 0.0, 1.0)
		masking_load = clampf(masking_load + 0.3 * k * mc * dist, 0.0, 1.0)
		out["stress"] = 4.0 * k * mc * dist
	return out


## Smyslová zátěž z hluku / tlačenice / jasu (amount ≈ síla podnětu 0..3).
func on_sensory(name: String, amount: float, k: float) -> void:
	var c := channel(name)
	if k <= 0.0 or c <= 0.0 or amount <= 0.0 or not is_finite(amount):
		return
	overload = clampf(overload + 0.08 * k * c * amount, 0.0, 1.0)


## Dokončená činnost hlubokého zájmu: regulace (silná stránka). Vrací úlevu ve stresu (záporné číslo).
func on_interest_finished(now: float, k: float) -> float:
	interest_last = now
	var d := a("interest_depth")
	if k <= 0.0 or d <= 0.0:
		return 0.0
	overload = clampf(overload - 0.3 * k * d, 0.0, 1.0)
	social_battery = clampf(social_battery + 0.15 * k * d, 0.0, 1.0)
	return -8.0 * k * d


## Krok. ctx: sleeping, social (právě v rozhovoru), quiet (klidná činnost), stress, others_near.
## Vrací {"stress": Δ, "tic": bool}.
func tick(dm: float, ctx: Dictionary, k: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"stress": 0.0, "tic": false}
	if dm <= 0.0:
		return out
	var sleeping := bool(ctx.get("sleeping", false))
	var social_now := bool(ctx.get("social", false))
	var calm := sleeping or bool(ctx.get("quiet", false))
	if not social_now:
		var rate := (2.0 if sleeping else (1.5 if calm else 1.0)) / 360.0
		social_battery = clampf(social_battery + rate * dm, 0.0, 1.0)
	masking_load *= exp(-dm / (120.0 if calm else 240.0))
	overload *= exp(-dm / (30.0 if sleeping else (45.0 if calm else 90.0)))
	if k <= 0.0:
		return out
	if overload > OVERLOAD_STRESS_FROM and not sleeping:
		out["stress"] = (overload - OVERLOAD_STRESS_FROM) * 0.05 * dm * k
	var tic := a("tic_tendency")
	tic_cd = maxf(tic_cd - dm, 0.0)
	if tic > 0.0 and not sleeping and tic_cd <= 0.0:
		var stress := float(ctx.get("stress", 15.0))
		var lam := 0.004 * k * tic * (0.4 + stress / 60.0 + overload)
		if rng.randf() < 1.0 - exp(-lam * dm):
			tic_count += 1
			tic_cd = 30.0
			out["tic"] = true
	return out


## Moodlety (slova, žádná čísla). now = herní minuty.
func mood_entries(now: float, k: float) -> Array:
	var out: Array = []
	if k <= 0.0:
		return out
	if overload > 0.45:
		out.append({"id": "nd_pretizeni", "label": "Smyslové přetížení", "emotion": "napjaty",
			"strength": -lerpf(6.0, 16.0, clampf((overload - 0.45) / 0.55, 0.0, 1.0)) * k, "remaining": -1.0})
	if a("social_energy") > 0.0 and social_battery < 0.3:
		out.append({"id": "nd_baterka", "label": "Sociální baterka je vybitá", "emotion": "unaveny",
			"strength": -lerpf(3.0, 9.0, (0.3 - social_battery) / 0.3) * k, "remaining": -1.0})
	if masking_load > 0.5:
		out.append({"id": "nd_maskovani", "label": "Únava z přizpůsobování se", "emotion": "unaveny",
			"strength": -6.0 * k, "remaining": -1.0})
	var d := a("interest_depth")
	if d > 0.3 and now - interest_last > 2880.0:
		out.append({"id": "nd_zajem", "label": "Chybí mi můj zájem", "emotion": "znudeny",
			"strength": -4.0 * d * k, "remaining": -1.0})
	return out


## Slovní soukromý popis (vidí jen vlastník offline; žádná čísla, žádné diagnózy).
func private_lines(k: float) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0:
		return out
	if overload > 0.45:
		out.append("Smyslů je na mě moc – pomůže klid a ticho.")
	if a("social_energy") > 0.0 and social_battery < 0.3:
		out.append("Na lidi teď nemám energii, potřebuju chvíli o samotě.")
	if masking_load > 0.5:
		out.append("Přizpůsobování se mě dnes hodně stálo.")
	return out


func to_dict() -> Dictionary:
	return {"social_battery": social_battery, "masking_load": masking_load, "overload": overload,
		"interest_last": interest_last, "tic_count": tic_count, "tic_cd": tic_cd}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 16:
		return false
	for k in d:
		if not STATE_KEYS.has(k) or typeof(d[k]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[k])):
			return false
	for k in ["social_battery", "masking_load", "overload"]:
		if d.has(k) and (float(d[k]) < 0.0 or float(d[k]) > 1.0):
			return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	social_battery = clampf(float(d.get("social_battery", 1.0)), 0.0, 1.0)
	masking_load = clampf(float(d.get("masking_load", 0.0)), 0.0, 1.0)
	overload = clampf(float(d.get("overload", 0.0)), 0.0, 1.0)
	interest_last = clampf(float(d.get("interest_last", -1.0e9)), -1.0e12, 1.0e12)
	tic_count = clampi(int(d.get("tic_count", 0)), 0, 1000000)
	tic_cd = clampf(float(d.get("tic_cd", 0.0)), 0.0, 1440.0)
