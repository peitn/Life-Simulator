extends "res://tests/test_base.gd"
## Zvuky z konektoru Audio Engine (res://audio/engine/): soubory (formát, délka, špička,
## ticho, klipování), mapování činností, povrch a kadence kroků, noční hodiny, hudba
## editoru a šance na bouchnutí dveří podle stresu a temperamentu.

const EngineSfx := preload("res://scripts/audio/engine_sfx.gd")
const AM := preload("res://scripts/audio/audio_manager.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

class FakeMental extends RefCounted:
	var stress := 0.0

class FakeSim extends Node3D:
	signal action_started(sim: Node3D, action: Dictionary)
	signal action_finished(sim: Node3D, action_id: String, interrupted: bool)
	signal social_event(sim: Node3D, positive: bool, milestone: bool)
	var look := {}
	var target = null
	var mental = null
	var trait_ids: Array = []


func _init() -> void:
	watchdog_seconds = 90.0


func _ready() -> void:
	_test_files()
	_test_mapping()
	_test_steps_and_clock()
	_test_slam()
	await _test_runtime()
	finish("test_audio_engine_sfx")


func _wav_info(p: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(p)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	var ch := b.decode_u16(22)
	var rate := b.decode_u32(24)
	var bits := b.decode_u16(34)
	var n := (b.size() - 44) / 2
	var peak := 0
	var clip := 0
	var sq := 0.0
	for i in n:
		var v := absi(b.decode_s16(44 + i * 2))
		peak = maxi(peak, v)
		if v >= 32700:
			clip += 1
		sq += float(v) * float(v)
	return {"ch": ch, "rate": rate, "bits": bits, "sec": float(n) / float(maxi(rate, 1)),
			"peak": float(peak) / 32767.0, "clip": clip, "rms": sqrt(sq / float(maxi(n, 1))) / 32767.0}


func _test_files() -> void:
	section("Soubory Audio Engine (mono 22 050 Hz, 16 bit)")
	for id in EngineSfx.ALL_IDS:
		var p := EngineSfx.path(id)
		if not check(FileAccess.file_exists(p), "%s existuje" % id):
			continue
		check(FileAccess.file_exists(p + ".import"), "%s má .import (keep)" % id)
		var w := _wav_info(p)
		if not check(not w.is_empty(), "%s je platný WAV" % id):
			continue
		check(int(w["ch"]) == 1 and int(w["rate"]) == 22050 and int(w["bits"]) == 16, "%s: formát mono/22050/16" % id,
				"%d ch, %d Hz, %d bit" % [w["ch"], w["rate"], w["bits"]])
		check(float(w["peak"]) > 0.2 and float(w["peak"]) <= 0.8, "%s: špička 0,2–0,8 (není ticho ani přebuzené)" % id, "%.2f" % w["peak"])
		check(int(w["clip"]) == 0, "%s: bez klipování" % id)
		check(float(w["rms"]) > 0.005, "%s: není prázdný" % id, "%.4f" % w["rms"])
	var steps := _wav_info(EngineSfx.path("step_wood_1"))
	check(not steps.is_empty() and float(steps["sec"]) < 0.5, "krok je krátký (< 0,5 s)")
	var mus := _wav_info(EngineSfx.path("music_creator"))
	check(not mus.is_empty() and float(mus["sec"]) > 50.0 and float(mus["sec"]) < 90.0, "hudba editoru 50–90 s",
			"%.1f s" % (float(mus.get("sec", 0.0))))
	var clk := _wav_info(EngineSfx.path("amb_clock"))
	check(not clk.is_empty() and float(clk["sec"]) >= 2.0, "hodiny jsou smyčka ≥ 2 s")


func _test_mapping() -> void:
	section("Mapování činností na zvuky")
	var ids := {}
	for a in ActionLibrary.ACTIONS:
		ids[String(a["id"])] = true
	for k in EngineSfx.ACTION_LOOPS:
		check(ids.has(k), "smyčka pro existující činnost %s" % k)
		check(EngineSfx.ALL_IDS.has(EngineSfx.ACTION_LOOPS[k]), "%s → známý soubor" % k)
	for k in EngineSfx.ACTION_ONESHOTS:
		check(ids.has(k), "jednorázový zvuk pro existující činnost %s" % k)
		for f in EngineSfx.ACTION_ONESHOTS[k]:
			check(EngineSfx.ALL_IDS.has(f), "%s → %s je známý soubor" % [k, f])
	check(EngineSfx.sounds_for_action("read")["loop"] == "loop_pages", "čtení = listování")
	check((EngineSfx.sounds_for_action("drink")["oneshots"] as Array).has("sfx_bottle"), "pivo = otevření lahve")
	check(EngineSfx.sounds_for_action("nic_takoveho")["loop"] == "" and (EngineSfx.sounds_for_action("nic_takoveho")["oneshots"] as Array).is_empty(),
			"neznámá činnost nic nespustí")
	# Činnosti, které už mají zvuk objektu (sporák, sprcha…), se nezdvojují.
	for a in ActionLibrary.ACTIONS:
		if String(a.get("sound", "")) != "":
			check(not EngineSfx.ACTION_LOOPS.has(String(a["id"])), "%s nemá dvojí smyčku" % a["id"])


func _test_steps_and_clock() -> void:
	section("Kroky a noční hodiny")
	check(EngineSfx.surface_at(Vector3(0, 0, 0)) == "wood", "uprostřed domu je dřevo")
	check(EngineSfx.surface_at(Vector3(-5.4, 0, -3.9)) == "wood", "u lednice je dřevo")
	check(EngineSfx.surface_at(Vector3(0, 0, 9.0)) == "grass", "na zahradní cestě je tráva")
	check(EngineSfx.surface_at(Vector3(10, 0, 0)) == "grass", "za domem je tráva")
	check(EngineSfx.step_interval(0.1) == 0.0, "stání = žádné kroky")
	var slow := EngineSfx.step_interval(1.0)
	var fast := EngineSfx.step_interval(3.0)
	check(slow > fast, "rychlejší chůze = hustší kroky (%.2f > %.2f s)" % [slow, fast])
	check(fast >= EngineSfx.MIN_STEP_INTERVAL and EngineSfx.step_interval(100.0) == EngineSfx.MIN_STEP_INTERVAL, "kroky se nezhustí pod minimum")
	check(EngineSfx.step_interval(0.4) <= EngineSfx.MAX_STEP_INTERVAL, "pomalá chůze nemá nekonečné pauzy")
	check(EngineSfx.clock_weight(2.0) > 0.25, "ve 2 h v noci hodiny tikají")
	check(EngineSfx.clock_weight(13.0) < 0.01, "v poledne hodiny neslyšet")
	var ok := true
	for h in 48:
		var w := EngineSfx.clock_weight(float(h) * 0.5)
		ok = ok and w >= 0.0 and w <= 0.4
	check(ok, "váha hodin je v celém dni v 0..0,4")


func _test_slam() -> void:
	section("Bouchnutí dveří podle stresu a temperamentu")
	check(AM.slam_chance(null) == AM.SLAM_CHANCE, "bez postavy výchozí šance")
	var calm := FakeSim.new()
	calm.mental = FakeMental.new()
	calm.mental.stress = 10.0
	calm.trait_ids = ["samotar"]
	var hot := FakeSim.new()
	hot.mental = FakeMental.new()
	hot.mental.stress = 95.0
	hot.trait_ids = ["vznetlivy", "impulzivni"]
	var mid := FakeSim.new()
	mid.mental = FakeMental.new()
	mid.mental.stress = 60.0
	var c_calm := AM.slam_chance(calm)
	var c_hot := AM.slam_chance(hot)
	var c_mid := AM.slam_chance(mid)
	check(c_calm <= 0.1, "klidná samotářka skoro nebouchá (%.2f)" % c_calm)
	check(c_hot >= 0.6 and c_hot <= AM.SLAM_CHANCE_MAX, "vznětlivý ve stresu bouchá často (%.2f)" % c_hot)
	check(c_calm < c_mid and c_mid < c_hot, "šance roste se stresem a temperamentem")
	mid.trait_ids = ["vznetlivy"]
	check(AM.slam_chance(mid) > c_mid, "Vznětlivý zvyšuje šanci při stejném stresu")
	calm.free()
	hot.free()
	mid.free()


func _test_runtime() -> void:
	section("Za běhu (AudioManager → EngineSfx)")
	var am = get_node_or_null("/root/AudioManager")
	if not check(am != null and am.engine != null, "AudioManager má EngineSfx"):
		return
	var eng = am.engine
	var sim := FakeSim.new()
	add_child(sim)
	am.register_sim(sim)
	var l0: int = eng.stats["loops"]
	sim.action_started.emit(sim, {"id": "read"})
	check(eng.stats["loops"] == l0 + 1 and eng.active_loops() >= 1, "čtení spustí smyčku listování")
	sim.action_finished.emit(sim, "read", false)
	await get_tree().create_timer(0.6).timeout
	check(eng.active_loops() == 0, "po dočtení smyčka skončí")
	var o0: int = eng.stats["oneshots"]
	sim.action_started.emit(sim, {"id": "drink"})
	await get_tree().create_timer(0.8).timeout
	check(eng.stats["oneshots"] == o0 + 2, "pivo = lednice + lahev", str(eng.stats["oneshots"] - o0))
	check(not eng.editor_open(), "bez otevřeného editoru hraje běžná hudba")
	check(am.choose_track() != EngineSfx.CREATOR_TRACK, "výběr skladby bez editoru není „creator“")
	sim.queue_free()
	await get_tree().process_frame
	check(eng.active_loops() == 0, "po odchodu postavy nevisí smyčky")
