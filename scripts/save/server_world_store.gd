extends RefCounted
## H4b – serverové ukládání multiplayerového světa (hostitel i dedikovaný server).
##
## Snímek = offline formát GameSave (stejná validace postav a stavu, atomický zápis přes .tmp,
## záloha .bak, SHA-256 kontrola, bytes_to_var bez Objectů) + sekce "server":
##   {"v": 1, "own": [uzly vlastních postav hráčů], "held": [{hash, sim, name, own, remaining}], "host_sim": uzel}
## * "held" nese JEN SHA-256 hash jednorázového reconnect tokenu (server token v čisté podobě
##   nikdy nemá). Po restartu serveru se hráč vrátí ke své postavě tím samým tokenem jako v H4a.
## * Soubor obsahuje i soukromá data postav (mind, predispozice, paměť) – zůstává jen na disku
##   serveru; klienti dál dostávají jen veřejný vzhled a vlastník svůj soukromý stav.
## * Obnova jen do prázdného světa před prvním klientem. Vše se validuje dřív, než se cokoli
##   spawne; nevalidní soubor = server začne s čerstvou domácností (fail-closed, žádný pád).
## * Vlastní postava hráče, který se po restartu vrátit nemůže (bez držení), se neobnoví – to platí
##   i pro postavu hostitele, když snímek z listen serveru načte dedikovaný server (nemá hostitele).
## * Hrozba „útočník zapisuje na disk serveru“ je mimo model: takový útočník může přepsat cokoli
##   (i hash držení). Validace chrání před poškozením a nekonzistencí, ne před vlastníkem disku.

const SaveGame := preload("res://scripts/save/game_save.gd")
const Protocol := preload("res://scripts/net/net_protocol.gd")

const SERVER_VERSION := 1
const SLOT := "autosave"
## Víc držení, než může být hráčů a vlastních postav současně, nedává smysl.
const MAX_HELD := Protocol.MAX_CLIENTS + Protocol.MAX_PLAYER_CHARACTERS
const HASH_LEN := 64
## Horní mez uloženého zbytku lhůty (s); skutečnou lhůtu stejně omezí reconnect_grace_seconds.
const MAX_REMAINING := 86400.0

var store: SaveGame


func _init(directory: String) -> void:
	store = SaveGame.new(directory)


## Snímek živého serverového světa (jen autorita v síťovém režimu).
static func capture(world: Node) -> Dictionary:
	if world == null or world.net == null or not world.net.is_networked() or not world.net.is_authority():
		return {"ok": false, "reason": "server_only"}
	var base: Dictionary = SaveGame.capture(world, true)
	if not bool(base.get("ok", false)):
		return base
	var data: Dictionary = base["data"]
	var own: Array = []
	for sim in world.sims:
		if is_instance_valid(sim) and bool(sim.get_meta("player_character", false)):
			own.append(String(sim.name))
	var snap: Dictionary = world.net.persist_snapshot()
	data["server"] = {"v": SERVER_VERSION, "own": own, "held": snap["held"], "host_sim": String(snap["host_sim"])}
	var check := validate_server_section(data)
	if not bool(check["ok"]):
		return check
	return {"ok": true, "data": data}


static func _valid_hash(h: Variant) -> bool:
	if typeof(h) != TYPE_STRING or String(h).length() != HASH_LEN:
		return false
	var t := String(h)
	for i in t.length():
		var c := t.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## Přísná kontrola serverové sekce proti seznamu postav v témže snímku.
static func validate_server_section(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("sims")) != TYPE_ARRAY:
		return {"ok": false, "reason": "bad_roster"}
	var nodes := {}
	for item in data["sims"]:
		if typeof(item) == TYPE_DICTIONARY and typeof(item.get("node")) == TYPE_STRING:
			nodes[String(item["node"])] = true
	var sec = data.get("server")
	if typeof(sec) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "missing_server_section"}
	if typeof(sec.get("v")) != TYPE_INT or int(sec["v"]) != SERVER_VERSION:
		return {"ok": false, "reason": "unsupported_server_version"}
	for key in sec:
		if String(key) not in ["v", "own", "held", "host_sim"]:
			return {"ok": false, "reason": "unknown_server_key"}
	var own = sec.get("own")
	if typeof(own) != TYPE_ARRAY or own.size() > Protocol.MAX_PLAYER_CHARACTERS:
		return {"ok": false, "reason": "bad_own"}
	var own_set := {}
	for n in own:
		if typeof(n) != TYPE_STRING or not nodes.has(String(n)) or own_set.has(String(n)):
			return {"ok": false, "reason": "bad_own"}
		own_set[String(n)] = true
	var held = sec.get("held")
	if typeof(held) != TYPE_ARRAY or held.size() > MAX_HELD:
		return {"ok": false, "reason": "bad_held"}
	var hashes := {}
	var sims := {}
	for e in held:
		if typeof(e) != TYPE_DICTIONARY or e.size() != 5:
			return {"ok": false, "reason": "bad_held"}
		if not _valid_hash(e.get("hash")) or hashes.has(String(e["hash"])):
			return {"ok": false, "reason": "bad_held_hash"}
		if typeof(e.get("sim")) != TYPE_STRING or not nodes.has(String(e["sim"])) or sims.has(String(e["sim"])):
			return {"ok": false, "reason": "bad_held_sim"}
		# Jméno musí být už serverem sanitizované (žádné řídicí/bidi znaky, délka).
		if typeof(e.get("name")) != TYPE_STRING or Protocol.sanitize_name(e["name"]) != String(e["name"]):
			return {"ok": false, "reason": "bad_held_name"}
		if typeof(e.get("own")) != TYPE_BOOL or bool(e["own"]) != own_set.has(String(e["sim"])):
			return {"ok": false, "reason": "bad_held_own"}
		var rem = e.get("remaining")
		if typeof(rem) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(rem)) or float(rem) <= 0.0 or float(rem) > MAX_REMAINING:
			return {"ok": false, "reason": "bad_held_remaining"}
		hashes[String(e["hash"])] = true
		sims[String(e["sim"])] = true
	var host_sim = sec.get("host_sim")
	if typeof(host_sim) != TYPE_STRING:
		return {"ok": false, "reason": "bad_host_sim"}
	if String(host_sim) != "" and (not own_set.has(String(host_sim)) or sims.has(String(host_sim))):
		return {"ok": false, "reason": "bad_host_sim"}
	return {"ok": true}


## Obnoví uložený svět do PRÁZDNÉHO serverového světa (před prvním klientem). Nejdřív se ověří
## celý snímek (postavy, stav, parcela, serverová sekce), teprve potom se spawnuje.
## Vlastní postavy bez držení (a mimo hostitele) se do snímku vůbec nedostanou.
static func restore(world: Node, data: Variant) -> Dictionary:
	if world == null or world.net == null or not world.net.is_networked() or not world.net.is_authority():
		return {"ok": false, "reason": "server_only"}
	if not world.sims.is_empty():
		return {"ok": false, "reason": "server_world_not_empty"}
	for pid in world.net.players:
		if int(pid) != 1:
			return {"ok": false, "reason": "players_connected"}
	if not world.net.pending.is_empty():
		return {"ok": false, "reason": "players_connected"}
	var base_check: Dictionary = SaveGame.validate_data(data, world)
	if not bool(base_check["ok"]):
		return base_check
	var sec_check := validate_server_section(data)
	if not bool(sec_check["ok"]):
		return sec_check
	var sec: Dictionary = data["server"]
	var host_sim := String(sec["host_sim"])
	var can_hold: bool = world.net.reconnect_grace_seconds > 0.0
	# Kdo se může vrátit: držení (jen se zapnutou lhůtou) + hostitel ke své postavě.
	var returning := {}
	if can_hold:
		for e in sec["held"]:
			returning[String(e["sim"])] = true
	var host_returns: bool = world.net.mode == world.net.Mode.HOST and host_sim != ""
	if host_returns:
		returning[host_sim] = true
	var dropped: Array = []
	for n in sec["own"]:
		if not returning.has(String(n)):
			dropped.append(String(n))
	var restored_data: Dictionary = data if dropped.is_empty() else _without_sims(data, dropped)
	if restored_data.is_empty():
		return {"ok": false, "reason": "roster_size"}
	var applied: Dictionary = SaveGame.apply(world, restored_data, true)
	if not bool(applied.get("ok", false)):
		return applied
	for n in sec["own"]:
		var s = world.find_sim(String(n))
		if s != null:
			s.set_meta("player_character", true)
			if world._character_records.has(String(n)):
				s.set_meta("character_uid", String(world._character_records[String(n)].uid))
	var held_n: int = world.net.restore_held(sec["held"]) if can_hold else 0
	return {"ok": true, "restored": world.sims.size(), "held": held_n, "dropped": dropped.size(),
		"host_sim": host_sim if host_returns and world.find_sim(host_sim) != null else "",
		"day": applied.get("day", 0)}


## Kopie snímku bez vybraných postav: zmizí i odkazy na ně (cíle, partneři, rezervace,
## fronty příkazů), ať zbytek projde stejnou striktní validací jako běžný save.
static func _without_sims(data: Dictionary, names: Array) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var kept: Array = []
	for item in out["sims"]:
		if not names.has(String(item["node"])):
			kept.append(item)
	if kept.is_empty():
		return {}
	for item in kept:
		var st: Dictionary = item["state"]
		var lost := false
		for key in ["target", "social_partner"]:
			var ref = st.get(key, {})
			if typeof(ref) == TYPE_DICTIONARY and names.has(String(ref.get("sim", ""))):
				st[key] = {}
				lost = true
		if lost and int(st.get("state", 0)) != 0:
			# Rozdělaná akce s postavou, která se neobnoví, končí (postava si vybere novou).
			st["state"] = 0
			st["action"] = {}
		var queue: Array = []
		for cmd in st.get("player_queue", []):
			var tgt = cmd.get("target", {}) if typeof(cmd) == TYPE_DICTIONARY else {}
			if typeof(tgt) == TYPE_DICTIONARY and names.has(String(tgt.get("sim", ""))):
				continue
			queue.append(cmd)
		st["player_queue"] = queue
	out["sims"] = kept
	for obj in out["objects"]:
		var users: Array = []
		for u in obj["users"]:
			if not names.has(String(u)):
				users.append(u)
		obj["users"] = users
	return out


## Uloží snímek (atomicky, s .bak). Validuje i serverovou sekci.
func save(data: Dictionary) -> Dictionary:
	var check := validate_server_section(data)
	if not bool(check["ok"]):
		return check
	return store.save_slot(SLOT, data)


## Načte snímek: primární soubor, jinak .bak. Každý kandidát musí projít validací GameSave
## (SHA-256, formát, postavy, stav) I serverové sekce – jinak se zkusí záloha.
func load_data() -> Dictionary:
	var first := ""
	for pair in [["primary", ""], ["backup", ".bak"]]:
		var r: Dictionary = store._read_file(store._path(SLOT, pair[1]))
		if bool(r.get("ok", false)):
			var check := validate_server_section(r["data"])
			if bool(check["ok"]):
				r["source"] = pair[0]
				return r
			r = check
		if first == "":
			first = String(r.get("reason", "missing"))
	return {"ok": false, "reason": first}


func path() -> String:
	return store._path(SLOT)
