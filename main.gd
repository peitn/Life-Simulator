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
const WorldInteractionPicker := preload("res://scripts/ui/world_interaction_picker.gd")
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
const GossipNetwork := preload("res://scripts/sim/gossip_network.gd")
const Gossip_G := preload("res://scripts/core/grammar_cs.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const ClothingWardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
const SimVisualScript := preload("res://scripts/sim/sim_visual.gd")

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
const EIGHT_HOUSEHOLD_FILE := "res://data/households/extreme_young_adults8.json"
## Existing three-resident baseline is retained for headless regression fixtures.
## Visual desktop/web launches now use this fictional eight-resident scenario.
const HOUSEHOLD_POS := [Vector3(-1.0, 0, 1.0), Vector3(1.5, 0, 0.5), Vector3(0.0, 0, -1.5),
	Vector3(7.9, 0, -0.6), Vector3(11.1, 0, -0.6), Vector3(14.3, 0, -0.6),
	Vector3(17.2, 0, -0.6), Vector3(18.35, 0, -0.6)]
## Kde se objeví postava, se kterou se hráč připojí (u vchodu).
const ARRIVAL_POS := Vector3(2.5, 0, 3.5)

## {"mode": "offline"|"host"|"server"|"client", "port": int, "address": String,
##  "name": String, "character": String (kód LSC1…), "clock": Node, "audio": bool, "hud": bool,
##  "camera": bool, "visuals": bool}
var net_config := {}
## H4a: konfigurace „Znovu připojit“ přežije reload scény (jen v paměti procesu; token se nikdy
## neukládá na disk). Spotřebuje ji první _ready() bez net_config.
static var _resume_config := {}

var clock
var net: Node
var sims_root: Node3D
var sims: Array = []
var smart_objects: Array = []
## Full CharacterData stays on the authority; never add this store to replication.
var _character_records: Dictionary = {}
var _character_revisions: Dictionary = {}
var selected := 0
var day_night: Node3D
var camera_rig: Node3D
var hud: CanvasLayer
var settings_menu: CanvasLayer
var psyche_fx: CanvasLayer
var _audio: Node = null
## Život domácnosti mimo rozhovory (třenice, společné chvíle, události) – jen na autoritě.
var dynamics = HouseholdDynamics.new()
var gossip = GossipNetwork.new()
var _test_mode := false
var _eight_household_enabled := false
var _test_days := 3
## Zátěžové testy (jen headless --test): jiná domácnost z JSON souboru, posun seedů, denní výpis.
static var household_override: Array = []
var _seed_offset := 0
var _daily_stats := false
## Save slots live only on the local device. Multiplayer clients and hosts do NOT
## serialize server-owned private minds in this first offline save slice.
var _save_manager
var _save_enabled := false
var _save_elapsed := 0.0
var _save_day_due := false
var _save_loading := false
var _save_notice := ""
## H4b: serverové ukládání MP světa (jen autorita v síťovém režimu, soubor jen na serveru).
const ServerWorldStore := preload("res://scripts/save/server_world_store.gd")
const SERVER_AUTOSAVE_SECONDS := 120.0
var _server_store = null
var _server_autosave_seconds := SERVER_AUTOSAVE_SECONDS
var _server_save_elapsed := 0.0
var _server_day_due := false
## Výsledek obnovy při startu serveru ({} = nic se neobnovovalo) – HUD, log a testy.
var server_restore_result := {}

const AUTOSAVE_REAL_SECONDS := 300.0
const WORLD_CLICK_DRAG_PX := 10.0
var _world_mouse_down := false
var _world_mouse_down_at := Vector2.ZERO
var _world_dragged := false
var _last_touch_ms := -100000


func _ready() -> void:
	var cfg := net_config if not net_config.is_empty() else _config_from_args()
	if net_config.is_empty() and not _resume_config.is_empty():
		cfg = _resume_config
		_resume_config = {}
	# Desktop/web gameplay gets the 8-adult challenge, but isolated headless
	# tests retain their original 3-person baseline unless explicitly opted in.
	_eight_household_enabled = bool(cfg.get("eight_member_household",
		DisplayServer.get_name() != "headless" and not _test_mode))
	if not household_override.is_empty():
		_eight_household_enabled = false
	# Dedikovaný server spuštěný z příkazové řádky nic nevykresluje – 3D modely nenačítá.
	if net_config.is_empty() and String(cfg.get("mode", "")) == "server":
		AssetLibrary.enabled = false
	clock = cfg.get("clock", null)
	if clock == null:
		clock = get_node("/root/GameClock")
	# Vlasy z karet: první sestavení účesu běží ve vlákně (hra se nezasekne při vstupu postavy s novým účesem);
	# headless --test a testy zůstávají synchronní. `async_character_assets` (výchozí = visuals) umožní
	# testům zapnout přesně herní cestu i bez ostatních vizuálů.
	var async_assets: bool = AssetLibrary.enabled and bool(cfg.get("async_character_assets",
		bool(cfg.get("visuals", true)) and not _test_mode))
	if async_assets:
		load("res://scripts/assets/hair_rig.gd").async_build = true
		# Same for the authored C5 wardrobe (H3, 7 Nov 2026): decoding a garment kind took 1.5–7 s on the
		# main thread and could stall a joining client past the ENet timeout. Start all kinds now.
		ClothingWardrobe.async_load = true
		ClothingWardrobe.prewarm_async()

	if bool(cfg.get("visuals", true)):
		day_night = Node3D.new()
		day_night.set_script(DayNight)
		add_child(day_night)

	var builder = WorldBuilder.new(self)
	builder.include_eight_suite = _eight_household_enabled
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
	# Native ENet editor is available to the authenticated owner only. Server and
	# clients must agree on enabling staged RPCs; explicit test configs stay OFF
	# unless they opt in. Browser exports remain offline (no ENet transport).
	var edit_network: bool = mode != "offline" and ClassDB.class_exists("ENetMultiplayerPeer") \
		and bool(cfg.get("network_character_editor", net_config.is_empty()))
	net.character_edit_apply_rpc_enabled = edit_network
	net.character_edit_read_ui_enabled = edit_network and mode == "client"
	# H4a: ve hře postava odpojeného hráče čeká RECONNECT_GRACE_DEFAULT s na jeho návrat.
	# Injektované testovací konfigurace mají výchozí 0 (staré chování), pokud si lhůtu nezapnou.
	net.reconnect_grace_seconds = maxf(0.0, float(cfg.get("reconnect_grace",
		NetSession.RECONNECT_GRACE_DEFAULT if net_config.is_empty() else 0.0)))
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
			# H4b: skutečná hra ukládá serverový svět (výchozí zapnuto); injektované testy jen opt-in.
			var persist: bool = bool(cfg.get("server_persistence", net_config.is_empty()))
			var stored := {}
			if persist:
				_server_store = ServerWorldStore.new(String(cfg.get("server_save_directory",
					"user://server_world_extreme8" if _eight_household_enabled else "user://server_world")))
				_server_autosave_seconds = maxf(5.0, float(cfg.get("server_autosave_seconds", SERVER_AUTOSAVE_SECONDS)))
				stored = _server_store.load_data()
				if not bool(stored.get("ok", false)) and String(stored.get("reason", "missing")) != "missing":
					push_warning("Uložený svět serveru nejde načíst (%s) – začíná čerstvá domácnost." % String(stored.get("reason", "")))
			var err: int = net.host(port, pname, mode == "server", my_char, not persist)
			if err != OK:
				push_error("Server se nepodařilo spustit na portu %d (chyba %d) – hraju offline." % [port, err])
				net.start_offline(pname)
				_server_store = null
				_spawn_household()
			else:
				var host_sim := _restore_server_world(stored)
				if persist and mode == "host":
					net.register_local_host(pname, my_char, host_sim)
				if _server_store != null:
					clock.day_changed.connect(_mark_server_autosave_day)
			net.assign_host_sim()
		"client":
			clock.running = true
			if async_assets:
				_prewarm_character_visual()
			var err2: int = net.join(String(cfg.get("address", "127.0.0.1")), port, pname, code,
				String(cfg.get("reconnect_token", "")))
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

	# Restore after default spawn, before HUD and camera observe the household.
	# In injected tests autoload/autosave are explicitly opt-in; never load test
	# fixtures or overwrite the player's real user://saves.
	# Independent save namespace avoids overwriting older three-person homes.
	_save_manager = SaveGame.new(String(cfg.get("save_directory",
		"user://saves_extreme8" if _eight_household_enabled else "user://saves")))
	_save_enabled = not net.is_networked() and bool(cfg.get("autosave", net_config.is_empty() and not _test_mode and DisplayServer.get_name() != "headless"))
	if not net.is_networked() and bool(cfg.get("autoload", net_config.is_empty() and not _test_mode and DisplayServer.get_name() != "headless")):
		var pending: Dictionary = _save_manager.load_slot("autosave")
		if bool(pending.get("ok", false)):
			_save_loading = true
			var restored: Dictionary = SaveGame.apply(self, pending["data"])
			_save_loading = false
			if restored.get("ok", false):
				_save_notice = "Hra obnovena z " + ("záložní kopie." if pending["source"] == "backup" else "automatického uložení.")
			else:
				push_warning("Uloženou domácnost se nepodařilo obnovit: " + String(restored.get("reason", "unknown")))
		elif String(pending.get("reason", "missing")) != "missing":
			push_warning("Automatické uložení nelze načíst: " + String(pending.get("reason", "unknown")))
	if _save_enabled:
		clock.day_changed.connect(_mark_autosave_day)

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
		if _save_notice != "":
			hud.show_notice(_save_notice)
		# Obsahové varování při prvním spuštění (ne v headless režimu a testech).
		if not _test_mode and DisplayServer.get_name() != "headless":
			settings_menu.show_first_run_warning()

	if _test_mode:
		_run_headless_test.call_deferred(_test_days)
	elif net_config.is_empty():
		print("Life Simulator spuštěn (%s) – %d postavy, %d interaktivních objektů." % [
			net.mode_name(), sims.size(), smart_objects.size()])


## H4a: klientská konfigurace pro návrat ke stejné postavě ({} = návrat není možný).
func resume_config() -> Dictionary:
	if net == null or not net.can_resume():
		return {}
	var j: Dictionary = net.last_join
	return {"mode": "client", "address": String(j.get("address", "127.0.0.1")), "port": int(j.get("port", Protocol.DEFAULT_PORT)),
		"name": String(j.get("name", "")), "character": String(j.get("character", "")),
		"reconnect_token": net.my_reconnect_token}


## H4a: „Znovu připojit“ z HUD – znovu načte scénu a připojí se s jednorázovým tokenem.
## Jen pro skutečnou hru (bez net_config); testy si nový klientský svět staví samy.
func reconnect() -> bool:
	var cfg := resume_config()
	if cfg.is_empty() or not net_config.is_empty() or get_tree().current_scene != self:
		return false
	_resume_config = cfg
	net.shutdown()
	get_tree().reload_current_scene.call_deferred()
	return true


## Client only, BEFORE connecting: build one throw-away character visual so the character GLB,
## skeleton, hand/foot detail meshes and shaders are cached. Without it the first replicated
## character froze the client for 1–6 s right after the ENet handshake (measured in the H3
## three-process test), long enough for the server to drop the peer. Hair and C5 garments are not
## built here – they are asynchronous. Returns the main-thread time spent (ms).
var prewarm_visual_ms := -1.0
func _prewarm_character_visual() -> float:
	var t0 := Time.get_ticks_usec()
	var warm := Node3D.new()
	warm.set_script(SimVisualScript)
	warm.name = "PrewarmVisual"
	add_child(warm)  # _ready → _build, synchronous
	remove_child(warm)
	warm.queue_free()
	prewarm_visual_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return prewarm_visual_ms


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
	if _eight_household_enabled:
		var raw = JSON.parse_string(FileAccess.get_file_as_string(EIGHT_HOUSEHOLD_FILE))
		if raw is Array and raw.size() == 8:
			# Preserve the validation/public-private schema path of normal spawns.
			household_override = raw
			chars = household_characters()
			household_override = []
		else:
			push_error("Eight-person household fixture missing/invalid; kept old baseline")
	for idx in chars.size():
		var pos: Vector3 = HOUSEHOLD_POS[idx % HOUSEHOLD_POS.size()]
		if idx >= HOUSEHOLD_POS.size():
			pos += Vector3(0.6 * float(idx / HOUSEHOLD_POS.size()), 0, 0.5)
		var member = spawn_character(chars[idx], pos, 1000 + idx * 77 + _seed_offset * 7919)
		if _eight_household_enabled and member != null:
			# Fictional stress-test profiles differ in baseline load, vulnerability
			# and ability to draw on support. No irreversible/scripted crisis action.
			var stress_levels := [74.0, 92.0, 82.0, 77.0, 88.0, 36.0, 24.0, 85.0]
			var dep_levels := [0.56, 0.78, 0.86, 0.34, 0.43, 0.06, 0.02, 0.28]
			member.mental.stress = stress_levels[idx]
			member.mental.dep.burden = dep_levels[idx]
			member.mental.support = 0.76 if idx in [5, 6] else 0.10


## Commit a new offline character from a private creator draft. The authority
## chooses the UID and node name, validates the entire draft, and only then
## spawns the sim. Cancel/invalid requests cannot mutate the live household.
## No remotely callable entry point; multiplayer remains blocked.
func create_offline_character(candidate: Dictionary) -> Dictionary:
	if net == null or net.mode != net.Mode.OFFLINE or not net.is_authority():
		return {"ok": false, "reason": "offline_only"}
	if sims.size() >= SaveGame.MAX_SIMS:
		return {"ok": false, "reason": "household_full"}
	if typeof(candidate.get("v")) != TYPE_INT or int(candidate["v"]) != Schema.VERSION:
		return {"ok": false, "reason": "invalid_version"}
	var proposed: Dictionary = candidate.duplicate(true)
	proposed["uid"] = CharacterData.new_uid()
	for item in _character_records.values():
		if item.uid == proposed["uid"]:
			return {"ok": false, "reason": "uid_collision"}
	var gs := get_node_or_null("/root/GameSettings")
	var mh: String = gs.mental_health_mode() if gs != null else "full"
	var validated: Dictionary = Validator.validate(proposed, {"mode": "strict", "mental_health": mh})
	if not validated.get("ok", false):
		return {"ok": false, "reason": "invalid", "errors": validated.get("errors", [])}
	var new_uid: String = String(validated["data"]["uid"])
	var ident: Dictionary = validated["data"]["identity"]
	var display: String = ("%s %s" % [ident["first_name"], ident["last_name"]]).strip_edges()
	for member in sims:
		if is_instance_valid(member) and String(member.sim_name) == display:
			return {"ok": false, "reason": "duplicate_name"}
	var new_node := "Player_" + new_uid
	if find_sim(new_node) != null:
		return {"ok": false, "reason": "node_collision"}
	var agent = spawn_character(validated["data"], ARRIVAL_POS, int(Time.get_ticks_usec() % 2147483647) + 1, new_node)
	if agent == null:
		return {"ok": false, "reason": "spawn_failed"}
	selected = sims.find(agent)
	return {"ok": true, "node": String(agent.name), "uid": new_uid,
		"warnings": validated.get("warnings", [])}


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
		_character_records[String(node.name)] = c
		_character_revisions[String(node.name)] = 0
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
	_character_records.erase(String(s.name))
	_character_revisions.erase(String(s.name))
	sims.erase(s)
	selected = clampi(selected, 0, maxi(sims.size() - 1, 0))


func find_sim(node_name: String) -> Node3D:
	if node_name == "":
		return null
	var n := sims_root.get_node_or_null(NodePath(node_name))
	if n != null and sims.has(n):
		return n
	return null


## Automatic real-time interval + game-day rollover (the next frame after all
## listeners finish). Neither clock pause nor closing the HUD can disable saves.
func _mark_autosave_day(_day: int) -> void:
	_save_day_due = true


func _process(delta: float) -> void:
	if _server_store != null:
		_server_autosave_tick(delta)
		return
	if not _save_enabled or _save_loading or _save_manager == null or net == null or net.is_networked():
		return
	_save_elapsed += maxf(delta, 0.0)
	if _save_elapsed >= AUTOSAVE_REAL_SECONDS or _save_day_due:
		_save_elapsed = 0.0
		_save_day_due = false
		var result: Dictionary = save_game("autosave")
		if not bool(result.get("ok", false)):
			push_warning("Automatické ukládání selhalo: " + String(result.get("reason", "")))


## User-visible manual save, and verified auto-save. No RPC entry point.
func save_game(slot: String = "manual") -> Dictionary:
	if _save_manager == null or net == null or not is_instance_valid(net) or net.is_networked() or _save_loading:
		return {"ok": false, "reason": "offline_only"}
	var captured: Dictionary = SaveGame.capture(self)
	if not captured.get("ok", false):
		return captured
	return _save_manager.save_slot(slot, captured["data"])


## Restore only in local/offline authority; reads backup if primary is invalid.
func load_game(slot: String = "autosave") -> Dictionary:
	if _save_manager == null or net == null or not is_instance_valid(net) or net.is_networked() or _save_loading:
		return {"ok": false, "reason": "offline_only"}
	var read: Dictionary = _save_manager.load_slot(slot)
	if not read.get("ok", false):
		return read
	var preflight: Dictionary = SaveGame.validate_data(read["data"], self)
	if not preflight.get("ok", false):
		return preflight
	_save_loading = true
	var result: Dictionary = SaveGame.apply(self, read["data"])
	_save_loading = false
	if result.get("ok", false):
		_save_elapsed = 0.0
		_save_day_due = false
		result["source"] = read["source"]
		# A stale offline editor draft must never outlive a restored household.
		if hud != null and is_instance_valid(hud):
			if hud._character_editor != null and is_instance_valid(hud._character_editor):
				hud._character_editor._on_cancel()
				hud._character_editor = null
			hud._cmd_for = ""
			hud._cmd_refresh = 0.0
	return result


# ---------------------------------------------------------------- H4b: serverový svět

## Start serveru: obnoví uložený svět (když je platný), jinak spawne čerstvou domácnost.
## Vrací uzel hostitelovy uložené vlastní postavy ("" = žádná).
func _restore_server_world(stored: Dictionary) -> String:
	if not bool(stored.get("ok", false)):
		_spawn_household()
		return ""
	server_restore_result = ServerWorldStore.restore(self, stored["data"])
	if not bool(server_restore_result.get("ok", false)):
		push_warning("Uložený svět serveru nejde obnovit (%s) – začíná čerstvá domácnost." % String(server_restore_result.get("reason", "")))
		# Validace proběhla před spawnem; po selhání spawnu uprostřed obnovy svět vyčistit.
		for s in sims.duplicate():
			if is_instance_valid(s):
				if s.has_method("leave_world"):
					s.leave_world()
				unregister_sim(s)
				s.free()
		dynamics = HouseholdDynamics.new()
		gossip = GossipNetwork.new()
		_spawn_household()
		return ""
	server_restore_result["source"] = String(stored.get("source", "primary"))
	_save_notice = "Svět serveru obnoven%s: den %d, %d postav, %d čeká na návrat hráčů." % [
		" ze zálohy" if server_restore_result["source"] == "backup" else "",
		int(server_restore_result.get("day", 0)), int(server_restore_result["restored"]), int(server_restore_result["held"])]
	if net_config.is_empty():
		print(_save_notice)
	# Rychlost času dál řídí hlasy hráčů (dedikovaný server bez hráčů stojí).
	net._update_speed()
	return String(server_restore_result.get("host_sim", ""))


func _mark_server_autosave_day(_day: int) -> void:
	_server_day_due = true


func _server_autosave_tick(delta: float) -> void:
	if net == null or not is_instance_valid(net) or not net.is_networked() or not net.is_authority():
		return
	_server_save_elapsed += maxf(delta, 0.0)
	if _server_save_elapsed >= _server_autosave_seconds or _server_day_due:
		_server_save_elapsed = 0.0
		_server_day_due = false
		var r := server_save_now()
		if not bool(r.get("ok", false)):
			push_warning("Ukládání serverového světa selhalo: " + String(r.get("reason", "")))


## Server: okamžité uložení světa (autosave, zavření okna, testy). Není to RPC.
func server_save_now() -> Dictionary:
	if _server_store == null or net == null or not is_instance_valid(net) or not net.is_networked() or not net.is_authority():
		return {"ok": false, "reason": "server_only"}
	# Po shutdown() už relace hráčů neexistují – neukládat ochuzený stav přes dobrý snímek.
	if not net._connected:
		return {"ok": false, "reason": "server_closed"}
	var cap: Dictionary = ServerWorldStore.capture(self)
	if not bool(cap.get("ok", false)):
		return cap
	return _server_store.save(cap["data"])


## Background garment builds are joined before the world goes away (no unfinished
## WorkerThreadPool tasks at engine teardown). Their queued results are simply not used.
func _exit_tree() -> void:
	if _server_store != null:
		server_save_now()
	if ClothingWardrobe.async_load:
		ClothingWardrobe.wait_for_builds()


## A window-close request is earlier than child teardown. Frequent interval/day
## autosaves remain the primary protection against crashes or forced process exit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _save_enabled:
		save_game("autosave")
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _server_store != null:
		server_save_now()
	# Zavření okna je úmyslný odchod: server postavu nemá držet pro návrat (H4a).
	if what == NOTIFICATION_WM_CLOSE_REQUEST and net != null and is_instance_valid(net) and net.mode == net.Mode.CLIENT:
		net.request_leave()


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
		if gossip != null:
			gossip.tick(dm)
		var plates := get_node_or_null("DirtyDishes") as Node3D
		if plates != null:
			plates.visible = dynamics.has_dirty_dishes(float(clock.total_minutes))


func get_smart_objects() -> Array:
	return smart_objects


func get_sims() -> Array:
	return sims


# ---------------------------------------------------------------- drby a pomluvy (vztahy (c))
# Adaptér mezi SimAgenty a GossipNetwork. Běží jen na autoritě (offline / server): hooky volá
# simulace postav, která na klientovi neběží. Klientům jde jen to, co postava řekne nahlas.

## Obsahová nastavení pro drby: psychika jen v plném režimu, pití jen se zapnutými závislostmi.
func gossip_content() -> Dictionary:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return {"mental_health": true, "addiction": true}
	return {"mental_health": gs.allows_conditions() and gs.mental_health_mode() == gs.MH_FULL,
		"addiction": gs.allows_addiction()}


static func _gossip01(v: Variant) -> float:
	if typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)):
		return clampf((float(v) + 1.0) * 0.5, 0.0, 1.0)
	return 0.5


## Profil postavy pro GossipNetwork: poctivost a extraverze (HEXACO), stigmatizace, vztahy a zášť podle klíčů.
func gossip_profile(s: Node) -> Dictionary:
	var rel := {}
	var grudge := {}
	for o in sims:
		if o == s or not is_instance_valid(o) or not o.has_method("command"):
			continue
		var k: String = SimAgent.memory_key(o)
		if s.relationships.has(o.sim_name):
			rel[k] = float(s.relationships[o.sim_name])
		var g: float = s.ledger.grudge(o.sim_name) if s.ledger != null else 0.0
		if g > 0.0:
			grudge[k] = g
	var hx: Dictionary = s.get("hexaco") if typeof(s.get("hexaco")) == TYPE_DICTIONARY else {}
	return {"key": SimAgent.memory_key(s), "honesty": _gossip01(hx.get("honesty", 0.0)),
		"extraversion": _gossip01(hx.get("extraversion", 0.0)),
		"stigma": clampf(Traits.sum_param(s.trait_profile, "stigma"), 0.0, 1.0), "rel": rel, "grudge": grudge}


func _gossip_sim(key: String) -> Node:
	if key == "":
		return null
	for o in sims:
		if is_instance_valid(o) and o.has_method("command") and SimAgent.memory_key(o) == key:
			return o
	return null


func _gossip_name(s: Node) -> void:
	gossip.set_name(SimAgent.memory_key(s), String(s.sim_name), String(s.grammar))


## Svědectví (hádka, urážka, ataka, opakované pití, pomoc). Vrací id drbu (0 = nic).
func gossip_observe(witness: Node, subject: Node, kind: String, sev_mult := 1.0, whom: Node = null) -> int:
	if gossip == null or witness == null or subject == null or not _gossip_authority():
		return 0
	_gossip_name(subject)
	_gossip_name(witness)
	return gossip.observe(SimAgent.memory_key(witness), SimAgent.memory_key(subject), kind,
		float(clock.total_minutes), gossip_content(), sev_mult, SimAgent.memory_key(whom) if whom != null else "")


func _gossip_authority() -> bool:
	if net == null or not is_instance_valid(net):
		return true
	return net.is_authority()


## Povedený rozhovor dvou postav: osobní zkušenost oslabí drby o tom druhém, pak každá strana může
## říct jeden drb a přítel může tomu druhému prozradit, co se o něm říká. Vrací události (pro testy).
func gossip_exchange(a: Node, b: Node) -> Array:
	var events: Array = []
	if gossip == null or a == null or b == null or not _gossip_authority():
		return events
	var now := float(clock.total_minutes)
	var content := gossip_content()
	for s in [a, b]:
		_gossip_name(s)
	gossip.contact(SimAgent.memory_key(a), SimAgent.memory_key(b))
	for pair in [[a, b], [b, a]]:
		# Jen sloupec posluchače (vztahy ostatních k němu) – O(n), ne celá matice (review Gemini).
		var listener: Node = pair[1]
		var lkey: String = SimAgent.memory_key(listener)
		var facts := {"rel": {}}
		for o in sims:
			if o != listener and is_instance_valid(o) and o.has_method("command") and o.relationships.has(listener.sim_name):
				facts["rel"][SimAgent.memory_key(o)] = {lkey: float(o.relationships[listener.sim_name])}
		var ex: Array = gossip.expose(gossip_profile(pair[0]), gossip_profile(pair[1]), now, content)
		for ev in ex:
			_apply_gossip_event(ev, now)
		events.append_array(ex)
		var sh: Array = gossip.share(gossip_profile(pair[0]), gossip_profile(pair[1]), now, content, facts)
		for ev in sh:
			_apply_gossip_event(ev, now)
		events.append_array(sh)
	return events


static func _rel_add(s: Node, other: Node, d: float) -> void:
	if s == null or other == null or d == 0.0:
		return
	var cur: float = float(s.relationships.get(other.sim_name, 0.0))
	var nv := clampf(cur + d, -100.0, 100.0)
	s.relationships[other.sim_name] = nv
	s.note_relationship_change(other, cur, nv)
	s._detail_dirty = true


func _apply_gossip_event(ev: Dictionary, now: float) -> void:
	match String(ev.get("type", "")):
		"shared":
			var teller := _gossip_sim(String(ev["teller"]))
			var listener := _gossip_sim(String(ev["listener"]))
			var subject := _gossip_sim(String(ev["subject"]))
			if teller == null or listener == null:
				return
			var line: String = gossip.line_for(int(ev["rid"]))
			if line != "":
				teller.say(line)
				listener.remember("Drb od: %s – %s" % [teller.first_name(), line])
			_rel_add(listener, subject, float(ev["delta_rel"]))
			_rel_add(listener, teller, float(ev["bond"]))
			if String(ev["kind"]) == "badmouth" and subject != null:
				listener.remember_social(subject, "grievance", clampf(0.5 * float(ev["belief"]), 0.05, 1.0), "told", "intended")
			var hx: Dictionary = teller.get("hexaco") if typeof(teller.get("hexaco")) == TYPE_DICTIONARY else {}
			# Pocit „dobrého drbu“ jen u běžných témat – za drb o psychice nebo pití hra nic neodměňuje.
			if _gossip01(hx.get("honesty", 0.0)) < 0.45 and String(GossipNetwork.KINDS[String(ev["kind"])]["content"]) == "":
				teller.add_joy_moodlet("drbani", "Dobrý drb", "stastny", 4.0, 90.0)
		"exposed":
			var informer := _gossip_sim(String(ev["informer"]))
			var subject := _gossip_sim(String(ev["subject"]))
			var source := _gossip_sim(String(ev["source"]))
			if informer == null or subject == null:
				return
			var sg := String(subject.grammar)
			informer.say("Hele… lidi o tobě něco povídají. %s to vědět." % ("Měli byste" if sg == "pl" else "Měl%s bys" % Gossip_G.past(sg)))
			_rel_add(subject, informer, float(ev["delta_informer"]))
			var sev := float(ev["sev"])
			var cfg: Dictionary = subject.mental_cfg()
			subject.mental.on_stressor("gossip", 4.0 + 8.0 * sev, cfg)
			if bool(ev["truth"]):
				subject.mood.add_moodlet("drb_stud", "Ví se to o mně", "smutny", -8.0 - 6.0 * sev, 360.0)
			else:
				subject.mood.add_moodlet("drb_pomluva", "Pomlouvají mě", "nastvany", -10.0 - 8.0 * sev, 360.0)
			if source != null and source != subject:
				_rel_add(subject, source, float(ev["delta_source"]))
				subject.ledger.on_hurt_by(source.sim_name, 8.0 + 14.0 * sev, now)
				subject.remember_social(source, "humiliation", clampf(sev * (0.7 if bool(ev["truth"]) else 1.0), 0.05, 1.0), "told", "intended")
				subject.remember("%s o mně roznáší řeči" % source.sim_name)


## Soukromé věty pro vlastníka postavy: co se o sobě dozvěděl(a).
func gossip_private_lines(s: Node) -> PackedStringArray:
	if gossip == null or s == null:
		return PackedStringArray()
	return gossip.exposed_lines(SimAgent.memory_key(s))
	

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


func _input(event: InputEvent) -> void:
	# Clear a gesture even if its mouse-up lands over the HUD. Deferred so
	# an unhandled release still has the original press location available.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_clear_world_mouse_gesture.call_deferred()


func _clear_world_mouse_gesture() -> void:
	_world_mouse_down = false
	_world_dragged = false


func _unhandled_input(event: InputEvent) -> void:
	# HUD and modal buttons get first chance; world clicks happen on release.
	# A drag pans the camera and must NOT activate furniture on mouse-up.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_ms < 450:
			return
		if event.pressed:
			_world_mouse_down = true
			_world_mouse_down_at = event.position
			_world_dragged = false
		elif _world_mouse_down:
			if not _world_dragged and event.position.distance_to(_world_mouse_down_at) <= WORLD_CLICK_DRAG_PX:
				_pick_world_click(event.position)
			_clear_world_mouse_gesture()
		return
	if event is InputEventMouseMotion and _world_mouse_down:
		if event.position.distance_to(_world_mouse_down_at) > WORLD_CLICK_DRAG_PX:
			_world_dragged = true
	if event is InputEventScreenTouch and event.pressed:
		_last_touch_ms = Time.get_ticks_msec()
		_pick_world_click(event.position)
		return
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
			KEY_F5:
				var saved: Dictionary = save_game("manual")
				if hud != null:
					hud.show_notice("Hra uložena." if saved.get("ok", false) else "Uložení selhalo: " + String(saved.get("reason", "")))
			KEY_F9:
				var slot := "manual" if event.shift_pressed else "autosave"
				var loaded: Dictionary = load_game(slot)
				if hud != null:
					hud.show_notice("Hra načtena." if loaded.get("ok", false) else "Načtení selhalo: " + String(loaded.get("reason", "")))
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


## Mouse / touch world picking is a UI request, not a physics or authority shortcut.
func _pick_world_click(screen: Vector2) -> void:
	if camera_rig == null or hud == null or net == null:
		return
	if settings_menu != null and settings_menu.is_open():
		return
	var cam: Camera3D = camera_rig.get("camera") as Camera3D
	if cam == null:
		return
	var choice: Dictionary = WorldInteractionPicker.pick(cam, smart_objects, sims, screen)
	if choice.is_empty():
		return
	if String(choice.get("kind", "")) == "sim":
		var index: int = int(choice["index"])
		if index < 0 or index >= sims.size():
			return
		if net.mode == net.Mode.OFFLINE:
			selected = index
			hud.show_notice("Vybrána postava: " + String(sims[index].sim_name))
		elif String(sims[index].name) == String(net.my_sim):
			selected = index
		else:
			hud.show_notice("V multiplayeru můžeš ovládat jen svou postavu.")
	else:
		hud.open_world_object_actions(int(choice["index"]), Vector2i(screen))
	get_viewport().set_input_as_handled()


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


## Local controller entry points. No RPC is exposed until edit replication and
## authenticated ownership are implemented. A supplied peer ID is not authentication.
func read_character_edit(sim_node: String, peer_id: int = 1) -> Dictionary:
	if net == null or not net.is_authority() or peer_id != 1:
		return {"ok": false, "reason": "editing_unavailable"}
	# Listen-host may only edit their own authenticated player-created character.
	if net.is_networked() and (net.mode != net.Mode.HOST
			or not net.character_edit_apply_rpc_enabled
			or not net.server_can_edit_character(1, sim_node)):
		return {"ok": false, "reason": "editing_unavailable"}
	if find_sim(sim_node) == null or not _character_records.has(sim_node):
		return {"ok": false, "reason": "missing_character"}
	return {"ok": true, "data": _character_records[sim_node].to_dict(),
		"revision": _character_revisions[sim_node]}


## Only these sexuality preferences may change inside the locked identity
## group via the OFFLINE editor. Name/gender/grammar edits still need migration.
const OFFLINE_PRIVATE_SEXUAL_FIELDS := ["asexual", "aromantic",
	"sexual_attracted_to", "libido", "drive_dysregulation"]


func apply_character_edit(sim_node: String, candidate: Dictionary, expected_revision: int, peer_id: int = 1) -> Dictionary:
	var current := read_character_edit(sim_node, peer_id)
	if not current["ok"]:
		return current
	if expected_revision != current["revision"]:
		return {"ok": false, "reason": "conflict"}
	var before: Dictionary = current["data"]
	if candidate.get("uid") != before["uid"] or candidate.get("v") != before["v"]:
		return {"ok": false, "reason": "identity_changed"}
	# Name, gender and grammar edits need relationship/index migration. Only
	# specific *private* sexuality fields may be changed offline: never allow
	# replacing the identity group with arbitrary data or unknown keys.
	var identity: Variant = candidate.get("identity")
	if typeof(identity) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "identity_edit_pending"}
	var existing: Dictionary = before["identity"]
	for key in existing:
		if key not in OFFLINE_PRIVATE_SEXUAL_FIELDS and identity.get(key) != existing[key]:
			return {"ok": false, "reason": "identity_edit_pending"}
	for key in identity:
		if not existing.has(key) and key not in OFFLINE_PRIVATE_SEXUAL_FIELDS:
			return {"ok": false, "reason": "identity_edit_pending"}
	var gs := get_node_or_null("/root/GameSettings")
	var mh: String = gs.mental_health_mode() if gs != null else "full"
	var result := Validator.validate(candidate, {"mode": "strict", "mental_health": mh})
	if not result["ok"]:
		return {"ok": false, "reason": "invalid", "errors": result["errors"]}
	var committed: Dictionary = _commit_validated_character_edit(sim_node, result["data"], expected_revision, result["warnings"], true)
	if net.mode == net.Mode.HOST and committed.get("ok", false) and committed.get("changed", false):
		net._server_broadcast_character_public_look(sim_node, int(committed["revision"]))
	return committed


# Server-INTERNAL entry point. Future RPC MUST derive sender from multiplayer,
# never from the payload. No await or user callback between recheck and commit.
func server_apply_character_edit(sender_peer_id: int, sim_node: Variant, expected_revision: Variant, wire_payload: Variant) -> Dictionary:
	if net == null:
		return {"ok":false,"reason":"unauthorized"}
	var prepared: Dictionary = net.server_prepare_character_edit(sender_peer_id, sim_node, expected_revision, wire_payload)
	if not prepared.get("ok", false):
		return prepared
	if not net.server_can_edit_character(sender_peer_id, sim_node):
		return {"ok":false,"reason":"unauthorized"}
	return _commit_validated_character_edit(String(sim_node), prepared["data"], int(expected_revision), prepared["warnings"])


# Server-only public snapshot for staged appearance replication. No identity-private,
# personality, mind, or owner-only data can be returned by public_snapshot().
func read_public_character_look(sim_node: String) -> Dictionary:
	if net == null or not net.is_authority() or not _character_records.has(sim_node):
		return {"ok":false}
	if not _character_revisions.has(sim_node) or find_sim(sim_node) == null:
		return {"ok":false}
	return {"ok":true, "revision":int(_character_revisions[sim_node]),
		"look":_character_records[sim_node].public_snapshot()}


# Trusted internal sink for strictly validated data, shared with offline Apply.
# Not RPC. Re-read canonical revision immediately before any live mutation.
func _commit_validated_character_edit(sim_node: String, after: Dictionary, expected_revision: int, warnings: Array, allow_private_sexuality: bool = false) -> Dictionary:
	if not _character_records.has(sim_node) or not _character_revisions.has(sim_node) or find_sim(sim_node) == null:
		return {"ok":false,"reason":"missing_character"}
	if _character_revisions[sim_node] != expected_revision:
		return {"ok":false,"reason":"conflict"}
	var before: Dictionary = _character_records[sim_node].to_dict()
	# Even a server-internal caller must not bypass network identity locking.
	if before["identity"] != after["identity"] and (not allow_private_sexuality
			or net == null or net.is_networked()):
		return {"ok": false, "reason": "identity_edit_pending"}
	if after == before:
		return {"ok": true, "revision": expected_revision, "changed": false}
	var sim = find_sim(sim_node)
	var character: Resource = _character_records[sim_node]
	character.set_from_dict(after)
	var snapshot: Dictionary = character.public_snapshot()
	if snapshot != sim.look:
		sim.look = snapshot
		if is_instance_valid(sim.visual):
			sim.visual.apply_look(snapshot)
	# Update current, private sexuality without resetting learned emotional/mental
	# history. Existing live consent becomes invalid whenever age or preferences
	# are edited; no consent is silently inherited from a draft.
	if before["identity"] != after["identity"] or before["body"].get("age") != after["body"].get("age"):
		var ident: Dictionary = after["identity"]
		var body: Dictionary = after["body"]
		sim.intimacy.revoke_consent("")
		sim.intimacy.interest.clear()
		sim.intimacy.configure({"age": body["age"],
			"asexual": ident["asexual"], "aromantic": ident["aromantic"],
			"sexual_attraction": ident["sexual_attracted_to"],
			"romantic_attraction": ident["attracted_to"],
			"libido": ident["libido"],
			"drive_dysregulation": ident["drive_dysregulation"]})
		sim._detail_dirty = true
	# Wardrobe/body edits must not reset adaptive sensory state or mental history.
	if before["personality"] != after["personality"] or before["mind"] != after["mind"]:
		sim.apply_character_private(after, false)
		sim.mood.evaluate(sim.needs, sim.trait_profile, sim._extra_moodlets())
		sim._detail_dirty = true
		sim._update_net(0.0)
		sim._update_visual()
	_character_revisions[sim_node] += 1
	return {"ok": true, "revision": _character_revisions[sim_node], "changed": true,
		"warnings": warnings}