extends RefCounted
## Průběh nálady v čase (psychika C, 27. 10. 2026) – bipolární spektrum a dlouhodobě nízká nálada.
##
## Žádná „diagnóza“ ani přepínač typu: soukromé posuvníky mind.mood (0..1) popisují predispozici k průběhu:
##   bipolar_tendency  – sklon k epizodám zvýšené i snížené nálady (hazard epizody)
##   elevation_ceiling – kam až může zvýšená fáze vystoupat (nízko = jen hypomanie, vysoko = i mánie);
##                       tím se plynule liší „typ I“ a „typ II“ bez nálepky
##   cycling           – rychlejší a mělčí střídání (cyklotymní průběh): kratší, nižší, častější výkyvy
##   chronic_low       – trvale nízká nálada bez epizod (dystymní průběh) – „podlaha“ depresivní zátěže
##   sleep_sensitivity – jak silně ztráta spánku rozhoupe náladu
##
## Stav `pole` −1..1 se měří VŮČI VLASTNÍMU NORMÁLU postavy (0 = její obvyklé já, ne populační průměr),
## takže přirozeně energický člověk ani ADHD-like hyperaktivita (stálá, bez změny spánku) epizodu nespustí.
## Fáze: depresivní ↔ vyrovnaná ↔ hypomanická ↔ manická; mají časový průběh (nástup, trvání, odeznění),
## spouštěče (ztráta spánku, stres) a zotavení (pravidelný spánek, opora, klid). Zvýšená fáze: víc energie,
## menší potřeba spánku, víc chuti na lidi a rychlé zážitky, rychlejší řeč, podrážděnost a riskantnější
## volby – vše jen jako omezené násobiče. Depresivní fáze tlačí existující depresivní zátěž (Depression),
## takže se používá stávající stažení, anhedonie i zotavení. Hráčův příkaz se nikdy neodmítne.
## Herní komprese času jako u deprese: herní den ≈ týden prožitku.

const AXES := ["bipolar_tendency", "elevation_ceiling", "cycling", "chronic_low", "sleep_sensitivity"]
const STATES := ["euthymic", "hypomanic", "manic", "depressive"]
## Hranice fází (s hysterezí) a minimální doba nad hranicí, než se fáze „potvrdí“ (minuty herního času).
const HYPO_UP := 0.4
const HYPO_DOWN := 0.25
const MANIC_UP := 0.75
const MANIC_DOWN := 0.6
const DEP_UP := -0.45
const DEP_DOWN := -0.3
const CONFIRM_MINUTES := 720.0
## Hazard nové epizody za den při tendenci 1 a klidném stavu.
const EPISODE_PER_DAY := 0.12
const STATE_KEYS := ["pole", "target", "episode_left", "phase", "above_minutes", "sleep_debt",
	"episodes_up", "episodes_down", "peak"]

var axes := {}
## Stav (ukládá se).
var pole := 0.0
var target := 0.0
var episode_left := 0.0
var phase := "euthymic"
var above_minutes := 0.0
## Spánkový dluh v minutách (bdění v noci se počítá, spánek ho splácí).
var sleep_debt := 0.0
var episodes_up := 0
var episodes_down := 0
var peak := 0.0


func a(id: String) -> float:
	return float(axes.get(id, 0.0))


func is_empty() -> bool:
	return axes.is_empty()


func configure(mood: Variant, keep_state: bool) -> void:
	axes = {}
	if typeof(mood) == TYPE_DICTIONARY:
		for id in mood:
			if AXES.has(id) and typeof(mood[id]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(mood[id])):
				var v := clampf(float(mood[id]), 0.0, 1.0)
				if v > 0.0:
					axes[String(id)] = v
	if not keep_state:
		pole = 0.0
		target = 0.0
		episode_left = 0.0
		phase = "euthymic"
		above_minutes = 0.0
		sleep_debt = 0.0
		episodes_up = 0
		episodes_down = 0
		peak = 0.0


## Strop zvýšené fáze podle posuvníku a režimu (muted = jen mírná hypomanie, žádná mánie).
func ceiling(k: float) -> float:
	var c := lerpf(0.55, 1.0, a("elevation_ceiling")) * lerpf(1.0, 0.65, a("cycling"))
	if k < 1.0:
		c = minf(c, 0.5)
	return c * k


## Podlaha depresivní zátěže u trvale nízké nálady (pod prahem epizody 0,6 → dlouhodobá skleslost).
func chronic_floor(k: float) -> float:
	var c := a("chronic_low")
	if c <= 0.0 or k <= 0.0:
		return 0.0
	return (0.22 + 0.25 * c) * k


func elevation() -> float:
	return maxf(pole, 0.0)


func depressive() -> float:
	return maxf(-pole, 0.0)


## Podrážděnost ve zvýšené fázi (víc pod stresem a v mánii) 0..1.
func irritability(stress: float) -> float:
	var e := elevation()
	if e <= 0.2:
		return 0.0
	return clampf((e - 0.2) * (0.6 + stress / 100.0), 0.0, 1.0)


## Krok. ctx: sleeping, night, stress (0..100), support (0..1). rng = vlastní RNG rozšíření.
func tick(dm: float, ctx: Dictionary, k: float, rng: RandomNumberGenerator) -> void:
	if dm <= 0.0:
		return
	var sleeping := bool(ctx.get("sleeping", false))
	var night := bool(ctx.get("night", false))
	if night and not sleeping:
		sleep_debt = minf(sleep_debt + dm, 2880.0)
	elif sleeping:
		sleep_debt = maxf(sleep_debt - dm * 1.5, 0.0)
	else:
		sleep_debt = maxf(sleep_debt - dm * 0.1, 0.0)
	if k <= 0.0 or axes.is_empty():
		pole *= exp(-dm / 240.0)
		target = 0.0
		_update_phase(dm, k)
		return
	var tend := a("bipolar_tendency")
	var cyc := a("cycling")
	var stress := float(ctx.get("stress", 15.0))
	var support := float(ctx.get("support", 0.0))
	var debt := clampf(sleep_debt / 600.0, 0.0, 1.0)
	# Nová epizoda: hazard 1 − e^(−λ·dm), spouštěče zvyšují λ. Směr: ztráta spánku táhne nahoru, stres
	# a vyčerpání spíš dolů.
	if (tend > 0.0 or cyc > 0.0) and episode_left <= 0.0:
		var trig := 1.0 + 2.5 * debt * (0.4 + a("sleep_sensitivity")) + maxf(stress - 50.0, 0.0) / 40.0
		var lam := (tend + 0.8 * cyc) * EPISODE_PER_DAY * (1.0 + 2.0 * cyc) * trig / 1440.0
		if rng.randf() < 1.0 - exp(-lam * dm):
			var p_up := clampf(0.5 + 0.35 * debt - maxf(stress - 50.0, 0.0) / 150.0, 0.15, 0.85)
			var depth := rng.randf_range(0.6, 1.0)
			if rng.randf() < p_up:
				target = ceiling(k) * depth
			else:
				target = -lerpf(0.55, 1.0, tend) * lerpf(1.0, 0.6, cyc) * depth * (1.0 if k >= 1.0 else 0.6)
			# Trvání: dny (herní komprese); rychlé cyklování = kratší.
			episode_left = rng.randf_range(1440.0, 4320.0) * lerpf(1.0, 0.4, cyc)
	if episode_left > 0.0:
		# Pravidelný spánek a opora epizodu zkracují, spánkový dluh prodlužuje.
		var rate := 1.0 + 0.8 * support + (0.5 if sleeping else 0.0) - 0.6 * debt
		episode_left = maxf(episode_left - dm * maxf(rate, 0.2), 0.0)
		if episode_left <= 0.0:
			target = 0.0
	# Spánkový dluh v zvýšené fázi tlačí výš (začarovaný kruh), spánek a opora tlumí.
	var t := target
	if t > 0.0:
		t = minf(t + 0.2 * debt * a("sleep_sensitivity"), ceiling(k))
	# Povzbuzující látka během účinku táhne náladu nahoru (psychika F), nanejvýš ke stropu.
	var push := float(ctx.get("push", 0.0))
	if push > 0.0:
		t = minf(maxf(t, 0.0) + push * maxf(a("bipolar_tendency"), 0.3), ceiling(k))
	var tau := 360.0 if absf(t) > absf(pole) else 600.0 / (1.0 + support)
	pole += (t - pole) * (1.0 - exp(-dm / tau))
	pole = clampf(pole, -1.0, 1.0)
	peak = maxf(peak, pole)
	_update_phase(dm, k)


func _update_phase(dm: float, k: float) -> void:
	var cand := phase
	match phase:
		"euthymic":
			if pole > HYPO_UP or pole < DEP_UP:
				above_minutes += dm
				if above_minutes >= CONFIRM_MINUTES:
					cand = "hypomanic" if pole > 0.0 else "depressive"
			else:
				above_minutes = 0.0
		"hypomanic":
			if pole > MANIC_UP and k >= 1.0:
				above_minutes += dm
				if above_minutes >= CONFIRM_MINUTES * 2.0:
					cand = "manic"
			elif pole < HYPO_DOWN:
				cand = "euthymic"
		"manic":
			if pole < MANIC_DOWN:
				cand = "hypomanic"
		"depressive":
			if pole > DEP_DOWN:
				cand = "euthymic"
	if cand != phase:
		if phase == "euthymic" and cand == "hypomanic":
			episodes_up += 1
		elif phase == "euthymic" and cand == "depressive":
			episodes_down += 1
		phase = cand
		above_minutes = 0.0


## Násobič úbytku energie (zvýšená fáze: méně únavy).
func energy_mult(k: float) -> float:
	return 1.0 - 0.4 * k * elevation()


## Spánek osvěží rychleji (menší potřeba spánku).
func sleep_rate_mult(k: float) -> float:
	return 1.0 + 0.5 * k * elevation()


func action_weight(act: Dictionary, hour: int, k: float) -> float:
	var e := elevation()
	if k <= 0.0 or e <= 0.0:
		return 1.0
	var tags: Array = act.get("tags", [])
	var m := 1.0
	if tags.has("sleep") and (hour >= 22 or hour < 6):
		m *= 1.0 - 0.55 * k * e
	elif tags.has("rest") or tags.has("quiet"):
		m *= 1.0 - 0.4 * k * e
	if tags.has("social") and not tags.has("pressure"):
		m *= 1.0 + 0.6 * k * e
	if tags.has("fun") or tags.has("exercise"):
		m *= 1.0 + 0.4 * k * e
	if tags.has("coping_unhealthy"):
		m *= 1.0 + 0.8 * k * e
	return clampf(m, 0.35, 2.0)


## Posun šance na dobrý rozhovor: zvýšená fáze víc kontaktu, ale podrážděnost riskuje hádku.
func talk_bias(stress: float, k: float) -> float:
	if k <= 0.0:
		return 0.0
	return -0.12 * k * irritability(stress)


const LINES_UP := ["Mám skvělý nápad, poslouchej!", "Dneska bych zvládl(a) cokoli.",
	"Počkej, ještě jedna věc… a pak další!", "Kdo potřebuje spát, když je tolik práce?"]


func mood_entries(k: float, stress: float) -> Array:
	var out: Array = []
	if k <= 0.0:
		return out
	match phase:
		"hypomanic":
			out.append({"id": "mc_nahore", "label": "Plno energie a nápadů", "emotion": "energicky",
				"strength": 6.0 * k, "remaining": -1.0})
		"manic":
			out.append({"id": "mc_nahore", "label": "Myšlenky letí, nedá se zastavit", "emotion": "energicky",
				"strength": 2.0 * k, "remaining": -1.0})
	if irritability(stress) > 0.3:
		out.append({"id": "mc_podrazdeny", "label": "Všechno je moc pomalé", "emotion": "nastvany",
			"strength": -6.0 * k, "remaining": -1.0})
	return out


## Soukromý slovní popis (výklad je jen pro vlastníka, bez čísel).
func private_lines(k: float) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0:
		return out
	match phase:
		"hypomanic":
			out.append("Nálada a energie jsou výš než moje obvyklé já (hypomanická fáze). Pomáhá pravidelný spánek.")
		"manic":
			out.append("Nálada je velmi vystupňovaná (manická fáze) – je dobré říct si o pomoc a hlídat spánek.")
		"depressive":
			out.append("Nálada je níž než obvykle (depresivní fáze průběhu).")
	if a("chronic_low") > 0.0 and k > 0.0 and phase == "euthymic":
		out.append("Dlouhodobě spíš nízká nálada – dny bývají šedé, ale dá se s tím žít a hledat oporu.")
	return out


func to_dict() -> Dictionary:
	return {"pole": pole, "target": target, "episode_left": episode_left, "phase": phase,
		"above_minutes": above_minutes, "sleep_debt": sleep_debt, "episodes_up": episodes_up,
		"episodes_down": episodes_down, "peak": peak}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 16:
		return false
	for key in d:
		if not STATE_KEYS.has(key):
			return false
	if d.has("phase") and (typeof(d["phase"]) != TYPE_STRING or not STATES.has(d["phase"])):
		return false
	for key in ["pole", "target", "peak"]:
		if d.has(key) and (typeof(d[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[key])) or absf(float(d[key])) > 1.0):
			return false
	for key in ["episode_left", "above_minutes", "sleep_debt", "episodes_up", "episodes_down"]:
		if d.has(key) and (typeof(d[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[key])) or float(d[key]) < 0.0 or float(d[key]) > 1.0e7):
			return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	pole = float(d.get("pole", 0.0))
	target = float(d.get("target", 0.0))
	episode_left = float(d.get("episode_left", 0.0))
	phase = String(d.get("phase", "euthymic"))
	above_minutes = float(d.get("above_minutes", 0.0))
	sleep_debt = float(d.get("sleep_debt", 0.0))
	episodes_up = int(d.get("episodes_up", 0))
	episodes_down = int(d.get("episodes_down", 0))
	peak = float(d.get("peak", 0.0))
