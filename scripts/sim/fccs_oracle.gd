extends RefCounted
## EXPERIMENT: FCCS jako volitelný MODULÁTOR výsledku běžného rozhovoru.
## Zapíná se jen v headless testu přepínačem `--fccs` (main.gd). Bez něj hra rozhoduje
## vlastní pravděpodobností (SimAgent.talk_success_chance) – deterministicky, bez sítě.
##
## Iniciátor řekne větu podle svého stavu (vlídná / neutrální / napjatá / konkrétní stížnost
## z domácnosti), partner ji vnímá přes FCCS. Výsledek je směs
##   p = W_GAME · p_hry + W_FCCS · σ(K · skóre FCCS).
## Nálada, de-eskalace, třenice, společné chvíle, náhodné události a vyvážení vztahů jsou od
## běhu 15 součástí HRY (scripts/sim/household_dynamics.gd + SimAgent) – tady se neduplikují.
## Samotest: FCCS musí na nepřátelskou větu reagovat záporně.
## HTTP je blokující (HTTPClient + poll), protože simulace běží synchronně. Nedeterministické
## (externí služba) – proto jen experiment, nikdy v multiplayeru ani v testech hry.

const Grammar := preload("res://scripts/core/grammar_cs.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

const W_GAME := 0.6
const W_FCCS := 0.4
const K := 6.0
const HOSTS := [
	{"host": "127.0.0.1", "port": 7860, "tls": false},
	{"host": "peiti-godot-mcp.hf.space", "port": 443, "tls": true},
]
const NEGATIVE_BEHAVIORS := ["flee", "attack", "refuse", "argue", "defend", "hostile", "threaten", "warn", "avoid", "ignore", "reject", "scold", "leave"]

var _host := {}
var _client: HTTPClient = null
var run_tag := ""
var ok := false
var self_test := {}
var stats := {"calls": 0, "fail": 0, "pos": 0, "neg": 0, "behaviors": {}, "ms": 0,
	"tones": {}, "neg_by_tone": {}, "p_game": 0.0, "p_fccs": 0.0, "p_mix": 0.0}
var samples: Array = []
var _last_aff := {}

const OPENERS := {
	"warm": [
		"Ahoj, jak se máš? Nedáme si spolu kafe?",
		"Hele, to jídlo včera bylo fakt dobrý, díky.",
		"Jak ti dneska bylo? Chceš to se mnou probrat?",
		"Mám radost, že tě vidím. Co je u tebe nového?",
	],
	"neutral": [
		"Čau. Co děláš?",
		"Viděl(a) jsi včera ten seriál?",
		"Je ještě něco v lednici, nebo musíme nakoupit?",
		"Dneska je venku hnusně, co?",
	],
	"tense": [
		"Nech mě bejt, mám toho dneska plný zuby.",
		"Můžeš mi vysvětlit, proč jsi na mě včera tak vyjel(a)?",
		"Pořád čekám, že se omluvíš. Ale ty se na to vykašleš, že jo?",
		"Jsem unaven{y} a ty mi tu furt něco chceš. Fakt ne.",
	],
}


func init(sims: Array) -> bool:
	run_tag = str(Time.get_unix_time_from_system()).replace(".", "").substr(4, 8)
	for h in HOSTS:
		_host = h
		_client = null
		if _post("/brain/npc", _npc_payload(sims[0])) != null:
			ok = true
			break
	if not ok:
		push_warning("FCCS oracle: brain API nedostupné – test poběží bez FCCS")
		return false
	for i in range(1, sims.size()):
		_post("/brain/npc", _npc_payload(sims[i]))
	_run_self_test()
	print("FCCS oracle: %s, NPC: %s | váhy hra %.1f / FCCS %.1f | samotest: %s" % [
		_host["host"], ", ".join(sims.map(func(s): return _id(s))), W_GAME, W_FCCS, self_test.get("verdict", "?")])
	return true


func _npc_payload(sim) -> Dictionary:
	return {"npc_id": _id(sim), "name": sim.first_name(), "role": "spolubydlící",
		"traits": _traits(sim), "backstory": "Bydlí ve sdíleném domě v Lipové ulici. Povaha: %s." % Traits.labels(sim.trait_ids)}


## Samotest: stejné NPC dostane vlídnou a nepřátelskou větu; nepřátelská musí vyjít hůř a záporně.
func _run_self_test() -> void:
	var tid := "ls_%s_selftest" % run_tag
	_post("/brain/npc", {"npc_id": tid, "name": "Test", "role": "spolubydlící", "traits": {"friendliness": 0.5, "bravery": 0.5, "curiosity": 0.5}})
	var good = _post("/brain/perceive", {"npc_id": tid, "text": OPENERS["warm"][0], "speaker": "A"})
	var bad = _post("/brain/perceive", {"npc_id": tid, "text": "Ty seš fakt k ničemu, zase jsi nechal nádobí ve dřezu, ty líná kreatura!", "speaker": "B"})
	if good == null or bad == null:
		self_test = {"verdict": "nelze ověřit"}
		return
	var sg := _score(good, 0.0)
	var sb := _score(bad, 0.0)
	self_test = {"warm_score": sg, "hostile_score": sb, "warm_behavior": good.get("behavior", ""), "hostile_behavior": bad.get("behavior", ""),
		"verdict": "OK" if (sb < 0.0 and sb < sg) else "SELHAL (nepřátelská věta nevyšla záporně)"}


func _id(sim) -> String:
	return "ls_%s_%s" % [run_tag, String(sim.first_name()).to_lower()]


## Osobnost FCCS (0–1) z herních rysů.
func _traits(sim) -> Dictionary:
	var f := 0.55
	var b := 0.5
	var c := 0.5
	var t: Array = sim.trait_ids
	if t.has("spolecensky"): f += 0.3
	if t.has("brucoun"): f -= 0.3
	if t.has("vznetlivy"): f -= 0.15; b += 0.2
	if t.has("zarlivy"): f -= 0.1
	if t.has("cynik"): f -= 0.2
	if t.has("uzkostlivy"): b -= 0.25
	if t.has("aktivni"): b += 0.15
	if t.has("knihomol"): c += 0.3
	if t.has("gurman"): c += 0.1
	if t.has("lenoch"): c -= 0.15
	return {"friendliness": clampf(f, 0.05, 0.95), "bravery": clampf(b, 0.05, 0.95), "curiosity": clampf(c, 0.05, 0.95)}


## Volá SimAgent při běžném rozhovoru. complaint = téma stížnosti z domácnosti ("" = žádná).
## Vrací {} = nerozhodnuto (hra použije vlastní kostku).
func decide(a, b, p_game: float, complaint := "") -> Dictionary:
	if not ok:
		return {}
	var tone := "neutral"
	var text := ""
	if complaint != "":
		tone = "complaint:" + complaint
		var lines: Array = ActionLibrary.LINES.get("complaint_" + complaint, [])
		text = String(lines[0]) if not lines.is_empty() else "Štve mě to."
	else:
		var grudge: float = float(a.ledger.grudge(b.sim_name))
		var rel: float = float(a.relationships.get(b.sim_name, 0.0))
		var drained: bool = float(a.needs.values["energy"]) < 25.0 or float(a.needs.values["hunger"]) < 25.0
		if a.mental.stress > 60.0 or a.mood.emotion == "nastvany" or grudge > 15.0 or rel < -35.0 or (drained and a.rng.randf() < 0.5):
			tone = "tense"
		elif a.mood.value > 15.0 and rel > -10.0:
			tone = "warm"
		var pool: Array = OPENERS[tone]
		text = String(pool[a.rng.randi() % pool.size()])
	text = Grammar.form(text, a.grammar)
	var t0 := Time.get_ticks_msec()
	var r = _post("/brain/perceive", {"npc_id": _id(b), "text": text, "speaker": a.first_name()})
	stats["ms"] += Time.get_ticks_msec() - t0
	if r == null or typeof(r) != TYPE_DICTIONARY:
		stats["fail"] += 1
		return {}
	var aff := float(r.get("relationship", {}).get("affinity", 0.0))
	var prev_key := "%s>%s" % [_id(b), a.first_name()]
	var d_aff := aff - float(_last_aff.get(prev_key, 0.0))
	_last_aff[prev_key] = aff
	var behavior := String(r.get("behavior", ""))
	var score := _score(r, d_aff)
	if NEGATIVE_BEHAVIORS.has(behavior):
		score = minf(score, -0.3)
	var p_fccs := 1.0 / (1.0 + exp(-K * score))
	var p := clampf(W_GAME * p_game + W_FCCS * p_fccs, 0.05, 0.95)
	var success: bool = a.rng.randf() < p
	stats["pos" if success else "neg"] += 1
	stats["p_game"] += p_game
	stats["p_fccs"] += p_fccs
	stats["p_mix"] += p
	var tkey := tone.split(":")[0]
	stats["tones"][tkey] = int(stats["tones"].get(tkey, 0)) + 1
	if not success:
		stats["neg_by_tone"][tkey] = int(stats["neg_by_tone"].get(tkey, 0)) + 1
	stats["behaviors"][behavior] = int(stats["behaviors"].get(behavior, 0)) + 1
	if (tkey != "warm" and samples.size() < 16) or samples.size() < 4:
		samples.append("%s → %s [%s] „%s“ ⇒ %s (skóre %+.2f) | p hra %.0f %% · FCCS %.0f %% → %.0f %% ⇒ %s" % [
			a.first_name(), b.first_name(), tone, text, behavior, score, p_game * 100.0, p_fccs * 100.0, p * 100.0,
			"pohoda" if success else "HÁDKA"])
	return {"success": success, "say": String(r.get("say", "")), "behavior": behavior, "tone": tone}


static func _score(r: Dictionary, d_aff: float) -> float:
	var mood_v := float(r.get("mood", {}).get("valence", 0.0))
	var emo_v := float(r.get("fccs", {}).get("emotion", {}).get("valence", 0.0))
	var hostile := float(r.get("appraisal", {}).get("hostile", 0.0))
	return 0.5 * mood_v + 0.5 * emo_v + 2.0 * d_aff - hostile


func report() -> String:
	var n := maxf(1.0, float(stats["pos"] + stats["neg"]))
	var lines := PackedStringArray()
	lines.append("--- FCCS modulátor (%.0f/%.0f) ---" % [W_GAME * 100, W_FCCS * 100])
	lines.append("  samotest: %s (vlídná %+.2f %s, nepřátelská %+.2f %s)" % [self_test.get("verdict", "?"),
		float(self_test.get("warm_score", 0.0)), self_test.get("warm_behavior", ""), float(self_test.get("hostile_score", 0.0)), self_test.get("hostile_behavior", "")])
	lines.append("  rozhovory: dobře %d / hádky %d (%.0f %%), dotazů %d, selhalo %d, %.0f ms/dotaz" % [
		stats["pos"], stats["neg"], 100.0 * stats["neg"] / n, stats["calls"], stats["fail"], float(stats["ms"]) / n])
	lines.append("  průměrná šance na dobrý rozhovor: hra %.0f %%, FCCS %.0f %%, výsledná %.0f %%" % [
		100.0 * stats["p_game"] / n, 100.0 * stats["p_fccs"] / n, 100.0 * stats["p_mix"] / n])
	lines.append("  tóny oslovení: %s | hádky podle tónu: %s" % [JSON.stringify(stats["tones"]), JSON.stringify(stats["neg_by_tone"])])
	lines.append("  chování FCCS: %s" % JSON.stringify(stats["behaviors"]))
	lines.append("  ukázky:")
	for s in samples:
		lines.append("    " + s)
	return "\n".join(lines)


# ---------------------------------------------------------------- HTTP (blokující)

func _connect() -> bool:
	_client = HTTPClient.new()
	var tls = TLSOptions.client() if _host["tls"] else null
	if _client.connect_to_host(_host["host"], _host["port"], tls) != OK:
		return false
	var t := Time.get_ticks_msec()
	while _client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		_client.poll()
		OS.delay_msec(2)
		if Time.get_ticks_msec() - t > 8000:
			return false
	return _client.get_status() == HTTPClient.STATUS_CONNECTED


func _post(path: String, payload: Dictionary) -> Variant:
	stats["calls"] += 1
	for attempt in 2:
		if _client == null or _client.get_status() != HTTPClient.STATUS_CONNECTED:
			if not _connect():
				_client = null
				continue
		var err := _client.request(HTTPClient.METHOD_POST, path, ["Content-Type: application/json", "Connection: keep-alive"], JSON.stringify(payload))
		if err != OK:
			_client = null
			continue
		var t := Time.get_ticks_msec()
		while _client.get_status() == HTTPClient.STATUS_REQUESTING:
			_client.poll()
			OS.delay_msec(1)
			if Time.get_ticks_msec() - t > 20000:
				break
		if not _client.has_response():
			_client = null
			continue
		var code := _client.get_response_code()
		var buf := PackedByteArray()
		while _client.get_status() == HTTPClient.STATUS_BODY:
			_client.poll()
			var chunk := _client.read_response_body_chunk()
			if chunk.size() == 0:
				OS.delay_msec(1)
			else:
				buf.append_array(chunk)
		if code != 200:
			return null
		return JSON.parse_string(buf.get_string_from_utf8())
	return null
