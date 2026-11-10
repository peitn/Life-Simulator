extends RefCounted
## Most mezi izolovanou FIKTIVNÍ ekonomikou/burzou (scripts/sim/economy/*) a psychikou agentů. Čistě data dovnitř / ven:
## nezná SimAgent ani uzly, nevolá mental ani mood. Jednou za herní den (step_day) posune ekonomiku o den a vrátí
## pro každého agenta (podle sim_name) malé VSTUPY: {"stress": body, "mood": síla moodletu, "mood_minutes": trvání}.
## Aplikaci (mental.on_stressor("life", ...), moodlet) provádí volající (HouseholdDynamics.apply_economy_effects).
##
## Zásady (docs/economy_psyche_bridge.md):
##  - VÝCHOZÍ VYPNUTO: bez instance mostu se v existující hře nic nemění (bit-for-bit).
##  - Žádný nový model psychiky; jen vstupy do existujícího stresoru a nálady.
##  - Finanční tíseň NIKDY nevybírá, nespouští ani nevynucuje žádnou akci (ani nelegální, ani násilnou); most akce vůbec nezná.
##  - Ekonomika je vymyšlená (krejcary, tickery "-G"); žádná reálná data. Všechny prahy/váhy jsou `game_balance`.
##  - Vše je ohraničené (strop denní dávky stresu, strop nálady) a konečné; žádná zpětná vazba do ekonomiky.

const Economy := preload("res://scripts/sim/economy/economy.gd")
const MODEL_VERSION := "economy-bridge-0.1"
## 128 (dříve 64): laboratoř ("Údolí") registruje stovku agentů; pro ≤ 64 agentů se nic nemění.
const MAX_AGENTS := 128

## Jediné místo s laděním (vše `game_balance`; nic není `empirical_anchor`, nic není kalibrováno na reálná data).
const BALANCE := {
	"seed": 1,                      # seed ekonomiky (a tím i burzy)
	"market": false,                # zapnout fiktivní burzu (stock_market.gd)
	"events": [],                   # události burzy (path/vol/div_cut/rates/layoffs) – viz docs/economy_market.md; den = den ekonomiky
	# Přepisy Economy.DEFAULT_CONFIG. Jmění 20 000–120 000 kr (běžné 3 000–40 000 kr by většinu agentů nechalo mimo burzu, takže by pokles
	# portfolia neměl na co působit); illegal_share_bp 0 = žádní agenti s (abstraktní) nelegální prací, most nemá nic, co by k ní vedlo.
	"economy": {"endowment_min": 20000, "endowment_max": 120000, "illegal_share_bp": 0},
	"max_catchup_days": 3,          # kolik dnů ekonomiky se nejvýš dožene při skoku času (zbytek se zahodí)
	# Volitelné předvolby po agentech (laboratoř): {sim_name: {tier, qualification, job, endowment, household, shift_off, profile}}.
	# Prázdné = původní chování (vše z RNG ekonomiky a z otisku id). `profile` = investorský profil burzy (jen s market=true).
	"agents": {},
	# --- chronický finanční stres z financial_pressure (0..1) ---
	"pressure_floor": 0.30,         # pod touto hodnotou tlaku žádný chronický stres
	"chronic_stress_per_day": 4.0,  # body stresu za den při tlaku 1.0 (lineárně od prahu)
	# --- akutní složka z poklesu portfolia (docs/economy_market.md, bod 8) ---
	"acute_gain": 4.0,              # přírůstek "starosti" = denní ztráta (podíl 0..1) × podíl akcií na likvidním majetku × acute_gain
	"acute_half_life_days": 12.0,   # poločas doznívání starosti (dny)
	"acute_cap": 1.0,               # strop starosti 0..1
	"acute_stress_per_day": 5.0,    # body stresu za den při starosti 1.0
	"acute_impulse": 0.6,           # jednorázová dávka stresu v den poklesu: ztráta × podíl akcií × acute_impulse × 100 bodů
	# --- strop a nálada ---
	"stress_dose_cap": 8.0,         # tvrdý strop součtu dávky stresu za jeden den (proti spirále)
	"mood_per_pressure": -6.0,      # síla moodletu při tlaku 1.0 (od prahu)
	"mood_per_worry": -5.0,         # síla moodletu při starosti 1.0
	"mood_cap": -10.0,              # nejhlubší moodlet z peněz
	"mood_minutes": 1440.0,         # trvání moodletu (obnovuje se denně)
}

var cfg: Dictionary = {}
var eco: RefCounted = null
var names: Dictionary = {}        # sim_name -> economy id
var state: Dictionary = {}        # economy id -> {"worry": float, "idx_prev": int}
var last_day: int = -1            # poslední herní den, ke kterému je ekonomika dorovnána (-1 = ještě nepřipojeno)
var stats: Dictionary = {"days": 0, "stress_sum": 0.0, "mood_min": 0.0, "agents": 0}


static func default_config() -> Dictionary:
	return (BALANCE as Dictionary).duplicate(true)


## Prázdné pole = platné. Kontroluje typ, konečnost a rozsah (mapování je ohraničené).
static func validate_config(c: Dictionary) -> Array:
	var errs: Array = []
	var ranges := {"pressure_floor": [0.0, 0.99], "chronic_stress_per_day": [0.0, 20.0], "acute_gain": [0.0, 20.0],
		"acute_half_life_days": [1.0, 365.0], "acute_cap": [0.0, 1.0], "acute_stress_per_day": [0.0, 20.0],
		"acute_impulse": [0.0, 2.0], "stress_dose_cap": [0.0, 30.0], "mood_per_pressure": [-20.0, 0.0],
		"mood_per_worry": [-20.0, 0.0], "mood_cap": [-20.0, 0.0], "mood_minutes": [60.0, 2880.0], "max_catchup_days": [1.0, 30.0],
		"seed": [-1.0e9, 1.0e9]}
	for k in c:
		if not (BALANCE as Dictionary).has(k):
			errs.append("neznámý klíč: %s" % String(k))
			continue
		if ranges.has(k):
			var v: Variant = c[k]
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				errs.append("%s musí být číslo" % String(k))
			elif not is_finite(float(v)) or float(v) < float(ranges[k][0]) or float(v) > float(ranges[k][1]):
				errs.append("%s mimo rozsah %s..%s" % [String(k), str(ranges[k][0]), str(ranges[k][1])])
		elif k == "market":
			if typeof(c[k]) != TYPE_BOOL:
				errs.append("market musí být bool")
		elif k == "events":
			if typeof(c[k]) != TYPE_ARRAY:
				errs.append("events musí být pole")
			else:
				var ee: String = Economy.StockMarket.validate_events(c[k])
				if ee != "":
					errs.append(ee)
		elif k == "economy":
			if typeof(c[k]) != TYPE_DICTIONARY:
				errs.append("economy musí být objekt")
		elif k == "agents":
			errs.append_array(_validate_agents(c[k]))
	return errs


const AGENT_KEYS := ["tier", "qualification", "job", "endowment", "household", "shift_off", "profile"]


static func _validate_agents(a: Variant) -> Array:
	var errs: Array = []
	if typeof(a) != TYPE_DICTIONARY:
		return ["agents musí být objekt"]
	if (a as Dictionary).size() > MAX_AGENTS:
		errs.append("agents: nejvýš %d agentů" % MAX_AGENTS)
	for nm in a:
		var o: Variant = a[nm]
		if typeof(o) != TYPE_DICTIONARY:
			errs.append("agents.%s musí být objekt" % String(nm))
			continue
		for k in o:
			if not AGENT_KEYS.has(String(k)):
				errs.append("agents.%s: neznámý klíč %s" % [String(nm), String(k)])
		if o.has("tier") and not (Economy.Catalog.HOUSING as Dictionary).has(String(o["tier"])):
			errs.append("agents.%s: neznámé bydlení" % String(nm))
		if o.has("job") and String(o["job"]) != "" and not (Economy.Catalog.JOBS as Dictionary).has(String(o["job"])):
			errs.append("agents.%s: neznámé povolání" % String(nm))
		if o.has("profile") and not (Economy.StockMarket.MCat.PROFILES as Dictionary).has(String(o["profile"])):
			errs.append("agents.%s: neznámý investorský profil" % String(nm))
		for k2 in ["qualification", "shift_off", "endowment"]:
			if o.has(k2):
				var v: Variant = o[k2]
				var okn: bool = (typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and floorf(v) == v))
				var lim: Array = {"qualification": [0, 3], "shift_off": [0, 6], "endowment": [0, 10000000]}[k2]
				if not okn or int(v) < int(lim[0]) or int(v) > int(lim[1]):
					errs.append("agents.%s.%s mimo rozsah" % [String(nm), k2])
	return errs


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = default_config()
	for k in p_cfg:
		if (BALANCE as Dictionary).has(k):
			cfg[k] = p_cfg[k]
	_make_economy()


func _make_economy() -> void:
	var ec: Dictionary = (cfg["economy"] as Dictionary).duplicate(true)
	if bool(cfg["market"]):
		ec["market_enabled"] = true
		var m: Dictionary = (ec.get("market", {}) as Dictionary).duplicate(true)
		m["events"] = (cfg["events"] as Array).duplicate(true)
		ec["market"] = m
	eco = Economy.new(int(cfg["seed"]), ec)


func _f(key: String) -> float:
	return float(cfg[key])


## Zaregistruje nové agenty (sim_name -> id) v pořadí, v jakém přišli (deterministické losování v ekonomice).
func ensure_agents(sim_names: Array) -> void:
	for n in sim_names:
		var nm: String = String(n)
		if names.has(nm) or names.size() >= MAX_AGENTS:
			continue
		var id: String = "sim:" + nm
		if eco.has_agent(id):
			names[nm] = id
			continue
		var opts: Dictionary = {}
		var prof: String = ""
		var pre: Variant = (cfg["agents"] as Dictionary).get(nm, null)
		if typeof(pre) == TYPE_DICTIONARY:
			for ok in ["tier", "qualification", "endowment", "household", "shift_off"]:
				if (pre as Dictionary).has(ok):
					opts[ok] = pre[ok]
			if (pre as Dictionary).has("job") and String(pre["job"]) != "":
				opts["job"] = String(pre["job"])
			elif (pre as Dictionary).has("job"):
				opts["job"] = ""   # výslovně bez práce
			prof = String((pre as Dictionary).get("profile", ""))
		if bool(eco.add_agent(id, opts)["ok"]):
			if prof != "" and eco.market != null:
				eco.market.set_profile(id, prof)
			names[nm] = id
			state[id] = {"worry": 0.0, "idx_prev": Economy.StockMarket.PPM if eco.market != null else 0}
			stats["agents"] = names.size()


## Jednou za herní den. Vrací {sim_name: {"stress", "mood", "mood_minutes"}} (jen agenti s nenulovým vstupem).
## První volání jen ukotví den (ekonomika startuje spolu se hrou); další dny dorovnává ekonomiku den po dni.
func step_day(game_day: int, sim_names: Array) -> Dictionary:
	ensure_agents(sim_names)
	if last_day < 0:
		last_day = game_day
		return {}
	if game_day <= last_day:
		return {}
	var n: int = mini(game_day - last_day, int(cfg["max_catchup_days"]))
	last_day = game_day
	var acc: Dictionary = {}
	for i in n:
		eco.run_day()
		_accumulate(acc, _day_effects(sim_names))
	var out: Dictionary = {}
	for nm in acc:
		var e: Dictionary = acc[nm]
		var st: float = clampf(float(e["stress"]), 0.0, _f("stress_dose_cap"))
		var mo: float = clampf(float(e["mood"]), _f("mood_cap"), 0.0)
		if st > 0.0 or mo < 0.0:
			out[nm] = {"stress": st, "mood": mo, "mood_minutes": _f("mood_minutes")}
			stats["stress_sum"] = float(stats["stress_sum"]) + st
			stats["mood_min"] = minf(float(stats["mood_min"]), mo)
	stats["days"] = int(stats["days"]) + n
	return out


static func _accumulate(acc: Dictionary, day_fx: Dictionary) -> void:
	for nm in day_fx:
		if not acc.has(nm):
			acc[nm] = {"stress": 0.0, "mood": 0.0}
		acc[nm]["stress"] = float(acc[nm]["stress"]) + float(day_fx[nm]["stress"])
		acc[nm]["mood"] = minf(float(acc[nm]["mood"]), float(day_fx[nm]["mood"]))


## Denní vstupy jednoho dne ekonomiky (po eco.run_day()).
func _day_effects(sim_names: Array) -> Dictionary:
	var out: Dictionary = {}
	var half: float = _f("acute_half_life_days")
	var decay: float = pow(0.5, 1.0 / half)
	var floor_p: float = _f("pressure_floor")
	for n in sim_names:
		var nm: String = String(n)
		if not names.has(nm):
			continue
		var id: String = String(names[nm])
		var st: Dictionary = state[id]
		var fp: float = clampf(float(eco.financial_pressure(id)), 0.0, 1.0)
		var excess: float = clampf((fp - floor_p) / maxf(1.0 - floor_p, 0.01), 0.0, 1.0)
		var stress: float = excess * _f("chronic_stress_per_day")
		var mood: float = excess * _f("mood_per_pressure")
		var worry: float = float(st["worry"]) * decay
		if eco.market != null and eco.market.portfolios.has(id):
			var h: Array = (eco.market.portfolios[id] as Dictionary)["idx_hist"]
			var cur: int = int(h[h.size() - 1])
			var prev: int = int(st["idx_prev"])
			st["idx_prev"] = cur
			var share: float = clampf(float(eco.agent_view(id)["market"]["equity_share_pm"]) / 1000.0, 0.0, 1.0)
			if prev > 0 and cur < prev:
				var loss: float = clampf(float(prev - cur) / float(prev), 0.0, 1.0)
				worry += loss * share * _f("acute_gain")
				stress += loss * share * _f("acute_impulse") * 100.0
		worry = clampf(worry, 0.0, _f("acute_cap"))
		st["worry"] = worry
		stress += worry * _f("acute_stress_per_day")
		mood += worry * _f("mood_per_worry")
		stress = clampf(stress, 0.0, _f("stress_dose_cap"))
		mood = clampf(mood, _f("mood_cap"), 0.0)
		if stress > 0.0 or mood < 0.0:
			out[nm] = {"stress": stress, "mood": mood}
	return out


# ---------------------------------------------------------------- pohledy a (de)serializace

## Jen čtení, pro HUD/laboratoř: {"pressure", "worry", "balance", "portfolio_value"} nebo {}.
func view(sim_name: String) -> Dictionary:
	if not names.has(sim_name):
		return {}
	var id: String = String(names[sim_name])
	var v: Dictionary = eco.agent_view(id)
	var out: Dictionary = {"pressure": float(v["financial_pressure"]), "worry": float((state[id] as Dictionary)["worry"]),
		"balance": int(v["balance"]), "portfolio_value": 0}
	if v.has("market"):
		out["portfolio_value"] = int(v["market"]["portfolio_value"])
	return out


func to_dict() -> Dictionary:
	return {"version": MODEL_VERSION, "cfg": cfg.duplicate(true), "names": names.duplicate(true), "state": state.duplicate(true),
		"last_day": last_day, "stats": stats.duplicate(true), "economy": eco.to_dict()}


## Vrací instanci, nebo null při neplatných datech (volající starou/neplatnou sekci ignoruje).
static func from_dict(d0: Variant) -> RefCounted:
	if typeof(d0) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = Economy._norm(d0)
	for k in ["version", "cfg", "names", "state", "last_day", "stats", "economy"]:
		if not d.has(k):
			return null
	if typeof(d["cfg"]) != TYPE_DICTIONARY or typeof(d["names"]) != TYPE_DICTIONARY or typeof(d["state"]) != TYPE_DICTIONARY \
			or typeof(d["economy"]) != TYPE_DICTIONARY or typeof(d["stats"]) != TYPE_DICTIONARY:
		return null
	if not validate_config(d["cfg"]).is_empty() or (d["names"] as Dictionary).size() > MAX_AGENTS:
		return null
	var b: RefCounted = (load("res://scripts/sim/economy_bridge.gd") as GDScript).new(d["cfg"])
	b.eco = Economy.from_dict(d["economy"])
	b.names = d["names"]
	b.state = d["state"]
	b.last_day = int(d["last_day"])
	b.stats = d["stats"]
	return b
