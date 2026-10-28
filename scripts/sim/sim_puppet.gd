extends Node3D
## Klientská „loutka“ postavy v multiplayeru. Nic nesimuluje – stav dostává ze serveru
## přes MultiplayerSynchronizer (vlastnosti `net_*`), pohyb plynule interpoluje
## a z `net_action` odvozuje signály akcí (pro 3D zvuky objektů na klientu).

const Needs := preload("res://scripts/sim/needs.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")
const Validator := preload("res://scripts/character/character_validator.gd")

signal action_started(sim: Node3D, action: Dictionary)
signal action_finished(sim: Node3D, action_id: String, interrupted: bool)
## Same public speech event as SimAgent.speech_started, raised when the replicated line changes.
signal speech_started(sim: Node3D, text: String)

## Vzdálenost, nad kterou se loutka teleportuje (např. vstává z postele).
const SNAP_DIST := 2.5
const FOLLOW_RATE := 10.0

var sim_name := "Postava"
var grammar := "m"
var female: bool:
	get:
		return grammar == "f"
var body_color := Color.GRAY
## Veřejný vzhledový snapshot (opravený validátorem – data ze sítě se neberou naslepo).
var look := {}
var trait_ids: Array = []
## Svět – kvůli převodu indexu objektu na uzel (zvuky).
var world: Node = null
## Objekt, se kterým postava právě pracuje (null = žádný).
var target: Node3D = null
var current_action: Dictionary = {}

var net_pos := Vector3.ZERO:
	set(v):
		net_pos = v
		if not _has_pos or position.distance_to(v) > SNAP_DIST:
			position = v
			_has_pos = true
var net_rot := 0.0
var net_label := ""
var net_emotion := "spokojeny"
var net_mood := 0
var net_posture := "stand"
var net_action := "":
	set(v):
		if v != net_action:
			_on_net_action(net_action, v)
		net_action = v
var net_speech := "":
	set(v):
		var changed: bool = v != net_speech
		net_speech = v
		if changed and v != "":
			speech_started.emit(self, v)
## Soukromý stav – dostává jen vlastník postavy (NetSession._s2c_private).
var net_needs := PackedByteArray()
var net_detail := {}
var has_private := false

var visual: Node3D
var stats := {"actions_started": 0, "actions_finished": 0}
var _has_pos := false


func setup_from_data(d: Dictionary, p_world: Node) -> void:
	sim_name = String(d.get("name", "Postava"))
	grammar = Grammar.norm(d.get("grammar", "m"))
	body_color = d.get("color", Color.GRAY)
	trait_ids = d.get("traits", []).duplicate()
	var lk = d.get("look", {})
	look = Validator.repaired(lk, {"public_only": true}) if typeof(lk) == TYPE_DICTIONARY and not lk.is_empty() else {}
	world = p_world
	name = String(d.get("node_name", sim_name))
	net_pos = d.get("pos", Vector3.ZERO)


func _ready() -> void:
	visual = SimVisual.new()
	visual.configure(body_color, female)
	if not look.is_empty():
		visual.apply_look(look)
	add_child(visual)


## Public appearance only; never merge full private character data into a puppet.
func apply_public_look(snapshot: Dictionary) -> void:
	var checked: Dictionary = Validator.validate(snapshot, {"mode":"strict", "public_only":true})
	if not checked.get("ok", false):
		return
	look = checked["data"].duplicate(true)
	if is_instance_valid(visual):
		visual.apply_look(look)


func _process(delta: float) -> void:
	position = position.lerp(net_pos, clampf(delta * FOLLOW_RATE, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, net_rot, clampf(delta * FOLLOW_RATE, 0.0, 1.0))
	if visual != null:
		visual.apply(net_posture, float(net_mood), net_emotion, sim_name, net_label, net_speech)


func _on_net_action(old: String, nw: String) -> void:
	if old != "":
		var old_id := old.split("|")[0]
		action_finished.emit(self, old_id, false)
		stats["actions_finished"] += 1
		target = null
		current_action = {}
	if nw != "":
		var parts := nw.split("|")
		current_action = ActionLibrary.get_action(parts[0])
		if current_action.is_empty():
			return
		target = null
		if parts.size() > 1 and parts[1].is_valid_int() and world != null:
			var idx := int(parts[1])
			var objs: Array = world.get_smart_objects()
			if idx >= 0 and idx < objs.size():
				target = objs[idx]
		action_started.emit(self, current_action)
		stats["actions_started"] += 1


func apply_private(needs: PackedByteArray, detail: Dictionary) -> void:
	net_needs = needs
	net_detail = detail
	has_private = true


func first_name() -> String:
	return sim_name.split(" ")[0]


func display_action() -> String:
	return net_label


func get_mood_value() -> float:
	return float(net_mood)


func get_emotion() -> String:
	return net_emotion


## Data pro HUD – stejný formát jako SimAgent.hud_info().
func hud_info() -> Dictionary:
	var nv := {}
	for i in Needs.KEYS.size():
		nv[Needs.KEYS[i]] = float(net_needs[i]) if i < net_needs.size() else 0.0
	var d: Dictionary = net_detail.duplicate(true)
	if not d.has("traits"):
		d["traits"] = trait_ids
	d["name"] = sim_name
	d["mood"] = float(net_mood)
	d["emotion"] = net_emotion
	d["action"] = net_label
	d["needs"] = nv
	d["private"] = has_private
	return d
