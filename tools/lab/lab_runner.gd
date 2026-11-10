extends RefCounted
## Laboratoř sociální a psychologické dynamiky – M1a: headless spouštěč scénářů.
## Spouští STÁVAJÍCÍ simulaci (main.gd, offline, bez 3D/HUD/zvuku/kamery/autosave) pro fiktivní agenty,
## posouvá GameClock po 2 minutách a zapisuje denní snímky. Nemění žádný kód hry.
##
## Scénář (Dictionary / JSON):
##   name: String, seed: int, days: int (1..60), household: Array (volitelné; formát Main.HOUSEHOLD, jinak výchozí 3 postavy),
##   snapshot_hours: int (výchozí 24), start_minutes: float (výchozí 8:00 = 480)
##   condition (volitelné, platí pro všechny agenty na začátku; vše ostatní zůstává shodné):
##     initial_support: 0..1  → mental.support (vnímaná opora, stejný konstrukt, který čte model)
##     initial_relationship: -100..100 → počáteční přátelství každého s každým (rel. matrix modelu)
##     POZOR: mental.support je „nedávná opora" a v modelu mizí s časovou konstantou 6 h (mental_state.gd:388),
##     takže initial_support sám o sobě po několika hodinách nic nedělá; trvalou složkou jsou vztahy.
##   interventions (volitelné): [{day: 0..days, kind: "stressor", amount: 0..100, target: "all" | jméno agenta}]
##     stresor se aplikuje stejnou cestou jako životní událost v household_dynamics (mental.on_stressor("life", ...)).
##   economy (volitelné, výchozí vypnuto; bez něj je běh bit-for-bit shodný): {enabled: bool, market: bool, seed: int,
##     shock: {day: 1..days, total_pm: -999..0, days: 1..30}}  → zapne most fiktivní ekonomiky/burzy na psychiku
##     (scripts/sim/economy_bridge.gd). shock = plošný pokles cen burzy (typ "path", scope "market"), vyžaduje market=true.
##     Den ekonomiky d se projeví na začátku herního dne d+1 (ekonomika se posouvá o den při přechodu dne).
## Výsledek: {"ok", "scenario", "seed", "days", "agents": [jména], "snapshots": [...], "final_hash": String,
##            "stats": household statistiky, "model": {...verze/provenance}}
## Všechna data jsou fiktivní agenti. Výsledky platí jen v rámci modelu, ne pro lidi.

const Main := preload("res://main.gd")
const EconomyBridge := preload("res://scripts/sim/economy_bridge.gd")
const STEP_MINUTES := 2.0
const MODEL_VERSION := "lab-m1a-0.1"


## JSON čte všechna čísla jako float; celé číslo = int nebo float bez desetinné části.
static func _is_whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and floorf(v) == v)


static func validate(sc: Dictionary) -> Array:
	var errs: Array = []
	if not _is_whole(sc.get("seed", null)):
		errs.append("seed musí být celé číslo")
	var days = sc.get("days", 0)
	if not _is_whole(days) or int(days) < 1 or int(days) > 60:
		errs.append("days musí být 1..60")
	var hrs = sc.get("snapshot_hours", 24)
	if not _is_whole(hrs) or int(hrs) < 1 or int(hrs) > 24 or 24 % int(hrs) != 0:
		errs.append("snapshot_hours musí dělit 24")
	if sc.has("household") and typeof(sc["household"]) != TYPE_ARRAY:
		errs.append("household musí být pole")
	var cond = sc.get("condition", {})
	if typeof(cond) != TYPE_DICTIONARY:
		errs.append("condition musí být objekt")
	else:
		if cond.has("initial_support") and (not (cond["initial_support"] is float or cond["initial_support"] is int) \
				or float(cond["initial_support"]) < 0.0 or float(cond["initial_support"]) > 1.0):
			errs.append("initial_support musí být 0..1")
		if cond.has("initial_relationship") and (not (cond["initial_relationship"] is float or cond["initial_relationship"] is int) \
				or absf(float(cond["initial_relationship"])) > 100.0):
			errs.append("initial_relationship musí být -100..100")
	if sc.has("economy"):
		errs.append_array(_validate_economy(sc["economy"], sc.get("days", 0)))
	var iv = sc.get("interventions", [])
	if typeof(iv) != TYPE_ARRAY:
		errs.append("interventions musí být pole")
	else:
		for e in iv:
			if typeof(e) != TYPE_DICTIONARY or String(e.get("kind", "")) != "stressor" \
					or not (e.get("amount", null) is float or e.get("amount", null) is int) \
					or float(e["amount"]) < 0.0 or float(e["amount"]) > 100.0 \
					or not (e.get("day", null) is float or e.get("day", null) is int) \
					or float(e["day"]) < 0.0 or float(e["day"]) > float(sc.get("days", 0)):
				errs.append("intervence musí být {day 0..days, kind 'stressor', amount 0..100, target}")
				break
	return errs


static func _validate_economy(eco: Variant, days: Variant) -> Array:
	var errs: Array = []
	if typeof(eco) != TYPE_DICTIONARY:
		return ["economy musí být objekt"]
	for k in eco:
		if not ["enabled", "market", "seed", "shock"].has(String(k)):
			errs.append("economy: neznámý klíč %s" % String(k))
	if eco.has("enabled") and typeof(eco["enabled"]) != TYPE_BOOL:
		errs.append("economy.enabled musí být bool")
	if eco.has("market") and typeof(eco["market"]) != TYPE_BOOL:
		errs.append("economy.market musí být bool")
	if eco.has("seed") and (not _is_whole(eco["seed"]) or absf(float(eco["seed"])) > 1.0e9):
		errs.append("economy.seed musí být celé číslo")
	if eco.has("shock"):
		var sh = eco["shock"]
		if typeof(sh) != TYPE_DICTIONARY:
			errs.append("economy.shock musí být objekt")
		else:
			if not bool(eco.get("market", false)) or not bool(eco.get("enabled", false)):
				errs.append("economy.shock vyžaduje enabled i market")
			for k in sh:
				if not ["day", "total_pm", "days"].has(String(k)):
					errs.append("economy.shock: neznámý klíč %s" % String(k))
			if not _is_whole(sh.get("day", null)) or int(sh["day"]) < 1 or (_is_whole(days) and int(sh["day"]) > int(days)):
				errs.append("economy.shock.day musí být 1..days")
			if not _is_whole(sh.get("total_pm", null)) or int(sh["total_pm"]) < -999 or int(sh["total_pm"]) > 0:
				errs.append("economy.shock.total_pm musí být -999..0")
			if not _is_whole(sh.get("days", null)) or int(sh["days"]) < 1 or int(sh["days"]) > 30:
				errs.append("economy.shock.days musí být 1..30")
	return errs


## Z bloku economy sestaví konfiguraci mostu (jen když je enabled).
static func _bridge_cfg(eco: Dictionary, sc_seed: int) -> Dictionary:
	var c := {"seed": int(eco.get("seed", sc_seed)), "market": bool(eco.get("market", false))}
	if eco.has("shock"):
		var sh: Dictionary = eco["shock"]
		c["events"] = [{"type": "path", "day": int(sh["day"]), "days": int(sh["days"]), "total_pm": int(sh["total_pm"]), "scope": "market"}]
	return c


## Spustí scénář pod `host` (uzel ve stromu, přes který se čeká na snímky). Vrací výsledek.
static func run(host: Node, sc: Dictionary) -> Dictionary:
	var errs := validate(sc)
	if not errs.is_empty():
		return {"ok": false, "errors": errs}
	var clock = host.get_node("/root/GameClock")
	var settings = host.get_node("/root/GameSettings")
	var prev_running: bool = clock.running
	var prev_persist = settings.persist
	clock.running = false
	settings.persist = false
	settings.reset()
	var seed_i := int(sc["seed"])
	var days := int(sc["days"])
	var snap_h := int(sc.get("snapshot_hours", 24))
	clock.total_minutes = float(sc.get("start_minutes", 480.0))
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var prev_override: Array = Main.household_override
	Main.household_override = sc.get("household", [])
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "LabWorld"
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false}
	host.add_child(w)
	var n := 0
	for sim in w.sims:
		sim.rng.seed = seed_i * 7919 + n * 104729 + 13
		sim.think_cooldown = sim.rng.randf_range(0.0, 3.0)
		n += 1
	var cond: Dictionary = sc.get("condition", {})
	for sim in w.sims:
		if cond.has("initial_support"):
			sim.mental.support = float(cond["initial_support"])
		if cond.has("initial_relationship"):
			for other in w.sims:
				if other != sim:
					sim.relationships[other.sim_name] = float(cond["initial_relationship"])
	var eco_sc: Dictionary = sc.get("economy", {})
	var eco_on: bool = bool(eco_sc.get("enabled", false))
	if eco_on:
		w.dynamics.economy_bridge = EconomyBridge.new(_bridge_cfg(eco_sc, seed_i))
	var names: Array = []
	for sim in w.sims:
		names.append(String(sim.sim_name))
	var snaps: Array = []
	snaps.append(_snapshot(w, 0.0))
	var pending: Array = []
	for e in sc.get("interventions", []):
		pending.append(e.duplicate(true))
	pending.sort_custom(func(x, y): return float(x["day"]) < float(y["day"]))
	var first_iv := float(pending[0]["day"]) if not pending.is_empty() else -1.0
	if eco_on and eco_sc.has("shock") and first_iv < 0.0:
		first_iv = float(eco_sc["shock"]["day"])
	var steps_per_snap := int(snap_h * 60 / STEP_MINUTES)
	var total_steps := int(days * 1440 / STEP_MINUTES)
	for i in total_steps:
		clock.advance(STEP_MINUTES)
		while not pending.is_empty() and float(pending[0]["day"]) * 1440.0 <= float(i + 1) * STEP_MINUTES:
			_apply_intervention(w, pending.pop_front())
		if (i + 1) % steps_per_snap == 0:
			snaps.append(_snapshot(w, float(i + 1) * STEP_MINUTES / 1440.0))
	var stats: Dictionary = w.dynamics.stats.duplicate(true)
	var eco_out: Dictionary = {}
	if eco_on:
		eco_out = {"enabled": true, "market": bool(eco_sc.get("market", false)), "stats": w.dynamics.economy_bridge.stats.duplicate(true),
			"bridge": EconomyBridge.MODEL_VERSION}
	var result := {"ok": true, "scenario": String(sc.get("name", "bez_nazvu")), "seed": seed_i, "days": days,
		"agents": names, "condition": cond, "snapshots": snaps, "stats": stats,
		"interventions": sc.get("interventions", []), "summary": summarize(snaps, first_iv),
		"final_hash": _hash_state(w),
		"model": {"version": MODEL_VERSION, "step_minutes": STEP_MINUTES,
			"note": "Fiktivní agenti; výsledky platí v rámci modelu. Část parametrů je herní balance."}}
	if eco_on:
		result["economy"] = eco_out
	w.queue_free()
	Main.household_override = prev_override
	clock.running = prev_running
	settings.persist = prev_persist
	await host.get_tree().process_frame
	return result


static func _apply_intervention(w: Node, e: Dictionary) -> void:
	var target := String(e.get("target", "all"))
	for sim in w.sims:
		if target == "all" or String(sim.sim_name) == target:
			sim.mental.on_stressor("life", float(e["amount"]), sim.mental_cfg())


static func _r(v: float) -> float:
	return snappedf(v, 0.0001)


static func _snapshot(w: Node, day: float) -> Dictionary:
	var agents := {}
	for a in w.sims:
		var rel := {}
		for b in w.sims:
			if a != b:
				rel[String(b.sim_name)] = _r(float(a.relationships.get(b.sim_name, 0.0)))
		var emo := {}
		for k in a.emotions.levels:
			emo[String(k)] = _r(float(a.emotions.levels[k]))
		agents[String(a.sim_name)] = {"stress": _r(float(a.mental.stress)), "mood": _r(float(a.get_mood_value())),
			"relationships": rel, "emotions": emo}
		if w.dynamics.economy_bridge != null:   # jen u zapnuté ekonomiky; jinak se formát snímků nemění
			var ev: Dictionary = w.dynamics.economy_bridge.view(String(a.sim_name))
			agents[String(a.sim_name)]["economy"] = {"pressure": _r(float(ev.get("pressure", 0.0))), "worry": _r(float(ev.get("worry", 0.0))),
				"portfolio_value": int(ev.get("portfolio_value", 0))}
	return {"day": _r(day), "agents": agents, "talks": int(w.dynamics.stats.get("talks", 0)),
		"arguments": int(w.dynamics.stats.get("argues", 0))}


static func _hash_state(w: Node) -> String:
	var parts := PackedStringArray()
	for a in w.sims:
		parts.append(String(a.sim_name))
		parts.append("%.6f" % float(a.mental.stress))
		parts.append("%.6f" % float(a.get_mood_value()))
		for b in w.sims:
			if a != b:
				parts.append("%.6f" % float(a.relationships.get(b.sim_name, 0.0)))
		for k in a.emotions.levels:
			parts.append("%s=%.6f" % [k, float(a.emotions.levels[k])])
	parts.append(JSON.stringify(w.dynamics.stats))
	return "|".join(parts).sha256_text()


## Souhrnné metriky z denních snímků (průměry přes agenty): stres, nálada, přátelství, vyhrocení stresu.
static func summarize(snaps: Array, first_iv_day: float = -1.0) -> Dictionary:
	var stress_sum := 0.0
	var mood_sum := 0.0
	var rel_sum := 0.0
	var n := 0
	var rel_n := 0
	var high_stress := 0
	for s in snaps:
		for nm in s["agents"]:
			var ag: Dictionary = s["agents"][nm]
			stress_sum += float(ag["stress"])
			mood_sum += float(ag["mood"])
			n += 1
			if float(ag["stress"]) >= 70.0:
				high_stress += 1
			for o in ag["relationships"]:
				rel_sum += float(ag["relationships"][o])
				rel_n += 1
	var peak := 0.0
	var post_sum := 0.0
	var post_n := 0
	for s2 in snaps:
		for nm2 in s2["agents"]:
			var st := float(s2["agents"][nm2]["stress"])
			peak = maxf(peak, st)
			if first_iv_day >= 0.0 and float(s2["day"]) > first_iv_day:
				post_sum += st
				post_n += 1
	var last: Dictionary = snaps[-1]
	var fs := 0.0
	var fm := 0.0
	var fr := 0.0
	var fn := 0
	var fk := 0
	for nm in last["agents"]:
		var ag2: Dictionary = last["agents"][nm]
		fs += float(ag2["stress"])
		fm += float(ag2["mood"])
		fn += 1
		for o in ag2["relationships"]:
			fr += float(ag2["relationships"][o])
			fk += 1
	var talks := int(last.get("talks", 0))
	var args := int(last.get("arguments", 0))
	return {"mean_stress": snappedf(stress_sum / maxf(1.0, n), 0.001), "mean_mood": snappedf(mood_sum / maxf(1.0, n), 0.001),
		"mean_relationship": snappedf(rel_sum / maxf(1.0, rel_n), 0.001),
		"high_stress_share": snappedf(float(high_stress) / maxf(1.0, n), 0.0001),
		"final_stress": snappedf(fs / maxf(1.0, fn), 0.001), "final_mood": snappedf(fm / maxf(1.0, fn), 0.001),
		"final_relationship": snappedf(fr / maxf(1.0, fk), 0.001),
		"peak_stress": snappedf(peak, 0.001), "mean_stress_post": snappedf(post_sum / maxf(1.0, post_n), 0.001),
		"talks": talks, "arguments": args, "argument_share": snappedf(float(args) / maxf(1.0, talks), 0.0001)}
