extends "res://tests/test_base.gd"
## UI/household/door smoke tests for playable 8-adult demo. Not a GPU screenshot.
const Main := preload("res://main.gd")

func _ready() -> void:
	watchdog_seconds = 100.0
	_run.call_deferred()


func _run() -> void:
	var clock := get_node("/root/GameClock")
	clock.running = false
	var settings := get_node("/root/GameSettings")
	settings.persist = false
	var initial_sound := bool(settings.get_value("audio_enabled"))
	settings.set_value("audio_enabled", true, false)
	settings.set_value("warning_ack", true, false)
	var w := Main.new()
	w.net_config = {"mode": "offline", "eight_member_household": true, "visuals": true,
		"audio": true, "hud": true, "camera": true, "autoload": false, "autosave": false}
	add_child(w)
	await get_tree().process_frame
	section("Eight fictional residents aged 18 to 27 with separate psychological profiles")
	check(w.sims.size() == 8, "eight independent real SimAgents spawned", str(w.sims.size()))
	var ages: Array = []
	var private_variation := {}
	var stress_values: Array = []
	for sim in w.sims:
		var rec = w._character_records.get(String(sim.name))
		if rec == null:
			continue
		ages.append(int(rec.body["age"]))
		var mind: Dictionary = rec.mind
		var predispositions: Dictionary = mind.get("predispositions", {})
		private_variation[JSON.stringify(predispositions)] = true
		stress_values.append(sim.mental.stress)
		check(not sim.get("look").has("mind"), "private mental conditions never in public look: %s" % sim.name)
	ages.sort()
	check(ages == [18, 19, 20, 21, 23, 24, 26, 27], "all eight ages within requested 18–27 window", str(ages))
	check(private_variation.size() >= 4, "distinct extreme mental predisposition profiles remain private")
	check(stress_values.max() >= 85.0 and stress_values.min() <= 25.0, "wide starting stress levels, not homogeneous NPCs")
	section("Actual sleeping capacity and separate bedrooms")
	var beds := 0
	var bed_units := 0
	for obj in w.smart_objects:
		if obj.object_tag == "bed":
			beds += int(obj.capacity)
			bed_units += 1
	check(beds == 8, "eight real independent reservable sleeping slots", str(beds))
	check(bed_units == 7, "existing double and single bed plus five annex beds", str(bed_units))
	for n in 4:
		check(w.get_node_or_null("BedroomLabel_%d" % (n + 1)) is Label3D,
			"bedroom %d built with a room marker" % (n + 1))
	section("Articulated doors, solid leaf collision and proximity motor")
	var doors := ["FrontDoor", "BathroomDoor", "BedroomDoor_1", "BedroomDoor_2",
		"BedroomDoor_3", "BedroomDoor_4"]
	for label in doors:
		var d=w.get_node_or_null(label)
		var collider=d.get_node_or_null("HingedDoor/Hinge/LeafBody/LeafCollider") if d != null else null
		check(d != null and collider is CollisionShape3D and collider.shape is BoxShape3D and not collider.disabled,
			"door %s has a physically collidable leaf and active hinge" % label)
	var front = w.get_node_or_null("FrontDoor")
	# Move every other resident away so we can verify both opening and closing.
	for sim in w.sims:
		sim.global_position = Vector3(1.0, 0, -1.0)
	w.sims[0].global_position = front.door_node().to_global(Vector3(1.0, 0.0, 0.8))
	for i in 68:
		await get_tree().physics_frame
	check(front.is_open() and front.door_node().hinge.rotation.y >= 1.5,
		"front door actually rotates open 90 degrees when character approaches")
	w.sims[0].global_position = Vector3(1,0,-1)
	for i in 75:
		await get_tree().physics_frame
	check(not front.is_open() and absf(front.door_node().hinge.rotation.y) < 0.03,
		"door closes behind actors after they leave")
	section("HUD and settings controls: connected actions and audio toggle")
	check(w.hud != null and w.settings_menu != null, "HUD and SettingsMenu instantiated")
	var sound=w.hud._audio_toggle
	check(sound != null and sound.name == "SoundToggle", "visible dedicated sound switch exists")
	check(sound.pressed.get_connections().size() > 0, "sound switch has working callback")
	check(w.settings_menu._audio_enabled != null and w.settings_menu._audio_enabled.toggled.get_connections().size() > 0,
		"settings also offers connected audio switch")
	check(not AudioServer.is_bus_mute(0), "master audio is initially enabled")
	sound.pressed.emit()
	check(AudioServer.is_bus_mute(0) and sound.text.contains("VYP"),
		"clicking HUD sound switch really mutes master audio and changes label")
	sound.pressed.emit()
	check(not AudioServer.is_bus_mute(0) and sound.text.contains("ZAP"),
		"second click really enables audio")
	settings.set_value("audio_enabled", false, false)
	check(sound.text.contains("VYP") and w.settings_menu._audio_enabled != null,
		"HUD updates when audio setting is changed elsewhere")
	settings.set_value("audio_enabled", true, false)
	var checked := 0
	var unbound: Array = []
	var blank: Array = []
	for layer in [w.hud, w.settings_menu]:
		for b in layer.find_children("*", "BaseButton", true, false):
			checked += 1
			var connected: bool
			if b is OptionButton:
				connected = b.item_selected.get_connections().size() > 0
			elif b is CheckBox:
				connected = b.toggled.get_connections().size() > 0
			else:
				connected = b.pressed.get_connections().size() > 0
			if not connected:
				unbound.append(b.name)
			if b is Button and (b as Button).text.strip_edges() == "" and b.icon == null:
				blank.append(b.name)
	check(checked >= 20, "checked all currently instantiated main HUD and settings controls (%d)" % checked)
	check(unbound.is_empty(), "all currently instantiated buttons have signal callbacks", str(unbound))
	check(blank.is_empty(), "no unlabeled button without an icon", str(blank))
	check(w.hud._cmd_list.item_activated.get_connections().size() > 0 and
		w.hud._cmd_list.item_clicked.get_connections().size() > 0,
		"action-list click and activation trigger character commands")
	check(w.hud._world_popup.id_pressed.get_connections().size() > 0,
		"world-object popup actions have callbacks")
	settings.set_value("audio_enabled", initial_sound, false)
	w.queue_free()
	await get_tree().process_frame
	finish("test_eight_household_doors_audio")