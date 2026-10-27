extends RefCounted
## Psychoaktivní látky a závislosti (psychika F, 27. 10. 2026) – abstraktní herní kategorie.
##
## Žádné reálné dávkování, příprava, způsob užití ani kombinace: akce je jen „dá si / užije X“ s herním
## jménem a model pracuje se stavem, ne s množstvím. Bez glorifikace: radost z užití je skromná a s tolerancí
## klesá, kdežto následky (spánek, nálada, čas, peníze jako starost, vztahy, abstinenční nepohodlí,
## relapsy) jsou modelované vždy. Cesta ven existuje: omezit, svěřit se, vyhledat pomoc, čas a opora.
##
## Pro každou kategorii:
##   craving (wanting)   – chuť 0..1; roste s odstupem od užití úměrně závislosti a s podněty (stres, denní
##                         doba, ostatní, kteří užívají); po užití klesne
##   liking              – prožitá libost = základ × (1 − 0,7 × tolerance)
##   tolerance           – roste s užíváním, pomalu mizí
##   dependence          – pomalá závislost 0..1 podle četnosti × náchylnosti (predispozice „addiction“ a
##                         zvyk); „jizva“ po zotavení zrychluje relaps
##   withdrawal          – nepohodlí, když je závislost a od užití uplynula doba (podle kategorie)
## Behaviorální závislosti (hraní, sázení) jdou stejným modelem bez tolerance látky.
## Zvyk (mind.substances, 0..1) říká, jak moc postava danou věc běžně dělá; 0 = AI ji sama nezačne
## (hráč ji zadat může, je-li obsah povolen). Režim obsahu: muted = poloviční dynamika, off = nic.

## [herní popis, libost, rychlost závislosti, nástup abstinence (min), tolerance/užití, účinek (min),
##  zhoršení spánku při užití před spaním, propad po účinku, „peníze“ (starost), obava blízkých,
##  podráždění při abstinenci, popis abstinence, tlak na psychotické prožívání, tlak na náladu nahoru]
const DEFS := {
	"caffeine": {"label": "káva", "pleasure": 3.0, "dep_rate": 0.012, "onset": 900.0, "tol": 0.03, "effect": 180.0,
		"sleep": 0.15, "crash": 0.0, "cost": 0.0, "concern": 0.0, "irritable": 0.2,
		"withdrawal": "Bez kafe mě bolí hlava a nemůžu se probrat", "psychosis": 0.0, "elevate": 0.0},
	"nicotine": {"label": "cigareta", "pleasure": 4.0, "dep_rate": 0.035, "onset": 300.0, "tol": 0.04, "effect": 60.0,
		"sleep": 0.05, "crash": 0.0, "cost": 0.2, "concern": 0.15, "irritable": 0.5,
		"withdrawal": "Chce se mi cigareta a všechno mě štve", "psychosis": 0.0, "elevate": 0.0},
	"alcohol": {"label": "alkohol", "pleasure": 0.0, "dep_rate": 0.02, "onset": 960.0, "tol": 0.0, "effect": 0.0,
		"sleep": 0.0, "crash": 0.0, "cost": 0.2, "concern": 0.3, "irritable": 0.4,
		"withdrawal": "Bez pití se mi třesou ruce a nemůžu se uklidnit", "psychosis": 0.0, "elevate": 0.0},
	"sedative": {"label": "Mlha", "pleasure": 6.0, "dep_rate": 0.02, "onset": 720.0, "tol": 0.05, "effect": 240.0,
		"sleep": -0.1, "crash": 0.0, "cost": 0.3, "concern": 0.4, "irritable": 0.4,
		"withdrawal": "Nemůžu se zklidnit a špatně spím", "psychosis": 0.15, "elevate": 0.0},
	"stimulant": {"label": "Jiskra", "pleasure": 8.0, "dep_rate": 0.05, "onset": 480.0, "tol": 0.07, "effect": 240.0,
		"sleep": 0.4, "crash": 8.0, "cost": 0.6, "concern": 0.6, "irritable": 0.6,
		"withdrawal": "Prázdnota a únava, nic nemá barvu", "psychosis": 0.4, "elevate": 0.25},
	"painkiller": {"label": "Útlum", "pleasure": 7.0, "dep_rate": 0.06, "onset": 600.0, "tol": 0.07, "effect": 300.0,
		"sleep": 0.0, "crash": 3.0, "cost": 0.5, "concern": 0.6, "irritable": 0.5,
		"withdrawal": "Všechno bolí a nemůžu spát", "psychosis": 0.0, "elevate": 0.0},
	"gaming": {"label": "hraní", "pleasure": 5.0, "dep_rate": 0.02, "onset": 1440.0, "tol": 0.02, "effect": 0.0,
		"sleep": 0.15, "crash": 0.0, "cost": 0.1, "concern": 0.2, "irritable": 0.3,
		"withdrawal": "Myslím jen na to, kdy si zase zahraju", "psychosis": 0.0, "elevate": 0.0},
	"gambling": {"label": "sázení", "pleasure": 6.0, "dep_rate": 0.04, "onset": 1440.0, "tol": 0.03, "effect": 0.0,
		"sleep": 0.05, "crash": 2.0, "cost": 1.0, "concern": 0.5, "irritable": 0.4,
		"withdrawal": "Musím to vyhrát zpátky", "psychosis": 0.0, "elevate": 0.0},
}
const IDS := ["caffeine", "nicotine", "alcohol", "sedative", "stimulant", "painkiller", "gaming", "gambling"]
const STATE_KEYS := ["s", "cut_until", "money_worry", "psychosis_push"]

## Zvyk 0..1 (mind.substances) a náchylnost k závislosti (predispozice addiction).
var habit := {}
var susceptibility := 0.0
## Stav po kategoriích: {id: {craving, tolerance, dependence, last, effect_left, scar, uses: [t…]}}.
var s := {}
## Rozhodnutí omezit (do herní minuty): chuť táhne méně, abstinence je citelnější.
var cut_until := -1.0e9
## Starost o peníze (abstraktně, bez rozpočtu) 0..1 – sázení a drahé látky.
var money_worry := 0.0
## Tlak na psychotické prožívání z některých látek (čte psychika H) 0..1.
var psychosis_push := 0.0


func is_empty() -> bool:
	if not habit.is_empty() or susceptibility > 0.0:
		return false
	for id in s:
		if float(s[id]["dependence"]) > 0.0 or float(s[id]["craving"]) > 0.0 or float(s[id]["effect_left"]) > 0.0:
			return false
	return money_worry <= 0.0 and psychosis_push <= 0.0


func configure(hab: Variant, susc: Variant, keep_state: bool) -> void:
	habit = {}
	if typeof(hab) == TYPE_DICTIONARY:
		for id in hab:
			if DEFS.has(id) and typeof(hab[id]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(hab[id])) and float(hab[id]) > 0.0:
				habit[String(id)] = clampf(float(hab[id]), 0.0, 1.0)
	susceptibility = clampf(float(susc), 0.0, 1.0) if typeof(susc) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(susc)) else 0.0
	if not keep_state:
		s = {}
		cut_until = -1.0e9
		money_worry = 0.0
		psychosis_push = 0.0
		# Dlouhodobý zvyk znamená výchozí toleranci a závislost (postava „už to tak má“).
		for id in habit:
			var h: float = habit[id]
			var st := _st(String(id))
			st["tolerance"] = 0.4 * h
			st["dependence"] = clampf(h * (0.25 + 0.4 * susceptibility), 0.0, 0.8)


func _st(id: String) -> Dictionary:
	if not s.has(id):
		s[id] = {"craving": 0.0, "tolerance": 0.0, "dependence": 0.0, "last": -1.0e9, "effect_left": 0.0,
			"scar": 0.0, "uses": []}
	return s[id]


func dependence(id: String) -> float:
	return float(s.get(id, {}).get("dependence", 0.0))


func craving(id: String) -> float:
	return float(s.get(id, {}).get("craving", 0.0))


func cutting_down(now: float) -> bool:
	return now < cut_until


func uses_today(id: String, now: float) -> int:
	var n := 0
	for t in s.get(id, {}).get("uses", []):
		if now - float(t) < 1440.0:
			n += 1
	return n


## Užití (nebo behaviorální epizoda). Vrací {"liking", "stress", "mood"} – prožitek s tolerancí.
func on_use(id: String, now: float, k: float) -> Dictionary:
	if not DEFS.has(id):
		return {}
	var d: Dictionary = DEFS[id]
	var st := _st(id)
	var liking := float(d["pleasure"]) * (1.0 - 0.7 * float(st["tolerance"]))
	var relief := float(st["craving"])
	st["craving"] = float(st["craving"]) * 0.2
	st["tolerance"] = clampf(float(st["tolerance"]) + float(d["tol"]) * k, 0.0, 1.0)
	var rate := float(d["dep_rate"]) * (0.25 + susceptibility + 0.5 * float(habit.get(id, 0.0)) + float(st["scar"])) * k
	# Častější užití v krátkém odstupu prohlubuje závislost víc.
	var recent := uses_today(id, now)
	st["dependence"] = clampf(float(st["dependence"]) + rate * (1.0 + 0.3 * recent) * (1.0 - float(st["dependence"])), 0.0, 1.0)
	st["last"] = now
	st["effect_left"] = float(d["effect"])
	var uses: Array = st["uses"]
	uses.append(now)
	while uses.size() > 12:
		uses.pop_front()
	# Alkohol: příležitostné pití běžné postavy peníze neohrožuje – starost až u návyku.
	if id != "alcohol" or float(st["dependence"]) > 0.15:
		money_worry = clampf(money_worry + 0.12 * float(d["cost"]) * k, 0.0, 1.0)
	psychosis_push = clampf(psychosis_push + 0.25 * float(d["psychosis"]) * k, 0.0, 1.0)
	# Alkohol má vlastní úlevu i kocovinu v MentalState (coping „drink“) – tady se jen sleduje návyk.
	if float(d["pleasure"]) <= 0.0:
		return {"liking": 0.0, "stress": -6.0 * relief * k}
	return {"liking": liking * k, "stress": -(2.0 + 6.0 * relief) * k}


## Krok. ctx: stress, sleeping, hour, others_using (počet lidí poblíž, kteří právě užívají), support.
## Vrací {"stress", "withdrawal" (0..1 nejsilnější), "withdrawal_id", "crash"}.
func tick(dm: float, now: float, ctx: Dictionary, k: float) -> Dictionary:
	var out := {"stress": 0.0, "withdrawal": 0.0, "withdrawal_id": "", "crash": 0.0}
	if dm <= 0.0:
		return out
	money_worry *= exp(-dm / 4320.0)
	psychosis_push *= exp(-dm / 1440.0)
	if k <= 0.0:
		for id in s:
			s[id]["craving"] = 0.0
		return out
	var stress := float(ctx.get("stress", 15.0))
	var support := float(ctx.get("support", 0.0))
	var hour := int(ctx.get("hour", 12))
	var cut := cutting_down(now)
	for id in s:
		var d: Dictionary = DEFS[id]
		var st: Dictionary = s[id]
		var dep := float(st["dependence"])
		var since := now - float(st["last"])
		if float(st["effect_left"]) > 0.0:
			var before := float(st["effect_left"])
			st["effect_left"] = maxf(before - dm, 0.0)
			if before > 0.0 and float(st["effect_left"]) <= 0.0 and float(d["crash"]) > 0.0:
				out["crash"] = maxf(float(out["crash"]), float(d["crash"]) * k)
		# Chuť: závislost × odstup + podněty (stres, ranní káva, lidé kolem, kteří užívají); opora tlumí.
		var cue := maxf(stress - 50.0, 0.0) / 50.0 * 0.5 + float(ctx.get("others_using", 0)) * 0.2
		if id == "caffeine" and hour >= 6 and hour <= 9:
			cue += 0.3
		# Občasné užití bez závislosti (pod 0,1) chuť nevytváří – žádná smyčka u běžných postav.
		var dep_c := clampf((dep - 0.1) / 0.9, 0.0, 1.0)
		var target := clampf(dep_c * clampf(since / float(d["onset"]), 0.0, 1.5) * (1.0 + cue) + 0.3 * float(habit.get(id, 0.0)) * cue, 0.0, 1.0)
		target *= 1.0 - 0.4 * support
		var tau := 120.0 if target > float(st["craving"]) else 240.0
		st["craving"] = clampf(float(st["craving"]) + (target - float(st["craving"])) * (1.0 - exp(-dm / tau)), 0.0, 1.0)
		# Abstinence: jen se závislostí a po nástupní době; při rozhodnutí omezit je citelnější, ale přechodná.
		if dep > 0.2 and since > float(d["onset"]):
			var wd := clampf((dep - 0.2) / 0.8 * clampf((since - float(d["onset"])) / float(d["onset"]), 0.0, 1.0), 0.0, 1.0)
			if cut:
				wd *= 1.15
			if wd > float(out["withdrawal"]):
				out["withdrawal"] = wd
				out["withdrawal_id"] = id
			out["stress"] = float(out["stress"]) + wd * 0.02 * dm * k
		# Odvykání: bez užití závislost pomalu klesá (týdny), tolerance rychleji; zůstane slabá jizva.
		if since > float(d["onset"]) * 2.0:
			var drop := dm / 30240.0 * (1.0 + support)
			if dep > 0.3 and dep - drop <= 0.3:
				st["scar"] = clampf(float(st["scar"]) + 0.1, 0.0, 0.4)
			st["dependence"] = maxf(dep - drop, 0.0)
		st["tolerance"] = float(st["tolerance"]) * exp(-dm / 14400.0)
		st["scar"] = float(st["scar"]) * exp(-dm / 129600.0)
	out["stress"] = float(out["stress"]) + money_worry * 0.01 * dm * k
	return out


## Chuť na akci užití (utility AI): chuť (wanting) + zvyk; rozhodnutí omezit ji tlumí. Bez zvyku a chuti
## je brána zavřená (výchozí postava nic nezačne).
func gate(id: String) -> float:
	if not DEFS.has(id):
		return 0.0
	return clampf(craving(id) + 0.5 * float(habit.get(id, 0.0)), 0.0, 1.0)


func use_weight(id: String, now: float, k: float) -> float:
	if k <= 0.0:
		return 1.0
	var w := 1.0 + 3.0 * craving(id) + 1.5 * float(habit.get(id, 0.0))
	if cutting_down(now):
		w *= 0.4
	# Už dnes užito několikrát → méně lákavé (únava z toho), ale u silné závislosti méně.
	w /= 1.0 + 0.4 * uses_today(id, now) * (1.0 - dependence(id))
	return clampf(w, 0.2, 5.0)


## Nejsilnější závislost (pro bránu „vyhledat pomoc“ a „omezit“).
func max_dependence() -> float:
	var m := 0.0
	for id in s:
		m = maxf(m, float(s[id]["dependence"]))
	return m


func sleep_quality_mult(now: float, hour: int) -> float:
	var q := 1.0
	for id in s:
		var d: Dictionary = DEFS[id]
		var since := now - float(s[id]["last"])
		if since < 360.0 and float(d["sleep"]) != 0.0:
			q *= 1.0 - float(d["sleep"]) * (1.0 - since / 360.0)
	return clampf(q, 0.5, 1.15)


## Podrážděnost z abstinence (posun šance na dobrý rozhovor).
func irritability(withdrawal: float, withdrawal_id: String) -> float:
	if withdrawal_id == "" or not DEFS.has(withdrawal_id):
		return 0.0
	return clampf(withdrawal * float(DEFS[withdrawal_id]["irritable"]), 0.0, 1.0)


## Tlak na náladu nahoru (stimulant) pro průběh nálady – jen během účinku.
func elevation_push() -> float:
	var e := 0.0
	for id in s:
		if float(s[id]["effect_left"]) > 0.0:
			e = maxf(e, float(DEFS[id]["elevate"]))
	return e


func mood_entries(now: float, withdrawal: float, withdrawal_id: String, k: float) -> Array:
	var out: Array = []
	if k <= 0.0:
		return out
	if withdrawal > 0.2 and withdrawal_id != "":
		out.append({"id": "sub_abstinence", "label": String(DEFS[withdrawal_id]["withdrawal"]), "emotion": "nesvuj",
			"strength": -lerpf(4.0, 16.0, clampf((withdrawal - 0.2) / 0.8, 0.0, 1.0)) * k, "remaining": -1.0})
	for id in s:
		if craving(id) > 0.5 and (withdrawal_id != id):
			out.append({"id": "sub_chut_" + id, "label": "Mám chuť na: " + String(DEFS[id]["label"]), "emotion": "napjaty",
				"strength": -4.0 * craving(id) * k, "remaining": -1.0})
			break
	if money_worry > 0.35:
		out.append({"id": "sub_penize", "label": "Starosti o peníze", "emotion": "uzkostny",
			"strength": -lerpf(3.0, 10.0, (money_worry - 0.35) / 0.65) * k, "remaining": -1.0})
	if cutting_down(now):
		out.append({"id": "sub_omezuji", "label": "Snažím se to omezit", "emotion": "soustredeny",
			"strength": 2.0 * k, "remaining": -1.0})
	return out


func private_lines(now: float, k: float) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0:
		return out
	var worst := ""
	var dep := 0.0
	for id in s:
		if float(s[id]["dependence"]) > dep:
			dep = float(s[id]["dependence"])
			worst = String(id)
	if dep > 0.5:
		out.append("Na %s si vytvářím silný návyk. Pomáhá říct to někomu blízkému, omezit to nebo vyhledat odbornou pomoc." % DEFS[worst]["label"])
	elif dep > 0.25:
		out.append("%s se stává zvykem." % String(DEFS[worst]["label"]).capitalize())
	if cutting_down(now):
		out.append("Rozhodl(a) jsem se to omezit – první dny bývají nejtěžší.")
	return out


func to_dict() -> Dictionary:
	return {"s": s.duplicate(true), "cut_until": cut_until, "money_worry": money_worry, "psychosis_push": psychosis_push}


static func _n(v: Variant, lo: float, hi: float) -> bool:
	return typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 8:
		return false
	for key in d:
		if not STATE_KEYS.has(key):
			return false
	var ss = d.get("s", {})
	if typeof(ss) != TYPE_DICTIONARY or ss.size() > IDS.size():
		return false
	for id in ss:
		if not DEFS.has(id) or typeof(ss[id]) != TYPE_DICTIONARY or ss[id].size() > 8:
			return false
		var st: Dictionary = ss[id]
		for key in ["craving", "tolerance", "dependence"]:
			if not _n(st.get(key), 0.0, 1.0):
				return false
		if not _n(st.get("scar", 0.0), 0.0, 0.4) or not _n(st.get("last"), -1.0e12, 1.0e12) or not _n(st.get("effect_left"), 0.0, 1.0e4):
			return false
		var uses = st.get("uses", [])
		if typeof(uses) != TYPE_ARRAY or uses.size() > 12:
			return false
		for t in uses:
			if not _n(t, -1.0e12, 1.0e12):
				return false
	if d.has("cut_until") and not _n(d["cut_until"], -1.0e12, 1.0e12):
		return false
	for key in ["money_worry", "psychosis_push"]:
		if d.has(key) and not _n(d[key], 0.0, 1.0):
			return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	s = {}
	var ss: Dictionary = d.get("s", {})
	for id in ss:
		var st: Dictionary = ss[id]
		s[String(id)] = {"craving": float(st["craving"]), "tolerance": float(st["tolerance"]), "dependence": float(st["dependence"]),
			"last": float(st["last"]), "effect_left": float(st["effect_left"]), "scar": float(st.get("scar", 0.0)),
			"uses": (st.get("uses", []) as Array).duplicate()}
	cut_until = float(d.get("cut_until", -1.0e9))
	money_worry = float(d.get("money_worry", 0.0))
	psychosis_push = float(d.get("psychosis_push", 0.0))
