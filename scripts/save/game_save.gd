extends RefCounted
## Offline save-game persistence. Never exposes private CharacterData to multiplayer.
## Binary Variant format disallows encoded Objects; checksum and bounded file sizes.
const CharacterValidator := preload("res://scripts/character/character_validator.gd")
const HouseholdDynamics := preload("res://scripts/sim/household_dynamics.gd")
const EmotionalState := preload("res://scripts/sim/emotional_state.gd")
const IntimacyState := preload("res://scripts/sim/intimacy_state.gd")
const PsycheExt := preload("res://scripts/sim/psyche_ext.gd")
const CharacterCodec := preload("res://scripts/character/character_codec.gd")
const VERSION := 1
const MAGIC := "LS-HOUSEHOLD"
const MAX_BYTES := 8 * 1024 * 1024
const MAX_SIMS := 32
const SAVE_SLOTS := ["autosave", "manual"]

var directory := "user://saves"


func _init(path: String = "user://saves") -> void:
	directory = path.trim_suffix("/")


func _path(slot: String, suffix: String = "") -> String:
	if not SAVE_SLOTS.has(slot):
		return ""
	return directory + "/" + slot + ".lss" + suffix


static func _sha(data: PackedByteArray) -> String:
	var h := HashingContext.new()
	if h.start(HashingContext.HASH_SHA256) != OK:
		return ""
	h.update(data)
	return h.finish().hex_encode()


static func _ref(world: Node, target: Variant) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	if world.sims.has(target):
		return {"sim": String(target.name)}
	var index: int = world.smart_objects.find(target)
	if index >= 0:
		return {"object": index}
	return {}


static func _resolve(world: Node, data: Variant) -> Node:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	if data.has("sim") and typeof(data["sim"]) == TYPE_STRING:
		return world.find_sim(data["sim"])
	if data.has("object") and typeof(data["object"]) == TYPE_INT:
		var i: int = data["object"]
		if i >= 0 and i < world.smart_objects.size():
			return world.smart_objects[i]
	return null


static func _commands(world: Node, queue: Array) -> Array:
	var out: Array = []
	for cmd in queue:
		if typeof(cmd) != TYPE_DICTIONARY:
			continue
		out.append({"action": (cmd.get("action", {}) as Dictionary).duplicate(true),
			"target": _ref(world, cmd.get("target")),
			"hesitated": bool(cmd.get("hesitated", false))})
	return out


static func capture(world: Node) -> Dictionary:
	if world == null or world.net == null or world.net.is_networked() or not world.net.is_authority():
		return {"ok": false, "reason": "offline_only"}
	var out: Array = []
	for sim in world.sims:
		if not is_instance_valid(sim) or not sim.has_method("command"):
			return {"ok": false, "reason": "invalid_agent"}
		var key: String = String(sim.name)
		if not world._character_records.has(key):
			return {"ok": false, "reason": "missing_record"}
		var state := {
			"position": sim.position, "rotation": sim.rotation, "seed": sim._seed,
			"rng_state": sim.rng.state,
			"needs": sim.needs.to_dict(), "mood": sim.mood.to_dict(),
			"mental": sim.mental.to_dict(), "ledger": sim.ledger.to_dict(),
			"emotions": sim.emotions.to_dict(),
			"intimacy": sim.intimacy.to_dict(),
			"sensory": sim.sensory.to_dict(), "vigilance": sim.vigilance.to_dict(),
			"rejection": sim.rejection.to_dict(),
			"psyche_ext": sim.psy.to_dict(),
			"state": sim.state, "action": sim.current_action.duplicate(true),
			"target": _ref(world, sim.target), "social_partner": _ref(world, sim.social_partner),
			"target_point": sim.target_point, "action_elapsed": sim.action_elapsed,
			"walk_elapsed": sim.walk_elapsed, "think_cooldown": sim.think_cooldown,
			"last_action_id": sim.last_action_id,
			"action_counts": sim.action_counts.duplicate(true),
			"relationships": sim.relationships.duplicate(true),
			"last_talk": sim.last_talk.duplicate(true), "memories": sim.memories.duplicate(true),
			"last_tag_time": sim.last_tag_time.duplicate(true),
			"player_queue": _commands(world, sim.player_queue),
			"speech": sim.speech, "speech_until": sim.speech_until,
			"by_player": sim.by_player, "insulted_by": sim.insulted_by.duplicate(true),
			"pending_complaints": sim.pending_complaints.duplicate(true),
			"social_arousal_start": sim._social_arousal_start,
			"social_positive": sim._social_positive,
			"confide_dismissed": sim._confide_dismissed,
			"crowd_timer": sim._crowd_timer,
			"helping_me": sim._helping_me,
			"witnessed_episode": sim._witnessed_episode,
			"last_coping_result": sim.last_coping_result.duplicate(true),
			"last_experience": sim.last_experience.duplicate(true),
			"last_apology": sim.last_apology.duplicate(true)
		}
		out.append({"node": key, "character": world._character_records[key].to_dict(),
			"revision": int(world._character_revisions.get(key, 0)), "state": state})
	if out.is_empty() or out.size() > MAX_SIMS:
		return {"ok": false, "reason": "roster_size"}
	var objs: Array = []
	for obj in world.smart_objects:
		var users: Array = []
		for sim in obj.users:
			if is_instance_valid(sim):
				users.append(String(sim.name))
		objs.append({"tag": String(obj.object_tag), "users": users})
	var d = world.dynamics
	var dynamics := {
		"acc": d._acc, "last_friction": d._last_friction.duplicate(true),
		"last_shared": d._last_shared.duplicate(true),
		"prev_acting": d._prev_acting.duplicate(true),
		"friction_day": d._friction_day.duplicate(true),
		"morning": d._morning.duplicate(true), "cooked": d._cooked.duplicate(true),
		"stats": d.stats.duplicate(true)
	}
	return {"ok": true, "data": {
		"version": VERSION,
		"clock": {"total_minutes": world.clock.total_minutes,
			"speed_index": world.clock.speed_index, "running": world.clock.running},
		"selected": int(world.selected), "sims": out,
		"objects": objs, "dynamics": dynamics}}


static func _finite_range(value: Variant, low: float, high: float) -> bool:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	var n: float = float(value)
	return is_finite(n) and n >= low and n <= high


static func _valid_ref(value: Variant, people: Dictionary, object_count: int) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	if value.is_empty():
		return true
	if value.size() != 1:
		return false
	if value.has("sim"):
		return typeof(value["sim"]) == TYPE_STRING and people.has(value["sim"])
	if value.has("object"):
		return typeof(value["object"]) == TYPE_INT and int(value["object"]) >= 0 and int(value["object"]) < object_count
	return false


static func validate_data(data: Variant, world: Node = null) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or data.get("version", -1) != VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	if typeof(data.get("clock")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "bad_clock"}
	var clock: Dictionary = data["clock"]
	if typeof(clock.get("total_minutes")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(clock["total_minutes"])) or float(clock["total_minutes"]) < 0.0 or float(clock["total_minutes"]) > 1.0e9:
		return {"ok": false, "reason": "bad_clock"}
	if typeof(clock.get("speed_index")) != TYPE_INT or int(clock["speed_index"]) < 0 or int(clock["speed_index"]) > 4:
		return {"ok": false, "reason": "bad_speed"}
	if typeof(clock.get("running")) != TYPE_BOOL:
		return {"ok": false, "reason": "bad_running"}
	var sims = data.get("sims")
	if typeof(sims) != TYPE_ARRAY or sims.is_empty() or sims.size() > MAX_SIMS:
		return {"ok": false, "reason": "bad_roster"}
	var nodes: Dictionary = {}
	for item in sims:
		if typeof(item) != TYPE_DICTIONARY or typeof(item.get("node")) != TYPE_STRING or typeof(item.get("state")) != TYPE_DICTIONARY or typeof(item.get("character")) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "bad_agent"}
		var name: String = item["node"]
		if name == "" or name.length() > 64 or name != name.validate_node_name() or nodes.has(name):
			return {"ok": false, "reason": "invalid_name"}
		nodes[name] = true
		# Uložená postava ze starší verze schématu se nejdřív zmigruje (v8 → v9 …), pak striktně ověří.
		var migrated: Dictionary = CharacterCodec.migrate(item["character"])
		if not bool(migrated.get("ok", false)):
			return {"ok": false, "reason": "invalid_character"}
		var char_result: Dictionary = CharacterValidator.validate(migrated["data"], {"mode": "strict"})
		if not bool(char_result.get("ok", false)):
			return {"ok": false, "reason": "invalid_character"}
		var state: Dictionary = item["state"]
		if typeof(state.get("position")) != TYPE_VECTOR3 or typeof(state.get("rotation")) != TYPE_VECTOR3 or typeof(state.get("rng_state")) != TYPE_INT:
			return {"ok": false, "reason": "bad_agent_state"}
		if typeof(state.get("state")) != TYPE_INT or int(state["state"]) not in [0, 1, 2]:
			return {"ok": false, "reason": "bad_action_state"}
		if not _finite_range(item.get("revision"), 0.0, 1.0e8) or not _finite_range(state.get("seed"), 0.0, 9.22e18):
			return {"ok": false, "reason": "bad_revision_or_seed"}
		var pos: Vector3 = state["position"]
		var rot: Vector3 = state["rotation"]
		for component in [pos.x, pos.y, pos.z, rot.x, rot.y, rot.z]:
			if not _finite_range(component, -1.0e4, 1.0e4):
				return {"ok": false, "reason": "bad_transform"}
		# Missing destination retains the existing v1 fallback to position.
		var destination = state.get("target_point", state["position"])
		if typeof(destination) != TYPE_VECTOR3:
			return {"ok": false, "reason": "bad_target_point"}
		for component in [destination.x, destination.y, destination.z]:
			if not _finite_range(component, -1.0e4, 1.0e4):
				return {"ok": false, "reason": "bad_target_point"}
		for part in ["needs", "mood", "mental", "ledger", "sensory", "vigilance", "rejection", "action"]:
			if typeof(state.get(part)) != TYPE_DICTIONARY:
				return {"ok": false, "reason": "bad_" + part}
		if typeof(state.get("player_queue")) != TYPE_ARRAY or state["player_queue"].size() > 3:
			return {"ok": false, "reason": "bad_queue"}
		var needs: Dictionary = state["needs"]
		if typeof(needs.get("values")) != TYPE_DICTIONARY or typeof(needs.get("decay_mult")) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "bad_needs"}
		for need in ["hunger", "energy", "hygiene", "fun", "social", "comfort"]:
			if not _finite_range(needs["values"].get(need), 0.0, 100.0) or not _finite_range(needs["decay_mult"].get(need), 0.0, 100.0):
				return {"ok": false, "reason": "bad_needs"}
		var mind: Dictionary = state["mental"]
		if not _finite_range(mind.get("stress"), 0.0, 100.0) or not _finite_range(mind.get("arousal"), 0.0, 100.0):
			return {"ok": false, "reason": "bad_mind"}
		if not _finite_range(mind.get("positive_arousal", 0.0), 0.0, 100.0) or not _finite_range(mind.get("threat"), 0.0, 1.0):
			return {"ok": false, "reason": "bad_mind"}
		# v1 saves from before the emotional layer have no emotions key.
		# New data is strictly validated *before* deleting the old household.
		if state.has("emotions") and not EmotionalState.validate_snapshot(state["emotions"]):
			return {"ok": false, "reason": "bad_emotions"}
		# Old H4 saves lack this field; new saves must match authoritative age.
		if state.has("intimacy") and not IntimacyState.validate_snapshot(state["intimacy"]):
			return {"ok": false, "reason": "bad_intimacy"}
		# Starší uložené hry rozšíření psychiky nemají (postava pak začne s čistým stavem).
		if state.has("psyche_ext") and not PsycheExt.validate_snapshot(state["psyche_ext"]):
			return {"ok": false, "reason": "bad_psyche_ext"}
		if state.has("intimacy") and int(state["intimacy"]["age"]) != int(item["character"]["body"]["age"]):
			return {"ok": false, "reason": "intimacy_age_mismatch"}
		if typeof(state["mood"].get("moodlets")) != TYPE_ARRAY or state["mood"]["moodlets"].size() > 512:
			return {"ok": false, "reason": "bad_mood"}
		if int(state["state"]) != 0 and not state["action"].has("id"):
			return {"ok": false, "reason": "missing_action"}
		if not _finite_range(state.get("action_elapsed"), 0.0, 1.0e7) or not _finite_range(state.get("walk_elapsed"), 0.0, 1.0e7):
			return {"ok": false, "reason": "bad_elapsed"}
		if not _finite_range(state.get("think_cooldown"), -1.0e7, 1.0e7):
			return {"ok": false, "reason": "bad_cooldown"}
	var objs = data.get("objects")
	if typeof(objs) != TYPE_ARRAY or typeof(data.get("dynamics")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "bad_environment"}
	if objs.size() > 256:
		return {"ok": false, "reason": "bad_environment"}
	for item in sims:
		var state: Dictionary = item["state"]
		if not _valid_ref(state.get("target", {}), nodes, objs.size()) or not _valid_ref(state.get("social_partner", {}), nodes, objs.size()):
			return {"ok": false, "reason": "bad_target"}
		for command in state["player_queue"]:
			if typeof(command) != TYPE_DICTIONARY or typeof(command.get("action")) != TYPE_DICTIONARY or not _valid_ref(command.get("target", {}), nodes, objs.size()):
				return {"ok": false, "reason": "bad_queue"}
	for obj in objs:
		if typeof(obj) != TYPE_DICTIONARY or typeof(obj.get("tag")) != TYPE_STRING or typeof(obj.get("users")) != TYPE_ARRAY:
			return {"ok": false, "reason": "bad_environment"}
		for name in obj["users"]:
			if typeof(name) != TYPE_STRING or not nodes.has(name):
				return {"ok": false, "reason": "bad_reservation"}
	if world != null:
		if objs.size() != world.smart_objects.size():
			return {"ok": false, "reason": "changed_lot"}
		for i in objs.size():
			if typeof(objs[i]) != TYPE_DICTIONARY or String(objs[i].get("tag", "")) != String(world.smart_objects[i].object_tag):
				return {"ok": false, "reason": "changed_lot"}
			var occupants = objs[i].get("users")
			if typeof(occupants) != TYPE_ARRAY or occupants.size() > world.smart_objects[i].capacity:
				return {"ok": false, "reason": "bad_reservation"}
			for person in occupants:
				if typeof(person) != TYPE_STRING or not nodes.has(person):
					return {"ok": false, "reason": "invalid_reservation"}
	return {"ok": true}


static func _restore_state(world: Node, sim: Node, data: Dictionary) -> void:
	sim.position = data["position"]
	sim.rotation = data["rotation"]
	sim.needs.from_dict(data["needs"])
	sim.mood.from_dict(data["mood"])
	sim.mental.from_dict(data["mental"])
	if data.has("emotions"):
		sim.emotions.from_dict(data["emotions"])
	if data.has("intimacy"):
		sim.intimacy.from_dict(data["intimacy"])
	sim.ledger.from_dict(data["ledger"])
	if data.has("psyche_ext"):
		sim.restore_psyche(data["psyche_ext"])
	for k in data["sensory"]:
		if k in ["hypersensitivity", "noise_sens", "crowd_sens", "joy_sens", "light_sens", "anticip_thr", "noise_habit", "crowd_habit"]:
			sim.sensory.set(k, float(data["sensory"][k]))
	for k in data["vigilance"]:
		if k in ["hypervigilance", "threat_sensitivity", "social_threat", "alertness"]:
			sim.vigilance.set(k, float(data["vigilance"][k]))
	for k in data["rejection"]:
		if k in ["reactivity", "distress", "recent_cues", "concern"]:
			sim.rejection.set(k, data["rejection"][k])
	sim.state = int(data["state"])
	sim.current_action = data["action"].duplicate(true)
	sim.target = _resolve(world, data.get("target", {}))
	sim.social_partner = _resolve(world, data.get("social_partner", {}))
	sim.target_point = data.get("target_point", sim.position)
	sim.action_elapsed = float(data.get("action_elapsed", 0.0))
	sim.walk_elapsed = float(data.get("walk_elapsed", 0.0))
	sim.think_cooldown = float(data.get("think_cooldown", 1.0))
	sim.last_action_id = String(data.get("last_action_id", ""))
	for field in ["action_counts", "relationships", "last_talk", "last_tag_time", "insulted_by", "pending_complaints",
			"last_coping_result", "last_experience", "last_apology"]:
		if typeof(data.get(field)) == TYPE_DICTIONARY:
			sim.set(field, data[field].duplicate(true))
	if typeof(data.get("memories")) == TYPE_ARRAY:
		sim.memories = data["memories"].duplicate(true)
	sim.player_queue = []
	for command in data["player_queue"]:
		if typeof(command) == TYPE_DICTIONARY and typeof(command.get("action")) == TYPE_DICTIONARY:
			sim.player_queue.append({"action": command["action"].duplicate(true),
				"target": _resolve(world, command.get("target", {})),
				"hesitated": bool(command.get("hesitated", false))})
	sim.speech = String(data.get("speech", ""))
	sim.speech_until = float(data.get("speech_until", -1.0))
	sim.by_player = bool(data.get("by_player", false))
	sim._social_arousal_start = float(data.get("social_arousal_start", 0.0))
	sim._social_positive = bool(data.get("social_positive", true))
	sim._confide_dismissed = bool(data.get("confide_dismissed", false))
	sim._crowd_timer = float(data.get("crowd_timer", 0.0))
	sim._helping_me = int(data.get("helping_me", 0))
	sim._witnessed_episode = int(data.get("witnessed_episode", -1))
	# Restore RNG last: spawning and initial mood setup consume random values.
	sim.rng.state = int(data["rng_state"])
	sim.mood.evaluate(sim.needs, sim.trait_profile, sim._extra_moodlets())
	sim._detail_dirty = true
	sim._update_net(0.0)
	sim._update_visual()


static func apply(world: Node, data: Variant) -> Dictionary:
	if world == null or world.net == null or world.net.is_networked():
		return {"ok": false, "reason": "offline_only"}
	var check: Dictionary = validate_data(data, world)
	if not bool(check["ok"]):
		return check
	var previous_running: bool = world.clock.running
	world.clock.running = false
	# All validation happens before discarding the old household.
	for sim in world.sims.duplicate():
		if is_instance_valid(sim):
			sim.leave_world()
			world.unregister_sim(sim)
			sim.free()
	world.dynamics = HouseholdDynamics.new()
	for item in data["sims"]:
		var st: Dictionary = item["state"]
		var created = world.spawn_character(CharacterCodec.migrate(item["character"])["data"], st["position"], int(st.get("seed", 1)), String(item["node"]))
		if created == null:
			world.clock.running = previous_running
			return {"ok": false, "reason": "spawn_failed"}
		world._character_revisions[String(created.name)] = int(item.get("revision", 0))
	# Second pass resolves cross-character references and object reservations.
	for item in data["sims"]:
		var sim = world.find_sim(String(item["node"]))
		_restore_state(world, sim, item["state"])
	for i in world.smart_objects.size():
		var obj = world.smart_objects[i]
		obj.users.clear()
		for node_name in data["objects"][i]["users"]:
			obj.users.append(world.find_sim(String(node_name)))
	var dy: Dictionary = data["dynamics"]
	for pair in [["acc", "_acc"], ["last_friction", "_last_friction"],
			["last_shared", "_last_shared"], ["prev_acting", "_prev_acting"],
			["friction_day", "_friction_day"], ["morning", "_morning"],
			["cooked", "_cooked"], ["stats", "stats"]]:
		var key: String = pair[0]
		if dy.has(key):
			world.dynamics.set(pair[1], dy[key].duplicate(true) if typeof(dy[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else dy[key])
	world.clock.total_minutes = float(data["clock"]["total_minutes"])
	world.clock._last_hour = world.clock.get_hour()
	world.clock._last_day = world.clock.get_day()
	world.clock.set_speed(int(data["clock"]["speed_index"]))
	world.selected = clampi(int(data.get("selected", 0)), 0, maxi(world.sims.size() - 1, 0))
	world.clock.running = bool(data["clock"].get("running", previous_running))
	return {"ok": true, "restored": world.sims.size(), "day": world.clock.get_day()}


func save_slot(slot: String, data: Dictionary) -> Dictionary:
	var dst: String = _path(slot)
	if dst == "":
		return {"ok": false, "reason": "bad_slot"}
	var valid: Dictionary = validate_data(data)
	if not valid.get("ok", false):
		return valid
	var payload := var_to_bytes(data)
	if payload.is_empty() or payload.size() > MAX_BYTES - 1024:
		return {"ok": false, "reason": "size"}
	var wire := var_to_bytes({"magic": MAGIC, "version": VERSION, "sha256": _sha(payload),
		"payload": payload, "saved_unix": int(Time.get_unix_time_from_system())})
	if wire.size() > MAX_BYTES:
		return {"ok": false, "reason": "size"}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return {"ok": false, "reason": "mkdir"}
	var tmp := dst + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "open"}
	f.store_buffer(wire)
	f.flush()
	f.close()
	var readback := _read_file(tmp)
	if not readback.get("ok", false):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return {"ok": false, "reason": "verify"}
	# A valid previous primary is archived, never a corrupt primary.
	var previous: Dictionary = _read_file(dst)
	var backup: String = _path(slot, ".bak")
	if bool(previous.get("ok", false)):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(dst), ProjectSettings.globalize_path(backup)) != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
			return {"ok": false, "reason": "backup_failed"}
	elif FileAccess.file_exists(dst):
		# Never DELETE a possibly valid primary on a transient read failure.
		# Quarantine it before replacement, keep an existing valid .bak.
		var invalid: String = _path(slot, ".invalid")
		if FileAccess.file_exists(invalid):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid)) != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
				return {"ok": false, "reason": "quarantine_failed"}
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(dst), ProjectSettings.globalize_path(invalid)) != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
			return {"ok": false, "reason": "quarantine_failed"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(dst)) != OK:
		if not FileAccess.file_exists(dst):
			if bool(previous.get("ok", false)) and FileAccess.file_exists(backup):
				DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(dst))
			elif FileAccess.file_exists(_path(slot, ".invalid")):
				DirAccess.rename_absolute(ProjectSettings.globalize_path(_path(slot, ".invalid")), ProjectSettings.globalize_path(dst))
		return {"ok": false, "reason": "replace_failed"}
	return {"ok": true, "slot": slot, "bytes": wire.size(), "path": dst}


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "open"}
	var length: int = f.get_length()
	if length < 32 or length > MAX_BYTES:
		return {"ok": false, "reason": "size"}
	var wire: PackedByteArray = f.get_buffer(length)
	if wire.size() != length:
		return {"ok": false, "reason": "truncated"}
	# allow_objects=false: hostile saves may NOT create arbitrary Godot Objects.
	var envelope = bytes_to_var(wire)
	if typeof(envelope) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "format"}
	if envelope.get("magic") != MAGIC or envelope.get("version") != VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	if typeof(envelope.get("payload")) != TYPE_PACKED_BYTE_ARRAY:
		return {"ok": false, "reason": "format"}
	var payload: PackedByteArray = envelope["payload"]
	if payload.size() <= 0 or payload.size() > MAX_BYTES or envelope.get("sha256") != _sha(payload):
		return {"ok": false, "reason": "checksum"}
	var decoded = bytes_to_var(payload)
	var valid: Dictionary = validate_data(decoded)
	if not valid.get("ok", false):
		return valid
	return {"ok": true, "data": decoded}


func load_slot(slot: String) -> Dictionary:
	var primary: String = _path(slot)
	if primary == "":
		return {"ok": false, "reason": "bad_slot"}
	var r := _read_file(primary)
	if bool(r.get("ok", false)):
		r["source"] = "primary"
		return r
	var backup := _read_file(_path(slot, ".bak"))
	if bool(backup.get("ok", false)):
		backup["source"] = "backup"
		return backup
	return {"ok": false, "reason": String(r.get("reason", "missing")),
		"backup_reason": String(backup.get("reason", "missing"))}
