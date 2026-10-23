extends Node3D
## Life Simulator – hlavní scéna. Postaví parcelu, postavy, kameru, HUD a denní cyklus
## a spustí síťovou relaci (offline / host / dedikovaný server / klient).
##
## Argumenty (za `--`):
##   --test [dny]            headless simulace offline + statistiky
##   --host [port]           listen server (hraješ a ostatní se připojují)
##   --server [port]         dedikovaný server bez lokálního hráče
##   --join adresa[:port]    připojení ke serveru
##   --name Jméno            jméno hráče
##   --character KÓD         vlastní postava (sdílecí kód LSC1… z editoru)
## Testy mohou místo argumentů nastavit `net_config` před přidáním do stromu.

const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const SimPuppet := preload("res://scripts/sim/sim_puppet.gd")
const WorldBuilder := preload("res://scripts/world/world_builder.gd")
const DayNight := preload("res://scripts/world/day_night.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const Protocol := preload("res://scripts/net/net_protocol.gd")
const Needs := preload("res://scripts/sim/needs.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const PsycheFX := preload("res://scripts/world/psyche_fx.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const CharacterCodec := preload("res://scripts/character/character_codec.gd")
const HouseholdDynamics := preload("res://scripts/sim/household_dynamics.gd")

## Startovní domácnost jako CharacterData (v2; jen pole odlišná od výchozích hodnot schématu;
## zbytek doplní validátor). Vzhled je explicitní – žádné odvozování ze jména ani z rodu.
## Skupina `mind` (predispozice) je SOUKROMÁ: nejde do spawn dat klientům, nastaví se jen na serveru.
const HOUSEHOLD := [
	{"uid": "a11ce0000000000a",
		"identity": {"first_name": "Jana", "last_name": "Nováková", "grammar": "f", "gender_identity": "zena",
			"attracted_to": ["muzi"]},
		"body": {"height_cm": 167.0, "age": 34, "frame": 0.42, "body_fat": 0.34, "muscle": 0.3, "shoulders": 0.42,
			"bust": 0.55, "waist": 0.45, "hips": 0.6},
		"face": {"head_width": -0.2, "cheekbones": 0.35, "cheeks_fullness": 0.25, "eye_size": 0.3, "eye_tilt": 0.2,
			"nose_length": -0.2, "nose_tip": 0.3, "nose_tip_angle": 0.4, "jaw_width": -0.3, "chin_length": -0.1,
			"lip_upper": 0.25, "lip_lower": 0.4, "mouth_width": 0.1, "brow_height": 0.2, "asym_eyes": 0.25, "asym_mouth": -0.2},
		"skin": {"tone": 0.2, "undertone": 0.15, "redness": 0.35, "freckles": 0.2},
		"hair": {"style": "dlouhe_vlnite", "melanin": 0.55, "red": 0.35},
		"eyes": {"iris": 0.45},
		"makeup": {"eyeliner": 0.3, "lipstick": 0.4},
		"clothing": {"bezne": {"top": "halenka", "bottom": "dziny", "shoes": "kozacky", "top_color": "#d94d59", "bottom_color": "#3a4250"}},
		"voice": {"pitch": 0.35, "tempo": 0.3},
		"personality": {"traits": ["spolecensky", "gurman", "zarlivy"], "aspirations": ["rodina"]},
		"story": {"family": "jeden_rodic", "childhood": "chaoticke", "past_work": ["gastro"], "hometown": "Most"},
		"mind": {"predispositions": {"depression": 0.5}, "morning_worse": true}},
	{"uid": "b0b0000000000b0b",
		"identity": {"first_name": "Petr", "last_name": "Dvořák", "grammar": "m", "gender_identity": "muz",
			"attracted_to": ["zeny"]},
		"body": {"height_cm": 181.0, "age": 41, "frame": 0.62, "body_fat": 0.42, "muscle": 0.32, "shoulders": 0.64,
			"bust": 0.06, "waist": 0.58, "hips": 0.45, "head_size": 0.2},
		"face": {"head_width": 0.3, "brow_ridge": 0.5, "forehead_slope": 0.35, "eyelid_hood": 0.45, "eye_depth": 0.4,
			"nose_length": 0.4, "nose_bridge": 0.6, "nose_width": 0.3, "jaw_width": 0.5, "jaw_angle": 0.35,
			"chin_width": 0.3, "chin_cleft": 0.4, "ear_size": 0.3, "ear_angle": 0.25, "neck_width": 0.4,
			"asym_jaw": 0.35, "asym_mouth": 0.3},
		"skin": {"tone": 0.5, "undertone": 0.35, "redness": 0.4, "weathering": 0.3},
		"hair": {"style": "kratke", "melanin": 0.9, "grey": 0.25, "hairline": 0.4, "facial": "strniste"},
		"eyes": {"iris": 0.85},
		"clothing": {"bezne": {"top": "mikina", "bottom": "teplaky", "shoes": "tenisky", "top_color": "#4073bf", "bottom_color": "#2b2f33"}},
		"voice": {"pitch": -0.5, "timbre": -0.3, "roughness": 0.45},
		"personality": {"traits": ["lenoch", "brucoun", "vznetlivy"], "aspirations": ["klid"]},
		"story": {"family": "oba_rodice", "childhood": "prisne", "past_work": ["sklad", "doprava"], "hometown": "Kladno"}},
	{"uid": "e115ca0000000e11",
		"identity": {"first_name": "Eliška", "last_name": "Malá", "grammar": "f", "gender_identity": "zena",
			"attracted_to": ["zeny", "muzi"]},
		"body": {"height_cm": 163.0, "age": 27, "frame": 0.38, "body_fat": 0.22, "muscle": 0.5, "shoulders": 0.45,
			"bust": 0.4, "waist": 0.38, "hips": 0.52, "leg_length": 0.58, "head_size": -0.15},
		"face": {"head_height": 0.2, "forehead_slope": -0.3, "eye_size": 0.45, "eye_distance": 0.2, "nose_width": 0.45,
			"nose_bridge": -0.3, "nose_tip": 0.25, "cheekbones": 0.55, "lip_upper": 0.55, "lip_lower": 0.6,
			"chin_length": 0.2, "jaw_width": -0.15, "philtrum": 0.3, "ear_size": -0.2, "asym_eyes": -0.3, "asym_jaw": -0.2},
		"skin": {"tone": 0.82, "undertone": 0.25, "redness": 0.25, "moles": 0.2},
		"hair": {"style": "copanky", "melanin": 0.97, "red": 0.05},
		"eyes": {"iris": 0.95},
		"aids": {"glasses": "kulate"},
		"clothing": {"bezne": {"top": "tricko", "bottom": "leginy", "shoes": "tenisky", "top_color": "#4da666", "bottom_color": "#23262b"}},
		"voice": {"pitch": 0.15, "tempo": 0.45},
		"personality": {"traits": ["aktivni", "knihomol", "uzkostlivy"], "aspirations": ["kariera", "nezavislost"]},
		"story": {"family": "oba_rodice", "childhood": "stehovani", "past_work": ["studium", "it"], "hometown": "Ostrava"},
		"mind": {"predispositions": {"anxiety": 0.6}}},
]
const HOUSEHOLD_POS := [Vector3(-1.0, 0, 1.0), Vector3(1.5, 0, 0.5), Vector3(0.0, 0, -1.5)]
## Kde se objeví postava, se kterou se hráč připojí (u vchodu).
const ARRIVAL_POS := Vector3(2.5, 0, 3.5)

## {"mode": "offline"|"host"|"server"|"client", "port": int, "address": String,
##  "name": String, "character": String (kód LSC1…), "clock": Node, "audio": bool, "hud": bool,
##  "camera": bool, "visuals": bool}
var net_config := {}

var clock
var net: Node
var sims_root: Node3D
var sims: Array = []
var smart_objects: Array = []
var selected := 0
var day_night: Node3D
var camera_rig: Node3D
var hud: CanvasLayer
var settings_menu: CanvasLayer
var psyche_fx: CanvasLayer
var _audio: Node = null
## Život domácnosti mimo rozhovory (třenice, společné chvíle, události) – jen na autoritě.
var dynamics = HouseholdDynamics.new()
var _test_mode := false
var _test_days := 3
## Zátěžové testy (jen headless --test): jiná domácnost z JSON souboru, posun seedů, denní výpis.
static var household_override: Array = []
var _seed_offset := 0
var _daily_stats := false


func _ready() -> void:
	var cfg := net_config if not net_config.is_empty() else _config_from_args()
	# Dedikovaný server spuštěný z příkazové řádky nic nevykresluje – 3D modely nenačítá.
	if net_config.is_empty() and String(cfg.get("mode", "")) == "server":
		AssetLibrary.enabled = false
	clock = cfg.get("clock", null)
	if clock == null:
		clock = get_node("/root/GameClock")
	# Vlasy z karet: první sestavení účesu běží ve vlákně (hra se nezasekne při vstupu postavy s novým účesem);
	# headless --test a testy zůstávají synchronní.
	if bool(cfg.get("visuals", true)) and not _test_mode and AssetLibrary.enabled:
		load("res://scripts/assets/hair_rig.gd").async_build = true

	if bool(cfg.get("visuals", true)):
		day_night = Node3D.new()
		day_night.set_script(DayNight)
		add_child(day_night)

	var builder = WorldBuilder.new(self)
	builder.build()
	smart_objects = builder.objects
	if day_night != null:
		for l in builder.lamps:
			day_night.add_interior_light(l)

	sims_root = Node3D.new()
	sims_root.name = "Sims"
	add_child(sims_root)

	net = Node.new()
	net.set_script(NetSession)
	net.name = "Net"
	add_child(net)
	net.setup(self, clock)
	net.welcomed.connect(_on_welcomed)
	clock.time_advanced.connect(_on_time_advanced)

	if bool(cfg.get("audio", true)):
		_audio = get_node_or_null("/root/AudioManager")
		if _audio != null:
			_audio.attach(self)

	var mode: String = cfg.get("mode", "offline")
	var port: int = int(cfg.get("port", Protocol.DEFAULT_PORT))
	var pname: String = String(cfg.get("name", ""))
	var code: String = String(cfg.get("character", ""))
	# Vlastní postava: lokálně se kód jen opraví (je hráčův), server ho u klienta ověří striktně.
	var my_char := {}
	if code != "" and mode != "client":
		var r := CharacterCodec.decode_code(code, {"mode": "repair"})
		if bool(r["ok"]):
			my_char = r["data"]
		else:
			push_error("Kód postavy nejde načíst: %s" % ", ".join(r["errors"]))
	match mode:
		"host", "server":
			var err: int = net.host(port, pname, mode == "server", my_char)
			if err != OK:
				push_error("Server se nepodařilo spustit na portu %d (chyba %d) – hraju offline." % [port, err])
				net.start_offline(pname)
			_spawn_household()
			net.assign_host_sim()
		"client":
			clock.running = true
			var err2: int = net.join(String(cfg.get("address", "127.0.0.1")), port, pname, code)
			if err2 != OK:
				push_error("Připojení selhalo (chyba %d) – hraju offline." % err2)
				net.start_offline(pname)
				_spawn_household()
		_:
			net.start_offline(pname)
			_spawn_household()
			if not my_char.is_empty():
				var own = spawn_character(my_char, ARRIVAL_POS, 4242,
					"Ja_" + SimAgent.node_name_for(String(my_char["identity"]["first_name"])))
				if own != null:
					selected = sims.find(own)

	if bool(cfg.get("camera", true)):
		camera_rig = Node3D.new()
		camera_rig.set_script(CameraRig)
		add_child(camera_rig)

	if bool(cfg.get("hud", true)):
		hud = CanvasLayer.new()
		hud.set_script(Hud)
		hud.main = self
		add_child(hud)
		psyche_fx = CanvasLayer.new()
		psyche_fx.set_script(PsycheFX)
		psyche_fx.main = self
		add_child(psyche_fx)
		settings_menu = CanvasLayer.new()
		settings_menu.set_script(SettingsMenu)
		add_child(settings_menu)
		# Obsahové varování při prvním spuštění (ne v headless režimu a testech).
		if not _test_mode and DisplayServer.get_name() != "headless":
			settings_menu.show_first_run_warning()

	if _test_mode:
		_run_headless_test.call_deferred(_test_days)
	elif net_config.is_empty():
		print("Life Simulator spuštěn (%s) – %d postavy, %d interaktivních objektů." % [
			net.mode_name(), sims.size(), smart_objects.size()])


func _config_from_args() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var cfg := {"mode": "offline"}
	_test_mode = args.has("--test")
	var i := args.find("--test")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		_test_days = int(args[i + 1])
	for flag in ["--host", "--server"]:
		var j := args.find(flag)
		if j >= 0:
			cfg["mode"] = flag.substr(2)
			if j + 1 < args.size() and args[j + 1].is_valid_int():
				cfg["port"] = int(args[j + 1])
	var k := args.find("--join")
	if k >= 0 and k + 1 < args.size():
		cfg["mode"] = "client"
		var addr: String = args[k + 1]
		var colon := addr.rfind(":")
		if colon > 0 and addr.substr(colon + 1).is_valid_int():
			cfg["port"] = int(addr.substr(colon + 1))
			addr = addr.substr(0, colon)
		cfg["address"] = addr
	var n := args.find("--name")
	if n >= 0 and n + 1 < args.size():
		cfg["name"] = args[n + 1]
	var ch := args.find("--character")
	if ch >= 0 and ch + 1 < args.size():
		cfg["character"] = args[ch + 1]
	if _test_mode:
		cfg["mode"] = "offline"
		var hh := args.find("--household")
		if hh >= 0 and hh + 1 < args.size():
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(args[hh + 1]))
			if typeof(parsed) == TYPE_ARRAY:
				household_override = parsed
			else:
				push_error("--household: soubor %s není JSON pole postav" % args[hh + 1])
		var sd := args.find("--seed")
		if sd >= 0 and sd + 1 < args.size() and args[sd + 1].is_valid_int():
			_seed_offset = int(args[sd + 1])
		_daily_stats = args.has("--daily")
	return cfg


## Kanonická (validovaná) data členů startovní domácnosti.
static func household_characters() -> Array:
	var out: Array = []
	for entry in (household_override if not household_override.is_empty() else HOUSEHOLD):
		var d := Schema.defaults()
		for g in entry:
			if typeof(entry[g]) == TYPE_DICTIONARY and d.has(g):
				if g == "clothing":
					for cat in entry[g]:
						d[g][cat] = (entry[g][cat] as Dictionary).duplicate()
				else:
					d[g].merge(entry[g], true)
			else:
				d[g] = entry[g]
		d["v"] = Schema.VERSION
		var r := Validator.validate(d)
		if not bool(r["ok"]):
			push_error("Neplatná postava domácnosti: %s" % str(r["errors"]))
		out.append(r["data"])
	return out


func _spawn_household() -> void:
	var chars := household_characters()
	for idx in chars.size():
		var pos: Vector3 = HOUSEHOLD_POS[idx % HOUSEHOLD_POS.size()]
		if idx >= HOUSEHOLD_POS.size():
			pos += Vector3(0.6 * float(idx / HOUSEHOLD_POS.size()), 0, 0.5)
		spawn_character(chars[idx], pos, 1000 + idx * 77 + _seed_offset * 7919)


## Server/offline: vytvoří postavu z KANONICKÝCH (validovaných) dat CharacterData.
## Do spawn dat (replikují se všem) jde jen veřejný snapshot; soukromé `mind` se nastaví
## až po spawnu a jen tady na autoritě. `node_name` = jedinečné jméno uzlu.
func spawn_character(cd: Dictionary, pos: Vector3, seed: int, node_name := "") -> Node:
	var c := CharacterData.new()
	c.set_from_dict(cd)
	var nm := c.display_name()
	var d := {"name": nm, "grammar": c.grammar(), "traits": c.traits(), "look": c.public_snapshot(),
		"pos": pos, "seed": seed, "node_name": node_name if node_name != "" else SimAgent.node_name_for(nm)}
	var node = net.spawn_sim(d)
	if node != null and node.has_method("apply_character_private"):
		node.apply_character_private(cd)
	return node


## Volá spawn_function MultiplayerSpawneru na všech peerech: autorita dostane simulovanou
## postavu, klient jen loutku. `d` může přijít ze sítě – typy se ověřují.
func spawn_sim_node(d: Dictionary) -> Node3D:
	var nm := String(d.get("name", "Postava")) if typeof(d.get("name")) == TYPE_STRING else "Postava"
	var node_name := String(d.get("node_name", "")) if typeof(d.get("node_name")) == TYPE_STRING else ""
	if node_name == "" or node_name.length() > 64:
		node_name = SimAgent.node_name_for(nm)
	# Rysy ze sítě: jen známé id, nejvýš MAX_TRAITS (klient je zobrazuje v HUD).
	var traits: Array = []
	if typeof(d.get("traits")) == TYPE_ARRAY:
		for t in d["traits"]:
			if typeof(t) == TYPE_STRING and Traits.DEFS.has(t) and not traits.has(t) and traits.size() < Schema.MAX_TRAITS:
				traits.append(t)
	var look = d.get("look", {})
	var col := Color.GRAY
	if multiplayer.is_server():
		var s := Node3D.new()
		s.set_script(SimAgent)
		s.setup(nm, String(d.get("grammar", "m")) if typeof(d.get("grammar")) == TYPE_STRING else "m", traits,
			col, int(d.get("seed", 1)) if typeof(d.get("seed")) == TYPE_INT else 1, self)
		s.name = node_name
		s.look = look if typeof(look) == TYPE_DICTIONARY else {}
		s.position = d.get("pos", Vector3.ZERO) if typeof(d.get("pos")) == TYPE_VECTOR3 else Vector3.ZERO
		return s
	var p := Node3D.new()
	p.set_script(SimPuppet)
	var safe := {
		"name": nm,
		"grammar": d.get("grammar", "m"),
		"color": col,
		"traits": traits,
		"look": look if typeof(look) == TYPE_DICTIONARY else {},
		"pos": d.get("pos", Vector3.ZERO) if typeof(d.get("pos")) == TYPE_VECTOR3 else Vector3.ZERO,
		"node_name": node_name.validate_node_name(),
	}
	p.setup_from_data(safe, self)
	return p


func register_sim(s: Node) -> void:
	if sims.has(s) or not (s is Node3D):
		return
	sims.append(s)
	if s.has_signal("memory_added"):
		s.memory_added.connect(_on_memory)
	if s.has_method("command"):
		dynamics.register(s)
	if _audio != null:
		_audio.register_sim(s)
	if String(s.name) == net.my_sim:
		selected = sims.size() - 1


func unregister_sim(s: Node) -> void:
	sims.erase(s)
	selected = clampi(selected, 0, maxi(sims.size() - 1, 0))


func find_sim(node_name: String) -> Node3D:
	if node_name == "":
		return null
	var n := sims_root.get_node_or_null(NodePath(node_name))
	if n != null and sims.has(n):
		return n
	return null


## Dynamika domácnosti běží jen tam, kde je autorita (offline / server); klient vidí výsledky.
func _on_time_advanced(dm: float) -> void:
	if dynamics == null:
		return
	# Klient, který se ještě připojuje (nebo už odpojil), nemá aktivní peer – is_server() by hlásil chybu.
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if peer == null or multiplayer.is_server():
		dynamics.advance(dm, sims, clock)


func get_smart_objects() -> Array:
	return smart_objects


func get_sims() -> Array:
	return sims


func get_selected_sim():
	if sims.is_empty():
		return null
	return sims[selected % sims.size()]


func _on_welcomed(my_sim: String) -> void:
	var s := find_sim(my_sim)
	if s != null:
		selected = sims.find(s)


func _on_memory(sim: Node3D, text: String) -> void:
	if not _test_mode and net_config.is_empty():
		print("[%s] %s: %s" % [clock.time_string(), sim.sim_name, text])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				net.request_speed(1 if clock.speed_index == 0 else 0)
			KEY_1:
				net.request_speed(1)
			KEY_2:
				net.request_speed(2)
			KEY_3:
				net.request_speed(3)
			KEY_4:
				net.request_speed(4)
			KEY_P:
				net.request_emergency_pause()
			KEY_TAB:
				if not sims.is_empty():
					selected = (selected + 1) % sims.size()
			KEY_F:
				var s = get_selected_sim()
				if s != null and camera_rig != null:
					camera_rig.focus_on(s.global_position)
			KEY_ENTER, KEY_KP_ENTER:
				if hud != null:
					hud.focus_chat()
			KEY_ESCAPE:
				if settings_menu != null:
					settings_menu.toggle()


# ---------------------------------------------------------------- headless test

func _run_headless_test(days: int) -> void:
	clock.running = false
	print("=== Life Simulator headless test: %d dní, %d postavy ===" % [days, sims.size()])
	var fccs_oracle = null
	if OS.get_cmdline_user_args().has("--fccs"):
		fccs_oracle = load("res://scripts/sim/fccs_oracle.gd").new()
		if fccs_oracle.init(sims):
			load("res://scripts/sim/sim_agent.gd").social_oracle = fccs_oracle
		else:
			fccs_oracle = null
	var min_avg := {}
	var min_need := {}
	var crit_minutes := {}
	for s in sims:
		min_avg[s.sim_name] = 100.0
		min_need[s.sim_name] = {}
		crit_minutes[s.sim_name] = 0
		for k in Needs.KEYS:
			min_need[s.sim_name][k] = 100.0
	var total := days * 1440
	var stress_hi := {}
	for s in sims:
		stress_hi[s.sim_name] = 0
	var start := Time.get_ticks_msec()
	for m in total:
		clock.advance(1.0)
		for s in sims:
			var n: String = s.sim_name
			if s.mental.stress > 85.0:
				stress_hi[n] += 1
			min_avg[n] = minf(min_avg[n], s.needs.average())
			for k in Needs.KEYS:
				min_need[n][k] = minf(min_need[n][k], s.needs.values[k])
				if s.needs.values[k] < 10.0:
					crit_minutes[n] += 1
		if _daily_stats and m % 1440 == 1439:
			for s2 in sims:
				var mm = s2.mental
				print("DAYSTAT|%d|%s|%.1f|%.1f|%.1f|%.3f|%.3f|%.3f|%d|%d|%s|%.1f|%d" % [m / 1440 + 1, s2.sim_name, s2.mood.value,
					mm.stress, mm.arousal, mm.dep.burden, mm.dep.hedonic, mm.dep.vigour, mm.panic_count, mm.dep.episode_count,
					mm.state_label(), s2.needs.average(), int(mm.coping_counts.get("drink", 0))])
		if m % 240 == 0:
			if day_night != null:
				day_night.update_cycle(clock.day_fraction())
			var line: PackedStringArray = []
			for s in sims:
				line.append("%s[%s|%s|%.0f]" % [s.sim_name.split(" ")[0], s.display_action(),
					Mood.emotion_label(s.mood.emotion), s.needs.average()])
			print("%s  %s" % [clock.time_string(), "  ".join(line)])
	var ms := Time.get_ticks_msec() - start
	print("--- Výsledky (%.0f ms, %.2f ms/herní hodinu) ---" % [ms, float(ms) / (days * 24.0)])
	var ds: Dictionary = dynamics.stats
	print("--- Domácnost ---")
	print("  rozhovory %d, hádky %d (%.0f %%), utnuto de-eskalací %d, stížnosti %d (z toho hádek %d)" % [
		ds["talks"], ds["argues"], 100.0 * dynamics.argue_rate(), ds["deescalated"], ds["complaint_talks"], ds["complaint_argues"]])
	print("  třenice %s | společné chvíle %s | události %s" % [JSON.stringify(ds["friction"]), JSON.stringify(ds["shared"]), JSON.stringify(ds["events"])])
	var mb := PackedStringArray()
	for k in ["good", "mid", "bad"]:
		var v: Array = ds["by_mood"][k]
		mb.append("%s %d (hádky %.0f %%)" % [k, v[0], 100.0 * v[1] / maxf(1.0, float(v[0]))])
	print("  hádky podle nálady: %s" % " | ".join(mb))
	if fccs_oracle != null:
		print(fccs_oracle.report())
		load("res://scripts/sim/sim_agent.gd").social_oracle = null
	var ok := true
	for s in sims:
		var n: String = s.sim_name
		var acts: PackedStringArray = []
		var total_actions := 0
		for id in s.action_counts:
			acts.append("%s×%d" % [id, s.action_counts[id]])
			total_actions += s.action_counts[id]
		var mins: PackedStringArray = []
		for k in Needs.KEYS:
			mins.append("%s %.0f" % [Needs.LABELS[k], min_need[n][k]])
		print("%s (%s)" % [n, Traits.labels(s.trait_ids)])
		print("  akce: %s" % ", ".join(acts))
		print("  min. potřeby: %s" % ", ".join(mins))
		print("  min. průměr: %.1f | minut v kritickém stavu: %d | nálada teď: %+.0f (%s)" % [
			min_avg[n], crit_minutes[n], s.mood.value, Mood.emotion_label(s.mood.emotion)])
		print("  vztahy: %s" % str(s.relationships))
		var mem_txt: PackedStringArray = []
		for e in s.memories.slice(-4):
			mem_txt.append(e["text"])
		print("  poslední vzpomínky: %s" % " | ".join(mem_txt))
		if total_actions < days * 10:
			print("  !! CHYBA: příliš málo akcí – postava se zasekla")
			ok = false
		if min_avg[n] < 20.0:
			print("  !! CHYBA: průměr potřeb klesl pod 20")
			ok = false
		if int(s.action_counts.get("sleep", 0)) + int(s.action_counts.get("sleep_sofa", 0)) + int(s.action_counts.get("sleep_floor", 0)) < days - 1:
			print("  !! CHYBA: postava téměř nespí")
			ok = false
		if int(s.action_counts.get("insult", 0)) > 0:
			print("  !! CHYBA: AI si sama vybrala akci jen pro hráče (urážka)")
			ok = false
		ok = _mental_report(s, days, stress_hi[n], days * 1440) and ok
	ok = _audio_report() and ok
	print("TEST %s" % ("OK" if ok else "SELHAL"))
	get_tree().quit(0 if ok else 1)


## Statistiky a sanity kontroly duševního stavu po headless simulaci.
func _mental_report(s, days: int, stress_hi_minutes: int, total_minutes: int) -> bool:
	var ok := true
	var m = s.mental
	var cop: PackedStringArray = []
	for id in m.coping_counts:
		cop.append("%s×%d" % [id, m.coping_counts[id]])
	print("  duševní stav: %s | stres %.0f | aktivace %.0f | citlivost %.2f | zvládnutelnost %.2f | ataky %d" % [
		m.state_label(), m.stress, m.arousal, m.sensitivity, m.mastery, m.panic_count])
	print("  copingy: %s | min. se stresem > 85: %d | myšlenek: %d" % [
		", ".join(cop) if not cop.is_empty() else "—", stress_hi_minutes, m.thoughts.size()])
	var dp = m.dep
	print("  deprese: zátěž %.2f | liking %.2f | vigour %.2f | pesimismus %.2f | epizod %d | váhání %d | omluv %d | křivdy %s | vina %s" % [
		dp.burden, dp.hedonic, dp.vigour, dp.pessimism, dp.episode_count, int(s.action_counts.get("hesitate", 0)),
		int(s.action_counts.get("apologize", 0)), _round_dict(s.ledger.grudges), _round_dict(s.ledger.guilt)])
	if dp.burden > 0.95:
		print("  !! CHYBA: depresivní zátěž v saturaci (systém se nevybíjí)")
		ok = false
	if int(s.action_counts.get("hesitate", 0)) > 0:
		print("  !! CHYBA: AI použila váhání (to je jen pro hráčovy příkazy)")
		ok = false
	if stress_hi_minutes > total_minutes * 0.25:
		print("  !! CHYBA: postava je přes čtvrtinu času v extrémním stresu (systém se nevybíjí)")
		ok = false
	if m.panic_count > days * 2:
		print("  !! CHYBA: příliš mnoho panických atak (%d za %d dní)" % [m.panic_count, days])
		ok = false
	if int(m.coping_counts.get("drink", 0)) > days * 2:
		print("  !! CHYBA: AI pije příliš často (%d×)" % int(m.coping_counts.get("drink", 0)))
		ok = false
	if m.conditions.is_empty() and m.panic_count > 0 and m.trait_vuln <= 0.0:
		print("  !! CHYBA: panická ataka u postavy bez predispozice")
		ok = false
	return ok


static func _round_dict(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in d:
		parts.append("%s %.0f" % [String(k).split(" ")[0], float(d[k])])
	return "{" + ", ".join(parts) + "}"


## Kontrola zvukového systému po headless simulaci.
func _audio_report() -> bool:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		print("!! CHYBA: AudioManager chybí")
		return false
	var ok := true
	var WavLoader = load("res://scripts/audio/wav_loader.gd")
	var missing: PackedStringArray = []
	var checked := 0
	for f in ["music/rano", "music/den", "music/vecer", "music/noc", "music/melancholie",
			"sfx/amb_dawn", "sfx/amb_birds", "sfx/amb_crickets", "sfx/amb_wind",
			"sfx/sfx_shower", "sfx/sfx_tv", "sfx/sfx_stove", "sfx/sfx_treadmill",
			"sfx/ui_click", "sfx/ui_chime", "sfx/ui_conflict",
			"sfx/amb_fridge", "sfx/amb_traffic", "sfx/amb_neighbors", "sfx/layer_tension", "sfx/hit_door_slam",
			"sfx/vox_argue_a", "sfx/vox_argue_b", "sfx/vox_argue_rough_a", "sfx/vox_argue_rough_b"]:
		checked += 1
		if WavLoader.load_wav("res://audio/%s.wav" % f, true) == null:
			missing.append(f)
	var plan: PackedStringArray = []
	var saved: float = clock.total_minutes
	for h in [2, 6, 9, 13, 19, 23]:
		clock.total_minutes = floor(saved / 1440.0) * 1440.0 + h * 60.0
		var w: Dictionary = audio.ambience_weights(float(h))
		var loud := ""
		var best := 0.0
		for k in w:
			if w[k] > best:
				best = w[k]
				loud = k
		plan.append("%02d h: %s + %s" % [h, audio.choose_track(), loud])
	clock.total_minutes = saved
	print("--- Zvuk ---")
	print("  soubory: %d chybí %s" % [checked - missing.size(), str(missing)])
	print("  hudba/ambience podle času: %s" % " | ".join(plan))
	print("  3D zvuky objektů: spuštěno %d, zastaveno %d, aktivních %d" % [
		audio.stats["object_starts"], audio.stats["object_stops"], audio.active_object_sounds()])
	if not missing.is_empty():
		print("  !! CHYBA: chybí zvukové soubory")
		ok = false
	if audio.stats["object_starts"] < 5:
		print("  !! CHYBA: objekty skoro nezněly")
		ok = false
	if audio.stats["object_starts"] - audio.stats["object_stops"] != audio.active_object_sounds():
		print("  !! CHYBA: nesouhlasí počet aktivních zvuků")
		ok = false
	return ok
