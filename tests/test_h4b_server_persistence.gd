extends "res://tests/test_base.gd"
## H4b – serverové ukládání multiplayerového světa (skutečné ENet, server a klienti v jednom
## procesu jako test_mp_reconnect). Ověřuje:
##  * injektované testy bez opt-in nic neukládají (výchozí stav ostatních testů se nemění),
##  * snímek serveru: atomický soubor + .bak, v souboru jen SHA-256 hashe tokenů (nikdy token),
##  * „pád“ serveru → nový server ze stejného adresáře obnoví domácnost, vlastní postavy hráčů,
##    vztahy, paměť, potřeby, čas a SOUKROMÝ záznam postavy (mind) – vše jen na serveru,
##  * hráči se po restartu vrátí ke svým postavám STEJNÝM tokenem (A vlastní, B domácnost),
##    bez nového spawnu, s vlastnictvím a právem editace; token se rotuje,
##  * cizí/použitý/podvržený token (i samotný hash) nic nepřevezme,
##  * autosave podle intervalu, vypršení držení po restartu, lhůta 0 = vlastní postavy se
##    neobnoví, poškozený primární soubor → .bak, oba poškozené → čerstvá domácnost,
##  * zfalšovaná serverová sekce (hash, jméno s bidi znakem, cizí uzel, own/host nesoulad,
##    neznámý klíč) se odmítne fail-closed; obnova do živého/neprázdného světa se odmítne,
##  * hostitel (listen server) dostane po restartu zpět svou vlastní postavu.
## Tokeny se nikdy nevypisují.

const Main := preload("res://main.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const Store := preload("res://scripts/save/server_world_store.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")

var port := 0
var dir := ""
var host_dir := ""
var _holders := {}
var notices := {}


func _ready() -> void:
	watchdog_seconds = 170.0
	randomize()
	port = 26200 + randi() % 600
	var tag := "%d_%d" % [OS.get_process_id(), randi() % 100000]
	dir = "user://test-h4b-%s" % tag
	host_dir = "user://test-h4b-host-%s" % tag
	_run.call_deferred()


func _branch(bname: String, cfg: Dictionary) -> Node3D:
	var holder := Node.new()
	holder.name = bname
	add_child(holder)
	_holders[bname] = holder
	get_tree().set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	if cfg.get("mode", "") == "client":
		var c := Node.new()
		c.set_script(GameClockScript)
		c.name = "Clock"
		holder.add_child(c)
		cfg["clock"] = c
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "World"
	w.net_config = cfg
	holder.add_child(w)
	notices[bname] = []
	w.net.notice.connect(func(t: String): notices[bname].append(t))
	return w


func _server(bname: String, p: int, grace: float, extra := {}) -> Node3D:
	var cfg := {"mode": "server", "port": p, "clock": get_node("/root/GameClock"), "audio": false,
		"hud": false, "camera": false, "visuals": false, "reconnect_grace": grace,
		"server_persistence": true, "server_save_directory": dir, "server_autosave_seconds": 3600.0}
	cfg.merge(extra, true)
	return _branch(bname, cfg)


func _client(bname: String, p: int, player_name: String, code := "", token := "") -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": p, "name": player_name,
		"character": code, "reconnect_token": token, "audio": false, "hud": false, "camera": false, "visuals": false})


## Simulovaný pád/odpojení: relace se zavře bez úmyslného odchodu, uzel zmizí.
func _drop(bname: String) -> void:
	var w: Node3D = _holders[bname].get_node("World")
	w.net.shutdown()
	_holders[bname].queue_free()
	_holders.erase(bname)


func _char(seed: int, extra := {}) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var d := Randomizer.generate(r)
	for g in extra:
		d[g].merge(extra[g], true)
	return Validator.validate(d)["data"]


func _peer_of(w: Node3D) -> int:
	return w.multiplayer.get_unique_id()


func _notice_has(bname: String, needle: String) -> bool:
	for t in notices[bname]:
		if String(t).find(needle) >= 0:
			return true
	return false


func _file_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


## Hledá UTF-8 bajty řetězce v binárním souboru (var_to_bytes obsahuje nuly – žádné ASCII čtení).
func _contains(hay: PackedByteArray, needle: String) -> bool:
	var h := hay.hex_encode()
	var n := needle.to_utf8_buffer().hex_encode()
	var at := h.find(n)
	while at >= 0:
		if at % 2 == 0:
			return true
		at = h.find(n, at + 1)
	return false


## Úmyslný odchod klienta (bez držení postavy) a odstranění jeho světa.
func _leave(bname: String, server: Node3D) -> void:
	var w: Node3D = _holders[bname].get_node("World")
	var pid := _peer_of(w)
	w.net.request_leave()
	await wait_until(func(): return not server.net.players.has(pid), 4.0)
	_drop(bname)


func _rm_dir(path: String) -> void:
	var full := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(full):
		return
	for f in DirAccess.get_files_at(full):
		DirAccess.remove_absolute(full.path_join(f))
	DirAccess.remove_absolute(full)


func _has_marker(sim: Node, marker: String) -> bool:
	for m in sim.memories:
		if String(m.get("text", "")).begins_with(marker):
			return true
	return false


func _run() -> void:
	var clock := get_node("/root/GameClock")
	var store := Store.new(dir)

	section("Výchozí: injektovaný server bez opt-in nic neukládá")
	var srv0 := _branch("Server0", {"mode": "server", "port": port + 9, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false, "reconnect_grace": 5.0})
	check(srv0._server_store == null, "server bez server_persistence nemá úložiště")
	check(String(srv0.server_save_now().get("reason", "")) == "server_only", "server_save_now bez úložiště nic nezapíše")
	check(srv0.server_restore_result.is_empty() and srv0.get_sims().size() == 3, "čerstvá domácnost jako dřív")
	check(not FileAccess.file_exists(store.path()), "žádný soubor serverového světa nevznikl")
	_drop("Server0")
	await wait_seconds(0.2)

	section("Server 1: hráči a stav světa")
	var srv := _server("Server1", port, 30.0)
	check(srv._server_store != null and srv.server_restore_result.is_empty(), "perzistence zapnutá, žádný uložený svět → čerstvá domácnost")
	check(srv.get_sims().size() == 3, "domácnost 3 postavy")
	var mine := _char(5501, {"identity": {"first_name": "Radka", "last_name": "Horká"},
		"mind": {"predispositions": {"anxiety": 0.45}}})
	var code := Codec.encode_code(mine)
	var a := _client("ClientA", port, "Alfa", code)
	var b := _client("ClientB", port, "Beta")
	check(await wait_until(func(): return a.net.my_sim != "" and b.net.my_sim != "", 8.0), "A (vlastní postava) a B (domácnost) přivítáni")
	check(await wait_until(func(): return a.net.my_reconnect_token != "" and b.net.my_reconnect_token != "", 3.0), "oba mají reconnect token")
	var tok_a: String = a.net.my_reconnect_token
	var tok_b: String = b.net.my_reconnect_token
	var a_sim: String = a.net.my_sim
	var b_sim: String = b.net.my_sim
	var s_a = srv.find_sim(a_sim)
	var s_b = srv.find_sim(b_sim)
	check(s_a != null and bool(s_a.get_meta("player_character", false)), "A má vlastní postavu na serveru")
	check(s_b != null and not bool(s_b.get_meta("player_character", false)), "B ovládá postavu domácnosti")
	s_a.relationships["H4b Svědek"] = 37.0
	s_a.memories.append({"t": clock.total_minutes, "text": "H4B_MARKER vzpomínka před restartem"})
	s_b.needs.values["hunger"] = 23.5
	s_b.relationships["H4b Soused"] = -12.0
	var private_a: Dictionary = srv._character_records[a_sim].to_dict()
	check(private_a["mind"]["predispositions"].get("anxiety", 0.0) == 0.45, "soukromý záznam A má predispozici (jen server)")
	check(a._character_records.is_empty() and b._character_records.is_empty(), "klienti soukromé záznamy postav nemají")

	section("Uložení serverového světa")
	var saved: Dictionary = srv.server_save_now()
	check(bool(saved.get("ok", false)), "server_save_now uložil svět", str(saved.get("reason", "")))
	check(FileAccess.file_exists(store.path()), "soubor serverového světa existuje")
	var raw := _file_bytes(store.path())
	check(raw.size() > 1000 and not _contains(raw, tok_a) and not _contains(raw, tok_b), "v souboru NENÍ žádný token v čisté podobě")
	check(_contains(raw, tok_a.sha256_text()) and _contains(raw, tok_b.sha256_text()), "v souboru jsou jen SHA-256 hashe tokenů")
	check(bool(srv.server_save_now().get("ok", false)) and FileAccess.file_exists(store.path() + ".bak"), "druhé uložení archivuje předchozí snímek do .bak")
	var loaded: Dictionary = store.load_data()
	check(bool(loaded.get("ok", false)) and loaded["source"] == "primary", "snímek jde načíst a projde validací")
	var sec: Dictionary = loaded["data"]["server"]
	check(sec["own"] == [a_sim] and sec["held"].size() == 2 and sec["host_sim"] == "", "serverová sekce: 1 vlastní postava, 2 připojení hráči jako držení")
	var saved_minutes: float = float(loaded["data"]["clock"]["total_minutes"])
	var saved_rev: int = int(srv._character_revisions[a_sim])

	section("Pád serveru (bez úmyslného odchodu hráčů)")
	_drop("Server1")
	check(await wait_until(func(): return not a.net._connected and not b.net._connected, 5.0), "klienti zjistili ztrátu spojení")
	check(a.net.can_resume() and b.net.can_resume(), "klienti si token ponechali (HUD nabídne návrat)")
	check(a.net.my_reconnect_token == tok_a, "token A beze změny")
	_drop("ClientA")
	_drop("ClientB")
	# Čerstvě spuštěný proces by měl hodiny od nuly – obnova je musí vrátit.
	clock.total_minutes = 0.0
	await wait_seconds(0.3)

	section("Restart serveru ze stejného adresáře")
	var port2 := port + 2
	var srv2 := _server("Server2", port2, 30.0)
	var rr: Dictionary = srv2.server_restore_result
	check(bool(rr.get("ok", false)), "obnova uloženého světa proběhla", str(rr.get("reason", "")))
	check(int(rr.get("restored", 0)) == 4 and int(rr.get("held", 0)) == 2 and int(rr.get("dropped", -1)) == 0, "4 postavy, 2 čekají na návrat hráčů", JSON.stringify(rr))
	check(String(rr.get("source", "")) == "primary", "zdroj = primární soubor")
	var r_a = srv2.find_sim(a_sim)
	var r_b = srv2.find_sim(b_sim)
	check(r_a != null and bool(r_a.get_meta("player_character", false)) and String(r_a.get_meta("character_uid", "")) == String(private_a["uid"]), "vlastní postava A obnovena se značkou hráče a UID")
	check(srv2.net.is_held(a_sim) and srv2.net.is_held(b_sim) and srv2.net.held_count() == 2, "A i B jsou držené pro návrat")
	check(r_a != null and bool(r_a.get_meta("reconnect_hold", false)), "obnovená postava nese reconnect_hold")
	var now2: float = NetSession._now()
	check(srv2.net._held.values().all(func(e): return float(e["expires"]) - now2 <= 30.05 and float(e["expires"]) - now2 >= 25.0), "připojení hráči při uložení mají po restartu celou lhůtu (30 s)")
	check(r_a != null and float(r_a.relationships.get("H4b Svědek", 0.0)) == 37.0 and _has_marker(r_a, "H4B_MARKER"), "vztahy a paměť A obnoveny")
	check(r_b != null and absf(float(r_b.needs.values["hunger"]) - 23.5) < 0.001 and float(r_b.relationships.get("H4b Soused", 0.0)) == -12.0, "potřeby a vztahy B obnoveny")
	check(absf(float(clock.total_minutes) - saved_minutes) < 0.001, "herní čas obnoven", "%f vs %f" % [clock.total_minutes, saved_minutes])
	check(srv2._character_records[a_sim].to_dict() == private_a, "soukromý záznam postavy (mind) obnoven beze změny")
	check(int(srv2._character_revisions[a_sim]) == saved_rev, "revize postavy obnovena")
	check(clock.speed_index == 0, "dedikovaný server bez hráčů po obnově stojí (rychlost řídí hlasy)")

	section("Podvržený token po restartu nic nepřevezme")
	var forger := _client("ClientForge", port2, "Padělatel", "", tok_a.sha256_text())
	check(await wait_until(func(): return srv2.net.players.has(_peer_of(forger)), 6.0), "klient s hashem místo tokenu je obsloužen jako nový hráč")
	check(forger.net.my_sim != a_sim and forger.net.my_sim != b_sim, "samotný hash z disku postavu nepřevezme", forger.net.my_sim)
	check(srv2.net.is_held(a_sim) and srv2.net.is_held(b_sim), "držení A i B dál trvá")
	check(await wait_until(func(): return _notice_has("ClientForge", "relace už neplatí"), 3.0), "server řekl, že relace neplatí")
	await _leave("ClientForge", srv2)
	check(srv2.net.players.is_empty() and srv2.net.held_count() == 2, "padělatel odešel, jeho postava se nedrží")

	section("Návrat hráčů stejným tokenem po restartu")
	var a2 := _client("ClientA2", port2, "Jiné Jméno", code, tok_a)
	var b2 := _client("ClientB2", port2, "Beta", "", tok_b)
	check(await wait_until(func(): return a2.net.my_sim != "" and b2.net.my_sim != "", 8.0), "A i B se znovu připojili")
	check(a2.net.my_sim == a_sim, "A je zpátky u své vlastní postavy", "%s vs %s" % [a2.net.my_sim, a_sim])
	check(b2.net.my_sim == b_sim, "B je zpátky u své postavy domácnosti", "%s vs %s" % [b2.net.my_sim, b_sim])
	check(a2.net.my_name == "Alfa", "jméno hráče z uložené relace", a2.net.my_name)
	check(srv2.net.stats["resumed"] == 2 and srv2.net.stats["characters_spawned"] == 0, "žádný nový spawn – postavy převzaty")
	var id_a2 := _peer_of(a2)
	check(bool(srv2.net.players[id_a2].get("own", false)) and srv2.net.server_can_edit_character(id_a2, a_sim), "vlastnictví a právo editace obnoveno")
	check(not srv2.net.is_held(a_sim) and not srv2.net.is_held(b_sim) and srv2.net.held_count() == 0, "nikdo už není držený")
	check(await wait_until(func(): return a2.net.my_reconnect_token != "" and a2.net.my_reconnect_token != tok_a, 3.0), "A dostal nový token (rotace)")
	check(await wait_until(func(): return a2.find_sim(a_sim) != null and a2.find_sim(a_sim).has_private, 5.0), "vlastník vidí svou postavu i se soukromým stavem")
	check(a2._character_records.is_empty(), "klient ani po návratu soukromý záznam nemá")
	check(await wait_until(func(): return b2.find_sim(a_sim) != null, 4.0) and not b2.find_sim(a_sim).has_private and b2._character_records.is_empty(), "jiný hráč po obnově soukromý stav postavy A nedostal")

	section("Použitý token neprojde ani po restartu")
	var thief := _client("ClientThief", port2, "Zloděj", "", tok_b)
	check(await wait_until(func(): return srv2.net.players.has(_peer_of(thief)), 6.0), "klient se starým tokenem B je nový hráč")
	check(thief.net.my_sim != b_sim and thief.net.my_sim != a_sim, "starý token nic nepřevzal", thief.net.my_sim)
	check(srv2.net.players[_peer_of(b2)]["sim"] == b_sim, "B o postavu nepřišel")
	await _leave("ClientThief", srv2)
	check(srv2.net.players.size() == 2 and srv2.net.held_count() == 0, "zloděj odešel, nic se nedrží")

	section("Autosave podle intervalu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path()))
	srv2._server_autosave_seconds = 0.4
	check(await wait_until(func(): return FileAccess.file_exists(store.path()), 4.0), "server sám uložil svět po uplynutí intervalu")
	srv2._server_autosave_seconds = 3600.0
	var auto: Dictionary = store.load_data()
	check(bool(auto.get("ok", false)) and auto["data"]["server"]["held"].size() == 2, "autosave nese obě relace (A2, B2) jako budoucí držení")
	var tok_a2: String = a2.net.my_reconnect_token
	check(_contains(_file_bytes(store.path()), tok_a2.sha256_text()) and not _contains(_file_bytes(store.path()), tok_a2), "i rotovaný token je v souboru jen jako hash")

	section("Restart, kdy se nikdo nevrátí → držení vyprší")
	_drop("Server2")
	_drop("ClientA2")
	_drop("ClientB2")
	await wait_seconds(0.3)
	var port3 := port + 4
	var srv3 := _server("Server3", port3, 1.5)
	check(bool(srv3.server_restore_result.get("ok", false)) and srv3.net.held_count() == 2, "obnoveno se 2 drženími (lhůta 1,5 s)")
	var watcher := _client("ClientW", port3, "Pozorovatel")
	check(await wait_until(func(): return watcher.net.my_sim != "", 6.0), "pozorovatel připojen")
	check(watcher.net.my_sim != a_sim and watcher.net.my_sim != b_sim, "pozorovatel nedostal drženou postavu")
	check(await wait_until(func(): return srv3.net.held_count() == 0, 5.0), "držení po lhůtě vypršela")
	check(await wait_until(func(): return srv3.find_sim(a_sim) == null, 3.0), "vlastní postava A po lhůtě ze světa odešla")
	check(srv3.find_sim(b_sim) != null, "postava domácnosti zůstala (je zase volná)")
	check(await wait_until(func(): return watcher.find_sim(a_sim) == null, 3.0), "odchod se replikoval klientovi")
	_drop("ClientW")
	_drop("Server3")
	await wait_seconds(0.3)

	section("Lhůta 0 → vlastní postavy bez možnosti návratu se neobnoví")
	var srv4 := _server("Server4", port + 6, 0.0)
	var r4: Dictionary = srv4.server_restore_result
	check(bool(r4.get("ok", false)) and int(r4["restored"]) == 3 and int(r4["dropped"]) == 1 and int(r4["held"]) == 0, "obnovena domácnost, vlastní postava A vynechána", JSON.stringify(r4))
	check(srv4.find_sim(a_sim) == null and srv4.net.held_count() == 0, "A ve světě není, nic se nedrží")
	check(srv4.find_sim(b_sim) != null and not srv4.net.is_held(b_sim), "postava domácnosti B obnovena a volná")
	_drop("Server4")
	await wait_seconds(0.2)

	section("Zfalšovaná serverová sekce se odmítne")
	var good: Dictionary = store.load_data()["data"]
	check(Store.validate_server_section(good)["ok"], "platný snímek projde")
	var cases := [
		["hash velkými písmeny", func(d): d["server"]["held"][0]["hash"] = String(d["server"]["held"][0]["hash"]).to_upper(), "bad_held_hash"],
		["krátký hash", func(d): d["server"]["held"][0]["hash"] = "abc", "bad_held_hash"],
		["duplicitní hash", func(d): d["server"]["held"][1]["hash"] = d["server"]["held"][0]["hash"], "bad_held_hash"],
		["jméno s bidi znakem", func(d): d["server"]["held"][0]["name"] = "Al" + String.chr(0x202E) + "fa", "bad_held_name"],
		["neexistující uzel", func(d): d["server"]["held"][0]["sim"] = "Nikdo", "bad_held_sim"],
		["dvě držení jedné postavy", func(d): d["server"]["held"][1]["sim"] = d["server"]["held"][0]["sim"], "bad_held_sim"],
		["own nesouhlasí", func(d): d["server"]["held"][0]["own"] = not bool(d["server"]["held"][0]["own"]), "bad_held_own"],
		["neznámý klíč v držení", func(d): d["server"]["held"][0]["admin"] = true, "bad_held"],
		["neznámý klíč sekce", func(d): d["server"]["peers"] = [], "unknown_server_key"],
		["host_sim není vlastní postava", func(d): d["server"]["host_sim"] = b_sim, "bad_host_sim"],
		["jiná verze sekce", func(d): d["server"]["v"] = 99, "unsupported_server_version"],
		["chybějící sekce", func(d): d.erase("server"), "missing_server_section"],
		["own na neexistující uzel", func(d): d["server"]["own"] = ["Nikdo"], "bad_own"],
		["záporný zbytek lhůty", func(d): d["server"]["held"][0]["remaining"] = -1.0, "bad_held_remaining"],
		["nulový zbytek lhůty", func(d): d["server"]["held"][0]["remaining"] = 0.0, "bad_held_remaining"],
		["NaN zbytek lhůty", func(d): d["server"]["held"][0]["remaining"] = NAN, "bad_held_remaining"],
		["nekonečný zbytek lhůty", func(d): d["server"]["held"][0]["remaining"] = INF, "bad_held_remaining"],
		["zbytek lhůty jako text", func(d): d["server"]["held"][0]["remaining"] = "30", "bad_held_remaining"],
		["chybějící zbytek lhůty", func(d): d["server"]["held"][0].erase("remaining"), "bad_held"],
	]
	for c in cases:
		var d: Dictionary = good.duplicate(true)
		c[1].call(d)
		var v: Dictionary = Store.validate_server_section(d)
		check(not v["ok"] and String(v["reason"]) == c[2], "odmítnuto: " + c[0], String(v.get("reason", "")))

	section("Poškozený primární soubor → záloha .bak")
	# Zfalšovaný primár s platným GameSave obalem (SHA sedí), ale špatnou serverovou sekcí:
	var forged: Dictionary = good.duplicate(true)
	forged["server"]["held"][0]["hash"] = "ZZ"
	check(bool(SaveGame.new(dir).save_slot("autosave", forged).get("ok", false)), "zfalšovaný snímek zapsán obejitím serverové validace (útok na disk)")
	var fb: Dictionary = store.load_data()
	check(bool(fb.get("ok", false)) and fb["source"] == "backup", "server použil platnou zálohu .bak", String(fb.get("reason", "")))
	# Useknutý primár (přerušený zápis) i náhodné bajty → vždy záloha:
	var whole := _file_bytes(store.path() + ".bak")
	var cut := FileAccess.open(store.path(), FileAccess.WRITE)
	cut.store_buffer(whole.slice(0, whole.size() / 2))
	cut.close()
	var tr: Dictionary = store.load_data()
	check(bool(tr.get("ok", false)) and tr["source"] == "backup", "useknutý primární soubor → platná záloha .bak", String(tr.get("reason", "")))
	# Rozbitý primár (náhodné bajty):
	var f := FileAccess.open(store.path(), FileAccess.WRITE)
	f.store_buffer(Crypto.new().generate_random_bytes(4096))
	f.close()
	var srv5 := _server("Server5", port + 8, 30.0)
	check(bool(srv5.server_restore_result.get("ok", false)) and srv5.server_restore_result["source"] == "backup", "server po rozbitém primáru obnovil svět ze zálohy")
	_drop("Server5")
	await wait_seconds(0.2)
	for suffix in ["", ".bak"]:
		var g := FileAccess.open(store.path() + suffix, FileAccess.WRITE)
		g.store_buffer(Crypto.new().generate_random_bytes(2048))
		g.close()
	var srv6 := _server("Server6", port + 10, 30.0)
	check(srv6.server_restore_result.is_empty() and srv6.get_sims().size() == 3 and srv6.net.held_count() == 0, "oba soubory rozbité → čerstvá domácnost, žádný pád")
	check(srv6.find_sim(a_sim) == null, "z rozbitého souboru se nic nespawnulo")

	section("Zbytek lhůty se při restartu neprodlužuje")
	var free_sim := ""
	for s in srv6.get_sims():
		if not srv6.net.is_held(String(s.name)):
			free_sim = String(s.name)
			break
	var h_short := "1".repeat(64)
	var h_long := "2".repeat(64)
	var other_sim := ""
	for s in srv6.get_sims():
		if String(s.name) != free_sim:
			other_sim = String(s.name)
			break
	var n_restored: int = srv6.net.restore_held([
		{"hash": h_short, "sim": free_sim, "name": "Krátká", "own": false, "remaining": 2.0},
		{"hash": h_long, "sim": other_sim, "name": "Dlouhá", "own": false, "remaining": 999.0}])
	var now6: float = NetSession._now()
	check(n_restored == 2, "obě držení obnovena")
	check(float(srv6.net._held[h_short]["expires"]) - now6 <= 2.05, "už běžící lhůta pokračuje jen zbytkem (2 s), restart ji neprodlouží")
	check(float(srv6.net._held[h_long]["expires"]) - now6 <= 30.05, "uložený zbytek nad lhůtou serveru se ořízne na reconnect_grace (30 s)")
	check(srv6.net.restore_held([{"hash": "3".repeat(64), "sim": free_sim, "name": "Druhé", "own": false, "remaining": 5.0}]) == 0, "jedna postava nemůže být držená dvakrát")
	for hk in [h_short, h_long]:
		var sn := String(srv6.net._held[hk]["sim"])
		srv6.net._held.erase(hk)
		srv6.find_sim(sn).remove_meta("reconnect_hold")

	section("Obnova jen do prázdného světa před hráči")
	var live := Store.restore(srv6, good)
	check(not live["ok"] and String(live["reason"]) == "server_world_not_empty", "obnova do běžícího světa odmítnuta")
	check(SaveGame.apply(srv6, good).get("reason", "") == "offline_only", "GameSave.apply bez allow_authority na serveru dál odmítá")
	check(SaveGame.capture(srv6).get("reason", "") == "offline_only", "GameSave.capture bez allow_authority na serveru dál odmítá")
	var cl := _client("ClientL", port + 10, "Late")
	check(await wait_until(func(): return cl.net.my_sim != "", 6.0), "klient připojen k serveru 6")
	check(String(Store.restore(cl, good).get("reason", "")) == "server_only", "klient obnovu spustit nemůže")
	check(String(Store.capture(cl).get("reason", "")) == "server_only", "klient snímek pořídit nemůže")
	srv6.net.pending[999] = 0.0
	var tmp_sims: Array = srv6.sims.duplicate()
	srv6.sims.clear()
	check(String(Store.restore(srv6, good).get("reason", "")) == "players_connected", "obnova při připojených hráčích odmítnuta")
	srv6.sims = tmp_sims
	srv6.net.pending.erase(999)
	_drop("ClientL")
	_drop("Server6")
	await wait_seconds(0.2)

	section("Hostitel dostane po restartu svou postavu zpět")
	var host_cfg := {"mode": "host", "port": port + 12, "clock": clock, "audio": false, "hud": false,
		"camera": false, "visuals": false, "reconnect_grace": 30.0, "name": "Hostitel",
		"character": Codec.encode_code(_char(5502, {"identity": {"first_name": "Bohdana", "last_name": "Veselá"}})),
		"server_persistence": true, "server_save_directory": host_dir, "server_autosave_seconds": 3600.0}
	var h1 := _branch("Host1", host_cfg.duplicate())
	var host_sim: String = h1.net.my_sim
	check(host_sim != "" and bool(h1.find_sim(host_sim).get_meta("player_character", false)) and h1.get_sims().size() == 4, "hostitel hraje svou vlastní postavu", host_sim)
	h1.find_sim(host_sim).memories.append({"t": 0.0, "text": "H4B_HOST hostitelova vzpomínka"})
	check(bool(h1.server_save_now().get("ok", false)), "hostitel uložil svět")
	_drop("Host1")
	await wait_seconds(0.3)
	var h2 := _branch("Host2", host_cfg.duplicate())
	check(bool(h2.server_restore_result.get("ok", false)) and String(h2.server_restore_result.get("host_sim", "")) == host_sim, "obnova zná hostitelovu postavu")
	check(h2.net.my_sim == host_sim and h2.net.stats["characters_spawned"] == 0 and h2.get_sims().size() == 4, "hostitel ovládá stejnou postavu, nic nového se nespawnulo")
	check(_has_marker(h2.find_sim(host_sim), "H4B_HOST") and bool(h2.net.players[1].get("own", false)), "hostitelova postava má svou paměť a vlastnictví")
	_drop("Host2")

	for bn in _holders.keys():
		_holders[bn].get_node("World").net.shutdown()
	_rm_dir(dir)
	_rm_dir(host_dir)
	finish("test_h4b_server_persistence")
