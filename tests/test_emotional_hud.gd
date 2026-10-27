extends "res://tests/test_base.gd"
## Real offline HUD panel, collapsible scrollable 19-axis display.
const Main := preload("res://main.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const Emotions := preload("res://scripts/sim/emotional_state.gd")
var hud
var world
var clock
var gs

func _ready() -> void:
	watchdog_seconds = 30.0
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	clock = get_node("/root/GameClock")
	clock.running = false
	_run.call_deferred()


func _run() -> void:
	section("Full HUD emotion popup with real selected adult NPC")
	Main.household_override = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/data/extreme_profiles_fictional8.json"))
	clock.total_minutes = 480.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	world = Node3D.new()
	world.set_script(Main)
	world.name = "EmotionHudWorld"
	world.net_config = {"mode": "offline", "audio": false, "hud": false,
		"camera": false, "visuals": false, "autoload": false,
		"autosave": false, "clock": clock}
	add_child(world)
	hud = HUD.new()
	hud.main = world
	add_child(hud)
	await get_tree().process_frame
	hud._refresh = -1.0
	hud._process(1.0)
	check(hud._emotion_button != null and hud._emotion_button.visible,
		"real selected offline owner has an emotion details control")
	check(hud._emotion_bars.size() == 19 and hud._emotion_bars.has("sadness")
		and hud._emotion_bars.has("uncertainty"),
		"popup renders all 19 independently named bars")
	check(hud._emotion_popup != null and hud._emotion_top != null,
		"popup has its own scrolling area and top-three summary")
	check(hud._emotion_bars.values().all(func(bar): return (bar as ProgressBar).show_percentage),
		"all nineteen meters show their numerical percentage")
	check(HUD.emotion_popup_size(Vector2(300.0, 420.0)) == Vector2i(284, 404),
		"narrow mobile viewport limits popup dimensions")
	var raven = world.find_sim("Raven_Vale")
	check(raven == world.get_selected_sim(),
		"the first selected agent is Raven for this foreign-name fixture")
	if raven != null:
		raven.emotions.shift("sadness", 77.0)
		raven.emotions.shift("joy", 55.0)
		raven.emotions.impulse("rejection_perceived", "Iris_North")
		hud._refresh = -1.0
		hud._process(1.0)
		check(raven.emotions.level("sadness") > 70.0 and raven.emotions.level("joy") > 50.0
			and absf(hud._emotion_bars["sadness"].value - raven.emotions.level("sadness")) < 0.001
			and absf(hud._emotion_bars["joy"].value - raven.emotions.level("joy")) < 0.001,
			"separate sadness and joy are shown at the same time")
		check("Iris North" in hud._emotion_people.text,
			"person-directed emotion is shown with that person's name, not a public label")
	hud._on_emotion_details()
	check(hud._emotion_popup.visible, "player can open the expandable emotional panel")
	hud._on_emotion_details()
	check(not hud._emotion_popup.visible, "player can close it again")
	# The exact multiplayer guard is verified by code, rather than forcibly
	# mutating the actual ENet transport mode in this isolated UI test.
	check(not raven._build_detail().has("emotion_levels")
		and not raven.net_detail.has("emotion_toward"),
		"emotional panel data never enters broadcast/owner network detail")
	hud.free()
	world.free()
	clock.running = false
	Main.household_override = []
	gs.reset()
	finish("test_emotional_hud")
