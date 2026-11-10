extends "res://tests/test_base.gd"
## QA 11/2026: ukončení hry s rozpracovanými stavbami účesů (HairRig.async_build) zablokovalo proces
## při ukončování enginu – úlohy WorkerThreadPool se nikdy nevyzvedly (Godot 4.7.2 uvázne, když při
## konci zbývá ve frontě víc nevyzvednutých úloh než vláken). Test: (1) evidence a vyzvednutí úloh,
## zrušení nespuštěných staveb a nová žádost po zrušení; (2) samostatný proces hry (herní cesta
## s asynchronními vlasy i šatníkem), který skončí hned po prvním snímku, se opravdu ukončí.
const Main := preload("res://main.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const Wardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
const STYLES := ["kratke", "mikado", "kudrnate", "dlouhe_vlnite", "copanky", "afro"]
const CHILD_LIMIT_S := 75.0


func _ready() -> void:
	watchdog_seconds = 170.0
	if OS.get_cmdline_user_args().has("--shutdown-child"):
		_child.call_deferred()
	else:
		_run.call_deferred()


## Dítě: skutečná scéna hry s asynchronními vlasy; skončí dřív, než se účesy dostaví.
func _child() -> void:
	var world := Main.new()
	world.net_config = {"mode": "offline", "hud": false, "camera": false, "audio": false,
		"visuals": true, "async_character_assets": true}
	add_child(world)
	await get_tree().process_frame
	print("CHILD hair_tasks=%d async=%s" % [HairRig.tasks_in_flight(), str(HairRig.async_build)])
	get_tree().quit(0)


func _run() -> void:
	section("HairRig: evidence úloh a jejich vyzvednutí")
	HairRig.clear_cache()
	HairRig.async_build = true
	check(not HairRig.context().is_empty(), "kontext vlasů je k dispozici (model postavy)")
	for s in STYLES:
		var r: Dictionary = HairRig.request_mesh("scalp", s, self)
		check(not bool(r["ready"]), "účes %s se staví ve vlákně" % s)
	check(HairRig.tasks_in_flight() == STYLES.size(), "každá stavba má evidovanou úlohu",
		str(HairRig.tasks_in_flight()))
	HairRig.wait_for_builds()
	check(HairRig.tasks_in_flight() == 0, "wait_for_builds vyzvedne všechny úlohy")
	# Dokončené stavby se uloží v dalším snímku; přeskočené (nespuštěné) už nejsou „rozpracované“.
	await get_tree().process_frame
	await get_tree().process_frame
	var built := 0
	var pending := 0
	for s in STYLES:
		if HairRig.is_pending("scalp", s):
			pending += 1
		elif bool(HairRig.request_mesh("scalp", s, null)["ready"]):
			built += 1
	check(pending == 0, "po vyzvednutí nezůstane žádný účes ve stavu „staví se“", "pending %d" % pending)
	print("    postaveno před zrušením: %d z %d" % [built, STYLES.size()])
	section("Zrušená stavba se dá vyžádat znovu")
	HairRig.wait_for_builds()  # žádosti z předchozí smyčky (zrušené účesy se znovu rozběhly)
	await get_tree().process_frame
	await get_tree().process_frame
	_ready_parts.clear()
	var rr: Dictionary = HairRig.request_mesh("scalp", "dredy", self)
	if not bool(rr["ready"]):
		var ok: bool = await wait_until(func(): return _ready_parts.has("scalp:dredy"), 60.0)
		check(ok, "vlastník dostane zprávu o dostavěném účesu")
	check(HairRig.mesh_for("scalp", "dredy") != null and not HairRig.is_pending("scalp", "dredy"),
		"účes je po dostavění v cache")
	check(HairRig.tasks_in_flight() == 0, "dokončená úloha se vyzvedne sama (_finish)")
	section("clear_cache zahodí výsledek rozpracované stavby")
	HairRig.clear_cache()
	HairRig.request_mesh("scalp", "kudrnate", self)
	HairRig.clear_cache()
	check(HairRig.tasks_in_flight() == 0 and not HairRig.is_pending("scalp", "kudrnate"),
		"clear_cache počká na úlohy a nenechá stav „staví se“")
	await get_tree().process_frame
	await get_tree().process_frame
	check(HairRig._meshes.is_empty(), "zastaralý výsledek se do nové cache neuloží")
	HairRig.async_build = false
	HairRig.clear_cache()

	section("Proces hry se ukončí i s rozpracovanými účesy")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/test_async_shutdown.tscn", "--", "--shutdown-child"])
	var t0 := Time.get_ticks_msec()
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "podřízený proces spuštěn")
	var exited: bool = await wait_until(func(): return not OS.is_process_running(pid), CHILD_LIMIT_S)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	check(exited, "podřízený proces skončil sám do %.0f s (%.1f s)" % [CHILD_LIMIT_S, secs])
	if not exited:
		OS.kill(pid)
	else:
		check(OS.get_process_exit_code(pid) == 0, "podřízený proces skončil s kódem 0",
			str(OS.get_process_exit_code(pid)))
	finish("test_async_shutdown")


var _ready_parts := {}
func _on_hair_mesh_ready(part: String, style: String) -> void:
	_ready_parts[part + ":" + style] = true
