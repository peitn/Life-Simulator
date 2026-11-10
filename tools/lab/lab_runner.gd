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
## ROZŠÍŘENÍ M1b (vše volitelné a zpětně kompatibilní; bez nich je běh bit-for-bit shodný s M1a):
##   long_run: bool – dovolí days až 400 (jinak platí 1..60)
##   household_file: "res://…json" | absolutní cesta – pole postav (formát Main.HOUSEHOLD), použije se, když chybí `household`
##   population_file: JSON z tools/lab/make_valley.py: {agents{jméno:{household,community,group,age,profile,tier,job,skill,endowment,…}},
##     relations[[a,b,v]], groups, communities, households}; aplikuje počáteční vztahy (oba směry) a umožní selektory skupin
##   settings: {mental_health, intrusive_thoughts, distortion_fx, distortion_strength, addiction, profanity, sh_ed_topics, adult_intimacy}
##     → GameSettings pro celý běh (po skončení se vrací původní hodnota `persist`; nastavení se neukládá na disk)
##   snapshot_mode: "full" (výchozí) | "compact" (pole po agentech, bez matice vztahů a 19 emocí; pro velké populace)
##   progress: bool – tiskne řádky LAB_PROGRESS (den, uplynulý reálný čas) při každém snímku
##   economy.use_population: bool – ekonomika agentů (bydlení, práce, jmění, investorský profil) z population_file
##   economy.events: [{type: path|vol|div_cut|rates|layoffs, day, …}] – události burzy/ekonomiky (viz docs/economy_market.md)
##   interventions: kind "stressor" | "moodlet" {strength -30..30, minutes, emotion, label} | "relation" {a, b, delta -40..40};
##     target/a/b = "all" | jméno | "group:id" | "community:id" | "household:id" | "profile:id" | "age:lo-hi" | "wealth:0..3" | "pred:id" | pole selektorů
##   checkpoint_in / checkpoint_out: cesta k binárnímu checkpointu (var_to_bytes; JSON text by u desetinných čísel nebyl bit-přesný);
##   stop_day: 1..days – po tomto dni běh skončí a zapíše checkpoint_out; checkpoint_in běh obnoví (stav světa přes GameSave.capture/apply,
##   ekonomika, drby, vztahy, hodiny; výsledek segmentu obsahuje snímky jen od počátku segmentu). Scénář musí být shodný (hash se kontroluje).
## Výsledek: {"ok", "scenario", "seed", "days", "agents": [jména], "snapshots": [...], "final_hash": String,
##            "stats": household statistiky, "model": {...verze/provenance}}
## Všechna data jsou fiktivní agenti. Výsledky platí jen v rámci modelu, ne pro lidi.

const Main := preload("res://main.gd")
const EconomyBridge := preload("res://scripts/sim/economy_bridge.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const GameSave := preload("res://scripts/save/game_save.gd")
const STEP_MINUTES := 2.0
const MODEL_VERSION := "lab-m1b-0.2"
const MAX_DAYS := 60
const MAX_DAYS_LONG := 400
const SETTINGS_KEYS := ["mental_health", "intrusive_thoughts", "distortion_fx", "distortion_strength", "addiction", "profanity",
	"sh_ed_topics", "adult_intimacy"]
const SELECTOR_PREFIXES := ["group", "community", "household", "profile", "age", "wealth", "pred"]
const IV_KINDS := ["stressor", "moodlet", "relation"]
const CHECKPOINT_MAX_SIMS := 512
const CHECKPOINT_VERSION := 1


## JSON čte všechna čísla jako float; celé číslo = int nebo float bez desetinné části.
static func _is_whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and floorf(v) == v)


static func _is_num(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


static func _load_json(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Populace ze souboru (nebo {}). Neplatný/nenalezený soubor vrací {} (validate to hlásí zvlášť).
static func _population(sc: Dictionary) -> Dictionary:
	if not sc.has("population_file"):
		return {}
	var p = _load_json(String(sc["population_file"]))
	return p if typeof(p) == TYPE_DICTIONARY else {}


## Zkontroluje selektor (String | Array Stringů); vrací pole chyb. pop = {} → jména se nekontrolují.
static func _check_selector(sel: Variant, pop: Dictionary, what: String) -> Array:
	var errs: Array = []
	var items: Array = []
	if typeof(sel) == TYPE_STRING:
		items = [sel]
	elif typeof(sel) == TYPE_ARRAY and not (sel as Array).is_empty():
		items = sel
	else:
		return ["%s: selektor musí být řetězec nebo neprázdné pole" % what]
	var agents: Dictionary = pop.get("agents", {})
	for it in items:
		if typeof(it) != TYPE_STRING or String(it) == "":
			errs.append("%s: selektor musí být neprázdný řetězec" % what)
			continue
		var t := String(it)
		if t == "all":
			continue
		if t.find(":") > 0:
			var pre := t.get_slice(":", 0)
			var arg := t.substr(pre.length() + 1)
			if not SELECTOR_PREFIXES.has(pre):
				errs.append("%s: neznámý selektor %s" % [what, t])
				continue
			if pop.is_empty():
				errs.append("%s: selektor %s vyžaduje population_file" % [what, t])
				continue
			var ok := false
			for nm in agents:
				if _matches(agents[nm], pre, arg):
					ok = true
					break
			if pre == "age":
				var parts := arg.split("-")
				ok = parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() and int(parts[0]) <= int(parts[1])
			if not ok:
				errs.append("%s: selektor %s nevybere žádného agenta" % [what, t])
		elif not pop.is_empty() and not agents.has(t):
			errs.append("%s: neznámý agent %s" % [what, t])
	return errs


static func _matches(a: Dictionary, pre: String, arg: String) -> bool:
	match pre:
		"group": return String(a.get("group", "")) == arg
		"community": return String(a.get("community", "")) == arg
		"household": return String(a.get("household", "")) == arg
		"profile": return String(a.get("profile", "")) == arg
		"wealth": return arg.is_valid_int() and int(a.get("wealth_class", -1)) == int(arg)
		"pred": return (a.get("predispositions", []) as Array).has(arg)
		"age":
			var parts := arg.split("-")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				return false
			var ag := int(a.get("age", -1))
			return ag >= int(parts[0]) and ag <= int(parts[1])
	return false


## Vybere agenty (ve stabilním pořadí světa) podle selektoru; unikátní.
static func _select(sims: Array, pop: Dictionary, sel: Variant) -> Array:
	var items: Array = [sel] if typeof(sel) == TYPE_STRING else (sel as Array)
	var agents: Dictionary = pop.get("agents", {})
	var out: Array = []
	for sim in sims:
		var nm := String(sim.sim_name)
		var hit := false
		for it in items:
			var t := String(it)
			if t == "all" or t == nm:
				hit = true
			elif t.find(":") > 0 and agents.has(nm):
				var pre := t.get_slice(":", 0)
				if _matches(agents[nm], pre, t.substr(pre.length() + 1)):
					hit = true
			if hit:
				break
		if hit:
			out.append(sim)
	return out


static func validate(sc: Dictionary) -> Array:
	var errs: Array = []
	var long_run: bool = bool(sc.get("long_run", false))
	if sc.has("long_run") and typeof(sc["long_run"]) != TYPE_BOOL:
		errs.append("long_run musí být bool")
	if not _is_whole(sc.get("seed", null)):
		errs.append("seed musí být celé číslo")
	var days = sc.get("days", 0)
	var max_days := MAX_DAYS_LONG if long_run else MAX_DAYS
	if not _is_whole(days) or int(days) < 1 or int(days) > max_days:
		errs.append("days musí být 1..%d" % max_days)
	var hrs = sc.get("snapshot_hours", 24)
	if not _is_whole(hrs) or int(hrs) < 1 or int(hrs) > 24 or 24 % int(hrs) != 0:
		errs.append("snapshot_hours musí dělit 24")
	if sc.has("household") and typeof(sc["household"]) != TYPE_ARRAY:
		errs.append("household musí být pole")
	if sc.has("household_file"):
		var hf = _load_json(String(sc["household_file"])) if typeof(sc["household_file"]) == TYPE_STRING else null
		if typeof(hf) != TYPE_ARRAY or (hf as Array).is_empty():
			errs.append("household_file musí ukazovat na JSON pole postav")
	var pop: Dictionary = {}
	if sc.has("population_file"):
		pop = _population(sc)
		if pop.is_empty() or typeof(pop.get("agents", null)) != TYPE_DICTIONARY or typeof(pop.get("relations", null)) != TYPE_ARRAY:
			errs.append("population_file musí ukazovat na JSON s klíči agents a relations")
			pop = {}
	for ck in ["checkpoint_in", "checkpoint_out"]:
		if sc.has(ck) and (typeof(sc[ck]) != TYPE_STRING or String(sc[ck]) == ""):
			errs.append("%s musí být cesta" % ck)
	if sc.has("stop_day") and (not _is_whole(sc["stop_day"]) or int(sc["stop_day"]) < 1 or (_is_whole(days) and int(sc["stop_day"]) > int(days))):
		errs.append("stop_day musí být 1..days")
	if sc.has("stop_day") and not sc.has("checkpoint_out"):
		errs.append("stop_day vyžaduje checkpoint_out")
	if sc.has("block"):
		var blks: Dictionary = pop.get("blocks", {}) if typeof(pop.get("blocks", null)) == TYPE_DICTIONARY else {}
		if typeof(sc["block"]) != TYPE_STRING or not blks.has(String(sc["block"])):
			errs.append("block musí být id bloku z population_file.blocks")
	if sc.has("snapshot_mode") and not ["full", "compact"].has(String(sc["snapshot_mode"])):
		errs.append("snapshot_mode musí být full nebo compact")
	if sc.has("progress") and typeof(sc["progress"]) != TYPE_BOOL:
		errs.append("progress musí být bool")
	if sc.has("settings"):
		errs.append_array(_validate_settings(sc["settings"]))
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
		errs.append_array(_validate_economy(sc["economy"], sc.get("days", 0), not pop.is_empty()))
	var iv = sc.get("interventions", [])
	if typeof(iv) != TYPE_ARRAY:
		errs.append("interventions musí být pole")
	else:
		for e in iv:
			var ie := _validate_intervention(e, sc.get("days", 0), pop)
			if not ie.is_empty():
				errs.append_array(ie)
				break
	return errs


static func _validate_settings(st: Variant) -> Array:
	var errs: Array = []
	if typeof(st) != TYPE_DICTIONARY:
		return ["settings musí být objekt"]
	for k in st:
		var key := String(k)
		var v: Variant = st[k]
		if not SETTINGS_KEYS.has(key):
			errs.append("settings: neznámý klíč %s" % key)
		elif key == "mental_health":
			if typeof(v) != TYPE_STRING or not ["full", "muted", "off"].has(String(v)):
				errs.append("settings.mental_health musí být full|muted|off")
		elif key == "intrusive_thoughts":
			if not _is_whole(v) or int(v) < 0 or int(v) > 3:
				errs.append("settings.intrusive_thoughts musí být 0..3")
		elif key == "distortion_strength":
			if not _is_num(v) or float(v) < 0.0 or float(v) > 1.0:
				errs.append("settings.distortion_strength musí být 0..1")
		elif typeof(v) != TYPE_BOOL:
			errs.append("settings.%s musí být bool" % key)
	return errs


static func _validate_intervention(e: Variant, days: Variant, pop: Dictionary) -> Array:
	var bad := ["intervence musí být {day 0..days, kind 'stressor', amount 0..100, target}"]
	if typeof(e) != TYPE_DICTIONARY:
		return bad
	var kind := String(e.get("kind", ""))
	if not IV_KINDS.has(kind):
		return bad
	if not _is_num(e.get("day", null)) or float(e["day"]) < 0.0 or float(e["day"]) > float(days if _is_num(days) else 0):
		return bad
	var errs: Array = []
	if kind == "stressor":
		if not _is_num(e.get("amount", null)) or float(e["amount"]) < 0.0 or float(e["amount"]) > 100.0:
			return bad
		if e.has("target"):
			errs.append_array(_check_selector(e["target"], pop, "intervence.target"))
	elif kind == "moodlet":
		if not _is_num(e.get("strength", null)) or absf(float(e["strength"])) > 30.0 or float(e["strength"]) == 0.0:
			errs.append("moodlet.strength musí být -30..30, nenulové")
		if not _is_num(e.get("minutes", null)) or float(e["minutes"]) < 30.0 or float(e["minutes"]) > 10080.0:
			errs.append("moodlet.minutes musí být 30..10080")
		if typeof(e.get("emotion", null)) != TYPE_STRING or not (MoodScript.EMOTIONS as Dictionary).has(String(e["emotion"])):
			errs.append("moodlet.emotion musí být známá emoce")
		if typeof(e.get("label", null)) != TYPE_STRING or String(e["label"]) == "" or String(e["label"]).length() > 40:
			errs.append("moodlet.label musí být text 1..40 znaků")
		errs.append_array(_check_selector(e.get("target", "all"), pop, "moodlet.target"))
	elif kind == "relation":
		if not _is_num(e.get("delta", null)) or absf(float(e["delta"])) > 40.0 or float(e["delta"]) == 0.0:
			errs.append("relation.delta musí být -40..40, nenulová")
		errs.append_array(_check_selector(e.get("a", null), pop, "relation.a"))
		errs.append_array(_check_selector(e.get("b", null), pop, "relation.b"))
	return errs


static func _validate_economy(eco: Variant, days: Variant, has_pop: bool = false) -> Array:
	var errs: Array = []
	if typeof(eco) != TYPE_DICTIONARY:
		return ["economy musí být objekt"]
	for k in eco:
		if not ["enabled", "market", "seed", "shock", "events", "use_population"].has(String(k)):
			errs.append("economy: neznámý klíč %s" % String(k))
	if eco.has("enabled") and typeof(eco["enabled"]) != TYPE_BOOL:
		errs.append("economy.enabled musí být bool")
	if eco.has("market") and typeof(eco["market"]) != TYPE_BOOL:
		errs.append("economy.market musí být bool")
	if eco.has("use_population"):
		if typeof(eco["use_population"]) != TYPE_BOOL:
			errs.append("economy.use_population musí být bool")
		elif bool(eco["use_population"]) and not has_pop:
			errs.append("economy.use_population vyžaduje population_file")
	if eco.has("seed") and (not _is_whole(eco["seed"]) or absf(float(eco["seed"])) > 1.0e9):
		errs.append("economy.seed musí být celé číslo")
	if eco.has("events"):
		if typeof(eco["events"]) != TYPE_ARRAY:
			errs.append("economy.events musí být pole")
		else:
			if not bool(eco.get("market", false)) or not bool(eco.get("enabled", false)):
				errs.append("economy.events vyžaduje enabled i market")
			var ee: String = EconomyBridge.Economy.StockMarket.validate_events(eco["events"])
			if ee != "":
				errs.append("economy.events: " + ee)
			elif _is_whole(days):
				for ev in eco["events"]:
					if int(ev["day"]) > int(days):
						errs.append("economy.events: day musí být 1..days")
						break
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
static func _bridge_cfg(eco: Dictionary, sc_seed: int, pop: Dictionary = {}) -> Dictionary:
	var c := {"seed": int(eco.get("seed", sc_seed)), "market": bool(eco.get("market", false))}
	var evs: Array = []
	if eco.has("shock"):
		var sh: Dictionary = eco["shock"]
		evs.append({"type": "path", "day": int(sh["day"]), "days": int(sh["days"]), "total_pm": int(sh["total_pm"]), "scope": "market"})
	for ev in eco.get("events", []):
		evs.append((ev as Dictionary).duplicate(true))
	if not evs.is_empty():
		c["events"] = evs
	if bool(eco.get("use_population", false)) and not pop.is_empty():
		var ag := {}
		for nm in pop["agents"]:
			var a: Dictionary = pop["agents"][nm]
			var o := {"tier": String(a["tier"]), "qualification": int(a["skill"]), "job": String(a["job"]), "endowment": int(a["endowment"]),
				"household": String(a["household"]), "shift_off": int(a.get("shift_off", 0))}
			if bool(eco.get("market", false)):
				o["profile"] = String(a["profile"])
			ag[String(nm)] = o
		c["agents"] = ag
		c["register_all"] = true
	return c


## Otisk scénáře bez klíčů segmentace (checkpoint musí patřit ke stejnému scénáři).
static func scenario_hash(sc: Dictionary) -> String:
	var c := sc.duplicate(true)
	for k in ["checkpoint_in", "checkpoint_out", "stop_day", "progress"]:
		c.erase(k)
	return JSON.stringify(c, "", true, true).sha256_text()


## Připraví svět podle scénáře (stejné pořadí kroků jako M1a). Vrací kontext pro _close.
static func _open(host: Node, sc: Dictionary) -> Dictionary:
	var clock = host.get_node("/root/GameClock")
	var settings = host.get_node("/root/GameSettings")
	var ctx := {"clock": clock, "settings": settings, "prev_running": clock.running, "prev_persist": settings.persist,
		"prev_override": Main.household_override, "prev_values": settings.values.duplicate(true)}
	clock.running = false
	settings.persist = false
	settings.reset()
	for k in sc.get("settings", {}):
		settings.set_value(String(k), sc["settings"][k], false)
	var seed_i := int(sc["seed"])
	clock.total_minutes = float(sc.get("start_minutes", 480.0))
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var hh = sc.get("household", [])
	if (hh as Array).is_empty() and sc.has("household_file"):
		hh = _load_json(String(sc["household_file"]))
	var pop0 := _population(sc)
	var gidx := {}   # jméno → globální pořadí v populaci (seed postavy nezávisí na tom, v jakém bloku běží)
	var block_members: Array = []
	if sc.has("block") and not pop0.is_empty():
		block_members = pop0["blocks"][String(sc["block"])]["members"]
		var keep: Array = []
		for ch in hh:
			var nm0 := ("%s %s" % [ch["identity"]["first_name"], ch["identity"].get("last_name", "")]).strip_edges()
			if block_members.has(nm0):
				keep.append(ch)
		hh = keep
		for i in (pop0.get("order", []) as Array).size():
			gidx[String(pop0["order"][i])] = i
	Main.household_override = hh
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "LabWorld"
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false}
	host.add_child(w)
	ctx["w"] = w
	var n := 0
	for sim in w.sims:
		var gi: int = int(gidx.get(String(sim.sim_name), n)) if not gidx.is_empty() else n
		sim.rng.seed = seed_i * 7919 + gi * 104729 + 13
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
	var pop := _population(sc)
	ctx["pop"] = pop
	if not pop.is_empty():
		var by_name := {}
		for sim in w.sims:
			by_name[String(sim.sim_name)] = sim
		ctx["missing"] = []
		for nm in pop["agents"]:
			if not by_name.has(String(nm)) and (block_members.is_empty() or block_members.has(String(nm))):
				(ctx["missing"] as Array).append(String(nm))
		for r in pop["relations"]:
			var a = by_name.get(String(r[0]), null)
			var b = by_name.get(String(r[1]), null)
			if a != null and b != null:
				a.relationships[b.sim_name] = clampf(float(r[2]), -100.0, 100.0)
				b.relationships[a.sim_name] = clampf(float(r[2]), -100.0, 100.0)
	var eco_sc: Dictionary = sc.get("economy", {})
	ctx["eco_sc"] = eco_sc
	ctx["eco_on"] = bool(eco_sc.get("enabled", false))
	if ctx["eco_on"]:
		w.dynamics.economy_bridge = EconomyBridge.new(_bridge_cfg(eco_sc, seed_i, pop))
	return ctx


static func _close(host: Node, ctx: Dictionary) -> void:
	ctx["w"].queue_free()
	Main.household_override = ctx["prev_override"]
	ctx["clock"].running = ctx["prev_running"]
	ctx["settings"].persist = ctx["prev_persist"]
	ctx["settings"].values = ctx["prev_values"]   # nastavení z `settings` scénáře nepřežije běh (hostitelský proces dostane původní)
	await host.get_tree().process_frame


## Spustí scénář pod `host` (uzel ve stromu, přes který se čeká na snímky). Vrací výsledek.
static func run(host: Node, sc: Dictionary) -> Dictionary:
	var errs := validate(sc)
	if not errs.is_empty():
		return {"ok": false, "errors": errs}
	var ctx := _open(host, sc)
	var w: Node = ctx["w"]
	var clock = ctx["clock"]
	var pop: Dictionary = ctx["pop"]
	if not (ctx.get("missing", []) as Array).is_empty():
		await _close(host, ctx)
		return {"ok": false, "errors": ["population_file: agenti nejsou v domácnosti: %s" % str(ctx["missing"])]}
	var seed_i := int(sc["seed"])
	var days := int(sc["days"])
	var snap_h := int(sc.get("snapshot_hours", 24))
	var i0 := 0
	var resume_hash := ""
	var prev_applied: Array = []
	if sc.has("checkpoint_in"):
		var cp = _read_checkpoint(String(sc["checkpoint_in"]))
		if typeof(cp) != TYPE_DICTIONARY or int(cp.get("v", -1)) != CHECKPOINT_VERSION:
			await _close(host, ctx)
			return {"ok": false, "errors": ["checkpoint_in: soubor chybí nebo je neplatný"]}
		if String(cp.get("scenario_hash", "")) != scenario_hash(sc):
			await _close(host, ctx)
			return {"ok": false, "errors": ["checkpoint_in: patří k jinému scénáři"]}
		var ap: Dictionary = GameSave.apply(w, cp["game"], false, CHECKPOINT_MAX_SIMS)
		if not bool(ap.get("ok", false)):
			await _close(host, ctx)
			return {"ok": false, "errors": ["checkpoint_in: obnova selhala: %s" % str(ap.get("reason", "?"))]}
		w = ctx["w"]
		_restore_derived(w, cp.get("derived", {}))
		i0 = int(cp["step"])
		prev_applied = cp.get("applied", [])
		resume_hash = _hash_state(w)
		if resume_hash != String(cp.get("state_hash", "")):
			await _close(host, ctx)
			return {"ok": false, "errors": ["checkpoint_in: hash obnoveného stavu se liší od uloženého (%s != %s)" % [resume_hash, cp.get("state_hash", "")]]}
	var compact: bool = String(sc.get("snapshot_mode", "full")) == "compact"
	var progress: bool = bool(sc.get("progress", false))
	var cond: Dictionary = sc.get("condition", {})
	var eco_sc: Dictionary = ctx["eco_sc"]
	var eco_on: bool = ctx["eco_on"]
	var names: Array = []
	for sim in w.sims:
		names.append(String(sim.sim_name))
	var snaps: Array = []
	var day0 := float(i0) * STEP_MINUTES / 1440.0
	snaps.append(_snapshot_compact(w, day0) if compact else _snapshot(w, day0))
	var pending: Array = []
	for e in sc.get("interventions", []):
		if float(e["day"]) * 1440.0 > float(i0) * STEP_MINUTES or i0 == 0:
			pending.append(e.duplicate(true))
	pending.sort_custom(func(x, y): return float(x["day"]) < float(y["day"]))
	var first_iv := float(pending[0]["day"]) if not pending.is_empty() else -1.0
	if eco_on and eco_sc.has("shock") and first_iv < 0.0:
		first_iv = float(eco_sc["shock"]["day"])
	var steps_per_snap := int(snap_h * 60 / STEP_MINUTES)
	var total_steps := int(days * 1440 / STEP_MINUTES)
	var stop_step := total_steps
	if sc.has("stop_day"):
		stop_step = int(int(sc["stop_day"]) * 1440 / STEP_MINUTES)
	var t0 := Time.get_ticks_msec()
	var applied: Array = prev_applied.duplicate(true)
	for i in range(i0, stop_step):
		clock.advance(STEP_MINUTES)
		while not pending.is_empty() and float(pending[0]["day"]) * 1440.0 <= float(i + 1) * STEP_MINUTES:
			var iv: Dictionary = pending.pop_front()
			var nhit := _apply_intervention(w, iv, pop)
			if compact:
				applied.append({"day": float(iv["day"]), "kind": String(iv["kind"]), "label": String(iv.get("label", "")), "affected": nhit})
		if (i + 1) % steps_per_snap == 0:
			snaps.append(_snapshot_compact(w, float(i + 1) * STEP_MINUTES / 1440.0) if compact else _snapshot(w, float(i + 1) * STEP_MINUTES / 1440.0))
			if progress:
				print("LAB_PROGRESS day=%.2f elapsed_s=%.1f" % [float(i + 1) * STEP_MINUTES / 1440.0, float(Time.get_ticks_msec() - t0) / 1000.0])
	var cp_info: Dictionary = {}
	if sc.has("checkpoint_out"):
		var cap: Dictionary = GameSave.capture(w, false, CHECKPOINT_MAX_SIMS)
		if not bool(cap.get("ok", false)):
			await _close(host, ctx)
			return {"ok": false, "errors": ["checkpoint_out: zachycení stavu selhalo: %s" % str(cap.get("reason", "?"))]}
		var sh := _hash_state(w)
		var blob := {"v": CHECKPOINT_VERSION, "scenario_hash": scenario_hash(sc), "step": stop_step, "applied": applied,
			"state_hash": sh, "game": cap["data"], "derived": _derived_state(w)}
		var bytes := var_to_bytes(blob)
		var f := FileAccess.open(String(sc["checkpoint_out"]), FileAccess.WRITE)
		if f == null:
			await _close(host, ctx)
			return {"ok": false, "errors": ["checkpoint_out: nelze zapsat soubor"]}
		f.store_buffer(bytes)
		f.close()
		cp_info = {"path": String(sc["checkpoint_out"]), "bytes": bytes.size(), "step": stop_step, "state_hash": sh}
	var stats: Dictionary = w.dynamics.stats.duplicate(true)
	var eco_out: Dictionary = {}
	if eco_on:
		eco_out = {"enabled": true, "market": bool(eco_sc.get("market", false)), "stats": w.dynamics.economy_bridge.stats.duplicate(true),
			"bridge": EconomyBridge.MODEL_VERSION}
	var result := {"ok": true, "scenario": String(sc.get("name", "bez_nazvu")), "seed": seed_i, "days": days,
		"agents": names, "condition": cond, "snapshots": snaps, "stats": stats,
		"interventions": sc.get("interventions", []),
		"summary": summarize_compact(snaps, first_iv) if compact else summarize(snaps, first_iv),
		"final_hash": _hash_state(w),
		"model": {"version": MODEL_VERSION, "step_minutes": STEP_MINUTES,
			"note": "Fiktivní agenti; výsledky platí v rámci modelu. Část parametrů je herní balance."}}
	if eco_on:
		result["economy"] = eco_out
	if sc.has("checkpoint_in") or sc.has("checkpoint_out"):
		result["segment"] = {"start_step": i0, "stop_step": stop_step, "start_day": day0,
			"stop_day": float(stop_step) * STEP_MINUTES / 1440.0, "complete": stop_step == total_steps,
			"resume_hash": resume_hash, "checkpoint_out": cp_info}
	if compact:
		result["applied_interventions"] = applied
		result["gossip_stats"] = (w.gossip.stats as Dictionary).duplicate(true)
		result["settings"] = (ctx["settings"].values as Dictionary).duplicate(true)
		var src := {}
		for a in w.sims:
			for k in a.mental.stress_sources:
				src[String(k)] = snappedf(float(src.get(String(k), 0.0)) + float(a.mental.stress_sources[k]), 0.01)
		result["stress_sources_total"] = src   # kumulativní příspěvky k stresu podle zdroje (součet přes agenty od startu světa)
		result["world"] = {"smart_objects": w.smart_objects.size(), "agents": w.sims.size()}
		result["elapsed_s"] = float(Time.get_ticks_msec() - t0) / 1000.0
	await _close(host, ctx)
	return result


## Měření výkonu: rozloží reálný čas `minutes` herních minut na sim_tick agentů, dynamiku domácnosti a zbytek.
static func probe(host: Node, sc: Dictionary, minutes: float) -> Dictionary:
	var errs := validate(sc)
	if not errs.is_empty():
		return {"ok": false, "errors": errs}
	var ctx := _open(host, sc)
	var w: Node = ctx["w"]
	var clock = ctx["clock"]
	# odpojit sim_tick i dynamiku od hodin, volat ručně a měřit zvlášť
	for sim in w.sims:
		if clock.time_advanced.is_connected(sim.sim_tick):
			clock.time_advanced.disconnect(sim.sim_tick)
	var dyn_cb := Callable(w, "_on_time_advanced")
	if clock.time_advanced.is_connected(dyn_cb):
		clock.time_advanced.disconnect(dyn_cb)
	var steps := int(minutes / STEP_MINUTES)
	var t_sim := 0
	var t_dyn := 0
	var t_adv := 0
	var t_all := Time.get_ticks_usec()
	var windows: Array = []   # reálné sekundy po oknech 360 herních minut (růst nákladů v čase)
	var t_win := t_all
	for i in steps:
		var a := Time.get_ticks_usec()
		clock.advance(STEP_MINUTES)
		var b := Time.get_ticks_usec()
		for sim in w.sims:
			sim.sim_tick(STEP_MINUTES)
		var c := Time.get_ticks_usec()
		w._on_time_advanced(STEP_MINUTES)
		var d := Time.get_ticks_usec()
		t_adv += b - a
		t_sim += c - b
		t_dyn += d - c
		if (i + 1) % 180 == 0:
			windows.append(snappedf(float(d - t_win) / 1.0e6, 0.001))
			t_win = d
	var total := Time.get_ticks_usec() - t_all
	var n: int = w.sims.size()
	var out := {"ok": true, "agents": n, "game_minutes": minutes, "steps": steps, "total_s": float(total) / 1.0e6,
		"sim_tick_s": float(t_sim) / 1.0e6, "dynamics_s": float(t_dyn) / 1.0e6, "clock_other_s": float(t_adv) / 1.0e6,
		"per_agent_tick_us": float(t_sim) / maxf(1.0, float(steps * n)),
		"est_s_per_game_day": float(total) / 1.0e6 * 1440.0 / maxf(1.0, minutes), "windows_360min_s": windows, "prof": (load("res://scripts/sim/sim_agent.gd").PROF if "PROF" in load("res://scripts/sim/sim_agent.gd") else {})}
	await _close(host, ctx)
	return out


## Aplikuje intervenci; vrací počet zasažených agentů.
static func _apply_intervention(w: Node, e: Dictionary, pop: Dictionary = {}) -> int:
	var kind := String(e.get("kind", "stressor"))
	if kind == "stressor":
		var hit := _select(w.sims, pop, e.get("target", "all"))
		for sim in hit:
			sim.mental.on_stressor("life", float(e["amount"]), sim.mental_cfg())
		return hit.size()
	if kind == "moodlet":
		var hit2 := _select(w.sims, pop, e.get("target", "all"))
		var mid := "lab_%s" % String(e["label"]).to_lower().replace(" ", "_")
		for sim in hit2:
			if float(e["strength"]) > 0.0:
				sim.add_joy_moodlet(mid, String(e["label"]), String(e["emotion"]), float(e["strength"]), float(e["minutes"]))
			else:
				sim.mood.add_moodlet(mid, String(e["label"]), String(e["emotion"]), float(e["strength"]), float(e["minutes"]))
		return hit2.size()
	# relation: změna vztahu a odpovídající stopa v knize křivd (stejné rozhraní, jaké používají rozhovory)
	var group_a := _select(w.sims, pop, e["a"])
	var group_b := _select(w.sims, pop, e["b"])
	var delta := float(e["delta"])
	var now := float(w.clock.total_minutes)
	var done := {}
	var touched := {}
	for x in group_a:
		for y in group_b:
			if x == y:
				continue
			for pair in [[x, y], [y, x]]:
				var key := "%s|%s" % [pair[0].sim_name, pair[1].sim_name]
				if done.has(key):
					continue
				done[key] = true
				var p: Node = pair[0]
				var q: Node = pair[1]
				var old := float(p.relationships.get(q.sim_name, 0.0))
				var nv := clampf(old + delta, -100.0, 100.0)
				p.relationships[q.sim_name] = nv
				p.note_relationship_change(q, old, nv)
				if delta < 0.0:
					p.ledger.on_hurt_by(String(q.sim_name), -delta * 0.5, now)
				else:
					p.ledger.soften(String(q.sim_name), delta)
				touched[String(p.sim_name)] = true
	return touched.size()


## Odvozené veličiny, které GameSave neukládá, ale čte je další krok (nálada = výsledek posledního evaluate před akcemi kroku).
## Bez nich by obnova nebyla bit-přesná (rozdíl ~0,02 bodu nálady → jiná cesta RNG o pár kroků později).
static func _derived_state(w: Node) -> Dictionary:
	var out := {}
	for a in w.sims:
		out[String(a.sim_name)] = {"mood_value": a.mood.value, "mood_emotion": String(a.mood.emotion)}
	return out


static func _restore_derived(w: Node, d: Dictionary) -> void:
	for a in w.sims:
		var e: Dictionary = d.get(String(a.sim_name), {})
		if e.has("mood_value"):
			a.mood.value = float(e["mood_value"])
			a.mood.emotion = String(e["mood_emotion"])


static func _read_checkpoint(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var b := FileAccess.get_file_as_bytes(path)
	if b.is_empty():
		return null
	return bytes_to_var(b)


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


## Kompaktní snímek pro velké populace: pole po agentech v pořadí result["agents"]. Vztahy jen jako agregáty
## (průměr, počet záporných ≤ -10 a silných kladných ≥ 50), emoce jako dominantní označení.
static func _snapshot_compact(w: Node, day: float) -> Dictionary:
	var stress: Array = []
	var mood: Array = []
	var rel_mean: Array = []
	var rel_neg: Array = []
	var rel_pos: Array = []
	var emo: Array = []
	var pressure: Array = []
	var worry: Array = []
	var balance: Array = []
	var pv: Array = []
	var employed: Array = []
	var br = w.dynamics.economy_bridge
	for a in w.sims:
		stress.append(_r(float(a.mental.stress)))
		mood.append(_r(float(a.get_mood_value())))
		var sum := 0.0
		var neg := 0
		var pos := 0
		var n := 0
		for b in w.sims:
			if a != b:
				var v := float(a.relationships.get(b.sim_name, 0.0))
				sum += v
				n += 1
				if v <= -10.0:
					neg += 1
				elif v >= 50.0:
					pos += 1
		rel_mean.append(_r(sum / maxf(1.0, float(n))))
		rel_neg.append(neg)
		rel_pos.append(pos)
		emo.append(String(a.mood.emotion))
		if br != null:
			var ev: Dictionary = br.view(String(a.sim_name))
			pressure.append(_r(float(ev.get("pressure", 0.0))))
			worry.append(_r(float(ev.get("worry", 0.0))))
			balance.append(int(ev.get("balance", 0)))
			pv.append(int(ev.get("portfolio_value", 0)))
			if br.names.has(String(a.sim_name)):   # před prvním dnem ekonomiky agenti ještě nejsou zaregistrováni
				var av: Dictionary = br.eco.agent_view(String(br.names[String(a.sim_name)]))
				employed.append(1 if bool(av.get("employed", false)) else 0)
			else:
				employed.append(0)
	var s := {"day": _r(day), "stress": stress, "mood": mood, "rel_mean": rel_mean, "rel_neg": rel_neg, "rel_pos": rel_pos,
		"emotion": emo, "talks": int(w.dynamics.stats.get("talks", 0)), "arguments": int(w.dynamics.stats.get("argues", 0)),
		"events_good": int(w.dynamics.stats["events"]["good"]), "events_bad": int(w.dynamics.stats["events"]["bad"]),
		"rumors": (w.gossip.rumors as Dictionary).size(), "gossip_shared": int(w.gossip.stats.get("shared", 0))}
	if br != null:
		s["pressure"] = pressure
		s["worry"] = worry
		s["balance"] = balance
		s["portfolio_value"] = pv
		s["employed"] = employed
		s["econ"] = (br.eco.metrics() as Dictionary).duplicate(true)
		if br.eco.market != null:
			s["market_index_pm"] = int(br.eco.market.index_hist[-1]) if not br.eco.market.index_hist.is_empty() else 0
	return s


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


## Souhrn z kompaktních snímků (stejné klíče jako summarize, kromě peak/post, které se počítají stejně).
static func summarize_compact(snaps: Array, first_iv_day: float = -1.0) -> Dictionary:
	var stress_sum := 0.0
	var mood_sum := 0.0
	var rel_sum := 0.0
	var n := 0
	var high := 0
	var peak := 0.0
	var post_sum := 0.0
	var post_n := 0
	for s in snaps:
		var st: Array = s["stress"]
		for i in st.size():
			var v := float(st[i])
			stress_sum += v
			mood_sum += float(s["mood"][i])
			rel_sum += float(s["rel_mean"][i])
			n += 1
			if v >= 70.0:
				high += 1
			peak = maxf(peak, v)
			if first_iv_day >= 0.0 and float(s["day"]) > first_iv_day:
				post_sum += v
				post_n += 1
	var last: Dictionary = snaps[-1]
	var fs := 0.0
	var fm := 0.0
	var fr := 0.0
	var fn: int = (last["stress"] as Array).size()
	for i in fn:
		fs += float(last["stress"][i])
		fm += float(last["mood"][i])
		fr += float(last["rel_mean"][i])
	var talks := int(last.get("talks", 0))
	var args := int(last.get("arguments", 0))
	return {"mean_stress": snappedf(stress_sum / maxf(1.0, n), 0.001), "mean_mood": snappedf(mood_sum / maxf(1.0, n), 0.001),
		"mean_relationship": snappedf(rel_sum / maxf(1.0, n), 0.001), "high_stress_share": snappedf(float(high) / maxf(1.0, n), 0.0001),
		"final_stress": snappedf(fs / maxf(1.0, fn), 0.001), "final_mood": snappedf(fm / maxf(1.0, fn), 0.001),
		"final_relationship": snappedf(fr / maxf(1.0, fn), 0.001), "peak_stress": snappedf(peak, 0.001),
		"mean_stress_post": snappedf(post_sum / maxf(1.0, post_n), 0.001), "talks": talks, "arguments": args,
		"argument_share": snappedf(float(args) / maxf(1.0, talks), 0.0001)}
