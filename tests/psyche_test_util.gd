extends RefCounted
## Společné pomůcky pro testy rozšíření psychiky (psychika A–H): domácnost se soukromým `mind`,
## deterministický běh, statistiky akcí a otisk stavu. Nic z toho není herní kód.

const Main := preload("res://main.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")


## Výchozí domácnost (3 postavy, pevná uid) s přepsanými poli `mind` podle indexu: {0: {"neuro": {...}}}.
static func household(mind_overrides: Dictionary = {}, trait_overrides: Dictionary = {}) -> Array:
	var hh: Array = (Main.HOUSEHOLD as Array).duplicate(true)
	for i in hh.size():
		var e: Dictionary = hh[i]
		if mind_overrides.has(i):
			var m: Dictionary = (e.get("mind", {}) as Dictionary).duplicate(true)
			for k in mind_overrides[i]:
				m[k] = mind_overrides[i][k]
			e["mind"] = m
		if trait_overrides.has(i):
			var p: Dictionary = (e.get("personality", {}) as Dictionary).duplicate(true)
			p["traits"] = trait_overrides[i]
			e["personality"] = p
	return hh


## Nový offline svět (bez grafiky) s danou domácností. Volající ho přidá do stromu a po testu uvolní.
static func make_world(hh: Array, clock: Node, start_minutes: float = 480.0) -> Node3D:
	Main.household_override = hh
	clock.running = false
	clock.total_minutes = start_minutes
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var w := Node3D.new()
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autoload": false, "autosave": false, "clock": clock}
	return w


static func run_minutes(clock: Node, minutes: float, step: float = 2.0) -> void:
	var left := minutes
	while left > 0.0:
		var s := minf(step, left)
		clock.advance(s)
		left -= s


## Otisk chování: počty akcí každé postavy (seřazeně) – pro determinismus a rozmanitost.
static func action_fingerprint(world: Node) -> Dictionary:
	var out := {}
	for s in world.sims:
		var counts: Dictionary = s.action_counts
		var keys: Array = counts.keys()
		keys.sort()
		var row := {}
		for k in keys:
			row[k] = int(counts[k])
		out[s.sim_name] = row
	return out


## Validní CharacterData slovník z položky domácnosti (pro validátor / snapshot testy).
static func character(entry_index: int, mind: Dictionary = {}) -> Dictionary:
	var hh := household({entry_index: mind})
	var e: Dictionary = hh[entry_index]
	var d := Schema.defaults()
	for g in e:
		if typeof(e[g]) == TYPE_DICTIONARY and d.has(g) and g != "clothing":
			d[g].merge(e[g], true)
		elif g != "clothing":
			d[g] = e[g]
	d["v"] = Schema.VERSION
	return d


## Rekurzivně: obsahuje slovník/pole některý z klíčů (pro testy soukromí)?
static func contains_key(v: Variant, keys: Array) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			if keys.has(String(k)) or contains_key(v[k], keys):
				return true
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			if contains_key(x, keys):
				return true
	return false
