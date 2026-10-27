extends Node
## Zvuky z konektoru Audio Engine (Surge XT + vestavěný syntezátor, 27. 10. 2026).
## Soubory leží v res://audio/engine/ (mono 22 050 Hz, 16 bit, verzované v gitu – na rozdíl
## od audio/music a audio/sfx je nejde přegenerovat nástrojem tools/build_audio.gd).
## - kroky: dřevěná podlaha uvnitř domu, tráva venku; kadence podle skutečné rychlosti chůze
## - zvuky činností bez vlastního objektu: listování knihou, ťukání do telefonu, psaní deníku
## - jednorázové zvuky: lednice (svačina, pivo), otevření lahve, šustění peřiny (spánek, úkryt)
## - noční tikání hodin v bytě (vrstva ambience)
## - hudba editoru/tvorby postavy (Surge XT: zvonky + tmavý pad + sub basa, a moll, 66 BPM)
## Jen kosmetika na tomto peeru – žádný vliv na simulaci ani síť.

const WavLoader := preload("res://scripts/audio/wav_loader.gd")
const ENGINE_DIR := "res://audio/engine/"
const CREATOR_TRACK := "creator"
## Půdorys domu (podlaha 12,4 × 9,4 m se středem v počátku) – uvnitř dřevo, venku tráva.
const HOUSE_HALF := Vector2(6.2, 4.7)
## Délka kroku (m) → interval mezi kroky = STRIDE / rychlost.
const STRIDE := 0.7
const MIN_STEP_INTERVAL := 0.2
const MAX_STEP_INTERVAL := 0.9
## Pod touto vodorovnou rychlostí (m/s) postava nejde.
const WALK_SPEED_MIN := 0.35
## Kroky dál než tohle od kamery/vybrané postavy nehrajeme vůbec (šetří hlasy).
const STEP_HEAR_DIST := 22.0
const STEP_DB := -13.0
const LOOP_DB := -11.0
const ONESHOT_DB := -7.0
const WOOD := ["step_wood_1", "step_wood_2", "step_wood_3", "step_wood_4"]
const GRASS := ["step_grass_1", "step_grass_2", "step_grass_3", "step_grass_4"]
## Činnost → smyčka po dobu činnosti (zvuk je u postavy, ne u objektu).
const ACTION_LOOPS := {"read": "loop_pages", "text_friend": "loop_phone", "doomscroll": "loop_phone", "journal": "loop_pen"}
## Činnost → jednorázové zvuky na začátku (s malým odstupem).
const ACTION_ONESHOTS := {
	"snack": ["sfx_fridge"],
	"drink": ["sfx_fridge", "sfx_bottle"],
	"sleep": ["loop_duvet"],
	"nap": ["loop_duvet"],
	"hide": ["loop_duvet"],
}
const ALL_IDS := ["step_wood_1", "step_wood_2", "step_wood_3", "step_wood_4",
		"step_grass_1", "step_grass_2", "step_grass_3", "step_grass_4",
		"amb_clock", "sfx_bottle", "sfx_fridge", "loop_pages", "loop_phone", "loop_pen",
		"loop_duvet", "music_creator"]

var am: Node = null
var stats := {"steps": 0, "steps_wood": 0, "steps_grass": 0, "loops": 0, "oneshots": 0}
var _walk := {}      # sim -> {"last": Vector3, "t": float, "i": int, "player": AudioStreamPlayer3D}
var _loops := {}     # sim -> AudioStreamPlayer3D
var _clock_player: AudioStreamPlayer
var _clock_level := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0xAE27
	_clock_player = AudioStreamPlayer.new()
	_clock_player.bus = "Ambience"
	_clock_player.stream = WavLoader.load_wav(ENGINE_DIR + "amb_clock.wav", true)
	_clock_player.volume_db = -60.0
	add_child(_clock_player)
	if _clock_player.stream != null:
		_clock_player.play()


static func path(id: String) -> String:
	return ENGINE_DIR + id + ".wav"


## Povrch pod nohama podle pozice (uvnitř domu dřevo, venku tráva).
static func surface_at(pos: Vector3) -> String:
	if absf(pos.x) < HOUSE_HALF.x and absf(pos.z) < HOUSE_HALF.y:
		return "wood"
	return "grass"


## Interval mezi kroky (s) pro danou vodorovnou rychlost; 0 = postava nejde.
static func step_interval(speed: float) -> float:
	if speed < WALK_SPEED_MIN:
		return 0.0
	return clampf(STRIDE / speed, MIN_STEP_INTERVAL, MAX_STEP_INTERVAL)


## Hlasitost nočního tikání hodin (0..1) podle hodiny – jen v noci, v tichu bytu.
static func clock_weight(hours: float) -> float:
	var night := 1.0 - smoothstep(5.0, 6.5, hours) + smoothstep(21.5, 23.0, hours)
	return clampf(night, 0.0, 1.0) * 0.32


static func sounds_for_action(id: String) -> Dictionary:
	return {"loop": ACTION_LOOPS.get(id, ""), "oneshots": ACTION_ONESHOTS.get(id, [])}


## Je otevřený editor nebo tvorba postavy? (pak hraje hudba editoru)
func editor_open() -> bool:
	var main = am.main if am != null else null
	if main == null or not is_instance_valid(main):
		return false
	var hud = main.get("hud")
	if hud == null or not is_instance_valid(hud):
		return false
	for key in ["_character_editor", "_character_creator"]:
		var panel = hud.get(key)
		if panel != null and is_instance_valid(panel) and panel.is_inside_tree():
			return true
	return false


func register_sim(sim: Node) -> void:
	if not sim.has_signal("action_started") or sim.action_started.is_connected(_on_action_started):
		return
	sim.action_started.connect(_on_action_started)
	sim.action_finished.connect(_on_action_finished)


func update(delta: float, hours: float, speed_index: int) -> void:
	_clock_level = move_toward(_clock_level, clock_weight(hours), delta * 0.2)
	if _clock_player != null:
		_clock_player.volume_db = linear_to_db(maxf(_clock_level, 0.001))
	_update_steps(delta, speed_index)


func _listener_pos() -> Variant:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam.global_position
	return null


func _update_steps(delta: float, speed_index: int) -> void:
	var main = am.main if am != null else null
	if main == null or not is_instance_valid(main) or not main.has_method("get_sims") or delta <= 0.0:
		return
	var listener = _listener_pos()
	var seen := {}
	for sim in main.get_sims():
		if not (sim is Node3D) or not is_instance_valid(sim) or not sim.is_inside_tree():
			continue
		seen[sim] = true
		var pos: Vector3 = sim.global_position
		var st: Dictionary = _walk.get(sim, {})
		if st.is_empty():
			_walk[sim] = {"last": pos, "t": 0.0, "i": _rng.randi_range(0, 3), "player": null}
			continue
		var d := Vector2(pos.x - st["last"].x, pos.z - st["last"].z).length()
		st["last"] = pos
		# Teleport (načtení hry, posazení) není chůze.
		if d > 2.0:
			st["t"] = 0.0
			continue
		var interval := step_interval(d / delta)
		if interval <= 0.0 or speed_index >= 3:
			st["t"] = 0.0
			continue
		st["t"] = float(st["t"]) + delta
		if float(st["t"]) < interval:
			continue
		st["t"] = 0.0
		if listener != null and (listener as Vector3).distance_to(pos) > STEP_HEAR_DIST:
			continue
		_play_step(sim, st, pos)
	for k in _walk.keys():
		if not seen.has(k):
			var p = _walk[k].get("player")
			if p != null and is_instance_valid(p):
				p.queue_free()
			_walk.erase(k)


func _play_step(sim: Node3D, st: Dictionary, pos: Vector3) -> void:
	var surf := surface_at(pos)
	var ids: Array = WOOD if surf == "wood" else GRASS
	st["i"] = (int(st["i"]) + 1 + _rng.randi_range(0, 1)) % ids.size()
	var s := WavLoader.load_wav(path(ids[st["i"]]), false)
	if s == null:
		return
	var p = st.get("player")
	if p == null or not is_instance_valid(p):
		p = AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 2.5
		p.max_distance = STEP_HEAR_DIST
		p.position = Vector3(0, 0.05, 0)
		sim.add_child(p)
		st["player"] = p
	p.stream = s
	p.volume_db = STEP_DB + _rng.randf_range(-1.5, 1.0)
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	p.play()
	stats["steps"] += 1
	stats["steps_" + surf] += 1


func _on_action_started(sim: Node3D, action: Dictionary) -> void:
	if sim == null or not is_instance_valid(sim) or not sim.is_inside_tree():
		return
	var snd := sounds_for_action(String(action.get("id", "")))
	var delay := 0.0
	for id in snd["oneshots"]:
		_oneshot_later(sim, String(id), delay)
		delay += 0.55
	if String(snd["loop"]) != "":
		_start_loop(sim, String(snd["loop"]))


func _oneshot_later(sim: Node3D, id: String, delay: float) -> void:
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(_oneshot.bind(sim, id))
	else:
		_oneshot(sim, id)


func _oneshot(sim, id: String) -> void:
	if sim == null or not is_instance_valid(sim) or not sim.is_inside_tree():
		return
	var s := WavLoader.load_wav(path(id), false)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.unit_size = 3.0
	p.max_distance = 26.0
	p.position = Vector3(0, 1.0, 0)
	p.volume_db = ONESHOT_DB - (5.0 if id == "loop_duvet" else 0.0)
	sim.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	stats["oneshots"] += 1


func _start_loop(sim: Node3D, id: String) -> void:
	_stop_loop(sim)
	var s := WavLoader.load_wav(path(id), true)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.unit_size = 2.0
	p.max_distance = 18.0
	p.position = Vector3(0, 1.0, 0)
	p.volume_db = -40.0
	sim.add_child(p)
	p.play(_rng.randf() * 2.0)
	if is_inside_tree():
		create_tween().tween_property(p, "volume_db", LOOP_DB, 0.4)
	_loops[sim] = p
	stats["loops"] += 1


func _stop_loop(sim) -> void:
	if not _loops.has(sim):
		return
	var p = _loops[sim]
	_loops.erase(sim)
	if p == null or not is_instance_valid(p):
		return
	if is_inside_tree() and p.is_inside_tree():
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -40.0, 0.4)
		tw.tween_callback(p.queue_free)
	else:
		p.queue_free()


func _on_action_finished(sim: Node3D, _id: String, _interrupted: bool) -> void:
	_stop_loop(sim)


func active_loops() -> int:
	for k in _loops.keys():
		if not is_instance_valid(k) or not is_instance_valid(_loops[k]):
			_loops.erase(k)
	return _loops.size()
