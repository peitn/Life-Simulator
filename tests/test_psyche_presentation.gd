extends "res://tests/test_base.gd"
## Test prezentace psychického stavu: PsycheFX (vinětace/desaturace), zvuk (low-pass hudby,
## tlukot srdce), respektování nastavení zkreslení, HUD duševního stavu a myšlenek,
## menu s obsahovým varováním a krizovou pomocí.

const Main := preload("res://main.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")

var world: Node3D
var clock: Node
var gs: Node
var audio: Node


func _ready() -> void:
	watchdog_seconds = 40.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	audio = get_node("/root/AudioManager")
	world = Node3D.new()
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": true, "hud": true, "camera": false, "visuals": false}
	add_child(world)
	_run.call_deferred()


func _run() -> void:
	var eli = world.find_sim(SimAgent.node_name_for("Eliška Malá"))
	world.selected = world.get_sims().find(eli)
	for s in world.get_sims():
		s.think_cooldown = 1.0e9

	section("Klid → žádné zkreslení")
	await wait_seconds(0.5)
	check(world.psyche_fx.level < 0.05, "v klidu je obraz bez zkreslení", "%.2f" % world.psyche_fx.level)

	section("Panická ataka → obraz i zvuk")
	eli.mental._start_panic()
	clock.advance(1.0)
	check(eli._in_panic_action(), "ataka běží")
	await wait_seconds(2.5)
	check(world.psyche_fx.level > 0.5, "vinětace a desaturace naběhnou", "%.2f" % world.psyche_fx.level)
	check(audio.psyche_level > 0.5, "AudioManager dostal úroveň úzkosti", "%.2f" % audio.psyche_level)
	check(audio.heartbeats() > 0, "ozývá se tlukot srdce", str(audio.heartbeats()))
	var mus := AudioServer.get_bus_index("Music")
	var lp := AudioServer.get_bus_effect(mus, 1) as AudioEffectLowPassFilter
	check(lp != null and lp.cutoff_hz < 5000.0, "hudba je tlumená low-passem", "%.0f Hz" % (lp.cutoff_hz if lp != null else -1.0))
	var hud = world.hud
	await wait_seconds(0.3)
	check(hud._mind_label.text.find("Panická ataka") >= 0, "HUD ukazuje duševní stav", hud._mind_label.text)
	check(hud._arousal_bar.value > 60.0, "lišta napětí je vysoko")

	section("Nastavení: zkreslení vypnuto")
	gs.set_value("distortion_fx", false)
	await wait_seconds(4.5)
	check(world.psyche_fx.level < 0.05, "po vypnutí zkreslení se obraz vrátí", "%.2f" % world.psyche_fx.level)
	check(audio.psyche_level < 0.05 and lp.cutoff_hz > 15000.0, "zvuk se vrátí do normálu")
	gs.reset()

	section("Myšlenky v HUD")
	eli.mental.add_thought("social", clock.total_minutes, {}, {"thought_rate": 1.0})
	eli._detail_dirty = true
	await wait_seconds(0.4)
	var shown := false
	for c in hud._thought_box.get_children():
		if c is Label and c.text.find("myšlenka, ne fakt") >= 0:
			shown = true
	check(shown, "myšlenka je v HUD označená jako myšlenka, ne fakt")
	gs.set_value("intrusive_thoughts", 0)
	await wait_seconds(0.4)
	var visible_count := 0
	for c in hud._thought_box.get_children():
		if not c.is_queued_for_deletion():
			visible_count += 1
	check(visible_count == 0, "vypnuté myšlenky z HUD zmizí", str(visible_count))
	gs.reset()

	section("Menu, varování a krizová pomoc")
	var menu = world.settings_menu
	check(menu != null and not menu.is_open(), "menu existuje a je zavřené")
	menu.show_first_run_warning()
	check(menu._warning.visible, "obsahové varování se ukáže, dokud ho hráč nepotvrdí")
	menu._ack_warning("muted")
	check(not menu._warning.visible and bool(gs.get_value("warning_ack")) and gs.get_value("mental_health") == "muted",
		"potvrzení s volbou „ztlumit“ uloží nastavení")
	menu.show_first_run_warning()
	check(not menu._warning.visible, "po potvrzení se varování už samo neukazuje")
	menu.toggle()
	check(menu._menu.visible and menu._mh.selected == 1, "menu (Esc) ukazuje aktuální nastavení")
	var crisis := false
	for n in menu._menu.find_children("*", "Label", true, false):
		if String(n.text).find("116 123") >= 0:
			crisis = true
	check(crisis, "menu obsahuje Linku první psychické pomoci 116 123")
	menu._thoughts.select(0)
	menu._thoughts.item_selected.emit(0)
	check(int(gs.get_value("intrusive_thoughts")) == 0, "změna v menu se propíše do nastavení")
	menu.toggle()
	gs.reset()
	finish("test_psyche_presentation")
