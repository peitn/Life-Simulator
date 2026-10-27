extends "res://tests/test_base.gd"
## Real offline transactional sexuality controls, strict identity and network lock.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const Save := preload("res://scripts/save/game_save.gd")

func _ready() -> void:
	watchdog_seconds = 40.0
	_run.call_deferred()


func _run() -> void:
	var gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	get_node("/root/GameClock").running = false
	Assets.enabled = false
	section("Private sexuality editor: offline own character and draft")
	var world = Main.new()
	world.net_config = {"mode": "offline", "hud": true, "camera": false,
		"visuals": false, "audio": false}
	add_child(world)
	await get_tree().process_frame
	var sim = world.get_selected_sim()
	var key := String(sim.name)
	var original: Dictionary = world.read_character_edit(key)["data"].duplicate(true)
	world.hud._edit_button.pressed.emit()
	var panel = world.hud._character_editor
	check(panel != null and panel.is_inside_tree(),
		"the existing character editor genuinely opens")
	var controls: Dictionary = panel.get("_sexuality_controls")
	check(controls.has("asexual") and controls.has("aromantic") and
		controls.has("libido") and controls.has("drive_dysregulation") and
		controls.has("target_zeny") and controls.has("target_muzi") and
		controls.has("target_nebinarni"),
		"visible controls separate attraction, libido and dysregulation")
	check(controls["libido"] is HSlider and controls["asexual"] is CheckBox,
		"correct interactive slider and checkbox types")
	check(panel._session.draft() == original,
		"opening sexual preferences never mutates the canonical character")
	var asx: CheckBox = controls["asexual"]
	asx.button_pressed = true
	check(bool(panel._session.draft()["identity"]["asexual"]),
		"asexuality checkbox creates a real transactional change")
	var slider: HSlider = controls["libido"]
	slider.value = 0.93
	var dys: HSlider = controls["drive_dysregulation"]
	dys.value = 0.06
	var target: CheckBox = controls["target_zeny"]
	target.button_pressed = true
	var draft = panel._session.draft()
	check(is_equal_approx(float(draft["identity"]["libido"]), 0.93) and
		is_equal_approx(float(draft["identity"]["drive_dysregulation"]), 0.06),
		"libido and disruptive preoccupation are independent numeric ranges")
	check(draft["identity"]["sexual_attracted_to"].has("zeny") and
		draft["identity"]["attracted_to"] == original["identity"]["attracted_to"],
		"sexual target preference is separate from romantic attraction")
	check(world.read_character_edit(key)["data"] == original,
		"draft cannot mutate authoritative CharacterData before Apply")
	check(not sim.look.has("libido") and not sim.look.has("sexual_attracted_to"),
		"private sexuality never enters public appearance data")
	check(panel._session.can_undo(), "sexuality changes participate in Undo")
	panel._on_undo()
	check(not panel._session.draft()["identity"]["sexual_attracted_to"].has("zeny"),
		"Undo removes the latest attraction checkbox selection")
	panel._on_redo()
	check(panel._session.draft()["identity"]["sexual_attracted_to"].has("zeny"),
		"Redo restores the independently selected attraction")
	section("Orientation preset slider")
	check(controls.has("orientation_spectrum") and controls["orientation_spectrum"] is HSlider,
		"three-position orientation slider exists alongside independent attraction")
	var saved_draft: Dictionary = panel._session.draft().duplicate(true)
	var sample: Dictionary = saved_draft.duplicate(true)
	sample["identity"]["gender_identity"] = "zena"
	panel._session.replace_draft(sample, "Test spectrum identity", "sex:orientation")
	panel._refresh()
	var spectrum: HSlider = controls["orientation_spectrum"]
	check(spectrum.editable, "woman character can use the spectrum")
	panel._on_orientation_spectrum(0.0)
	check(panel._session.draft()["identity"]["sexual_attracted_to"].has("muzi"),
		"heterosexual end selects men for woman")
	panel._on_orientation_spectrum(0.5)
	check(panel._session.draft()["identity"]["sexual_attracted_to"].has("muzi") and
		panel._session.draft()["identity"]["sexual_attracted_to"].has("zeny"),
		"middle position selects men and women")
	panel._on_orientation_spectrum(1.0)
	check(panel._session.draft()["identity"]["sexual_attracted_to"].has("zeny") and
		not panel._session.draft()["identity"]["sexual_attracted_to"].has("muzi"),
		"homosexual end selects women for woman")
	panel._session.replace_draft(saved_draft, "Restore original draft", "sex:orientation")
	panel._refresh()
	check(panel._session.draft() == saved_draft, "spectrum test leaves no draft mutations")
	section("Apply updates current physiology, not gender or mental history")
	sim.mental.stress = 34.0
	var prev_stress: float = sim.mental.stress
	panel._on_apply()
	var read = world.read_character_edit(key)
	check(bool(read["ok"]) and int(read["revision"]) == 1 and
		bool(read["data"]["identity"]["asexual"]),
		"offline Apply atomically commits private sexual fields")
	check(is_equal_approx(sim.intimacy.libido_baseline, 0.93)
		and sim.intimacy.asexual and sim.intimacy.sexual_attraction.has("zeny"),
		"live NPC intimacy model refreshes immediately without respawn")
	check(sim.mental.stress == prev_stress and
		read["data"]["identity"]["gender_identity"] ==
			original["identity"]["gender_identity"],
		"updating private sexuality leaves psychological burden and gender unchanged")
	check(not panel._session.is_dirty() and not gs.get_value("adult_intimacy"),
		"successful Apply resets draft; actual adult gameplay is still opt-in")
	var saved = Save.capture(world)
	check(bool(saved.get("ok", false)) and
		Save.validate_data(saved["data"], world).get("ok", false),
		"new preferences are accepted in authoritative H4 household save")
	section("Locked identity and network editing boundaries")
	var current: Dictionary = read["data"]
	var spoof = current.duplicate(true)
	spoof["identity"]["first_name"] = "ForbiddenName"
	check(world.apply_character_edit(key, spoof, 1).get("reason") == "identity_edit_pending",
		"renaming remains forbidden; offline exception is sexuality-only")
	spoof = current.duplicate(true)
	spoof["identity"]["gender_identity"] = "jine"
	check(world.apply_character_edit(key, spoof, 1).get("reason") == "identity_edit_pending",
		"gender identity remains independent and cannot be silently modified")
	spoof = current.duplicate(true)
	spoof["identity"]["libido"] = 0.3
	world.net.mode = world.net.Mode.DEDICATED
	check(world.apply_character_edit(key, spoof, 1).get("reason") == "editing_unavailable",
		"offline-only editing cannot be used after switching to network mode")
	check(world._commit_validated_character_edit(key, spoof, 1, []).get("reason") ==
		"identity_edit_pending",
		"network/internal commit refuses private identity mutation without offline gate")
	world.net.mode = world.net.Mode.OFFLINE
	check(world.read_character_edit(key)["data"] == current,
		"denied private edits do not change live authority")
	slider.value = 0.19
	check(panel._session.is_dirty(), "new libido draft stays staged after prior Apply")
	panel._on_cancel()
	await get_tree().process_frame
	check(world.read_character_edit(key)["data"] == current,
		"Cancel discards uncommitted sexuality preferences")
	world.queue_free()
	await get_tree().process_frame
	gs.reset()
	Assets.enabled = true
	finish("test_adult_sexuality_editor")
