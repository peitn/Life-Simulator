extends RefCounted
## EXPERIMENT v2: FCCS jako MODULÁTOR sociálních interakcí + domácí třenice.
## Zapíná se jen v headless testu přepínačem `--fccs` (main.gd). Bez něj hra
## rozhoduje vlastní pravděpodobností (sim_agent._start_social) jako dřív.
##
## 1) Rozhovor: iniciátor řekne větu podle svého stavu (vlídná / neutrální /
##    napjatá / konkrétní stížnost), partner ji vnímá přes FCCS. Výsledek je směs
##    p = W_GAME · p_hry + W_FCCS · p_fccs, kde p_fccs = σ(K · skóre FCCS).
## 2) Třenice v domácnosti nezávislé na rozhovoru (hluk v noci, obsazená koupelna,
##    nádobí po vaření). Přidají stres, drobnou křivdu, moodlet a téma stížnosti,
##    které se objeví v příštím oslovení – konflikt tak může vzniknout „z ničeho“
##    jako v životě, ale FCCS rozhodne, jestli se z něj stane hádka.
## 3) Samotest: FCCS musí na nepřátelskou větu reagovat záporně.
## HTTP je blokující (HTTPClient + poll), protože simulace běží synchronně.

const Grammar := preload("res://scripts/core/grammar_cs.gd")
const Traits := preload("res://scripts/sim/traits.gd")

const W_GAME := 0.6
const W_FCCS := 0.4
## Kolik procentních bodů může nálada (průměr obou) přidat/ubrat šanci na dobrý rozhovor.
const MOOD_WEIGHT := 0.2
## Max. šance, že posluchač v dobré náladě hádku utne smířlivou odpovědí.
const DEESCALATE := 0.35
const K := 6.0
const HOSTS := [
	{"host": "127.0.0.1", "port": 7860, "tls": false},
	{"host": "peiti-godot-mcp.hf.space", "port": 443, "tls": true},
]
const NEGATIVE_BEHAVIORS := ["flee", "attack", "refuse", "argue", "defend", "hostile", "threaten", "warn", "avoid", "ignore", "reject", "scold", "leave"]
const SLEEP_IDS := ["sleep", "sleep_sofa", "nap"]
const NOISY_IDS := ["watch_tv", "workout", "cook"]
const COMPLAINT_TTL := 360.0
## Odstup mezi třenicemi stejného druhu u stejné dvojice (herní minuty).
const FRICTION_COOLDOWN := {"noise": 360.0, "bathroom": 360.0, "dishes": 720.0}
var _last_friction := {}
## Vyvážení vztahů (čte SimAgent._social_outcome): hádka ×0,6, opakovaný hovor ×0,7 místo ×0,35.
var balance := true
const SHARED_COOLDOWN := 240.0
const DRIFT_NEG := 0.015   # za 10 min směrem k 0, když nevisí křivda (~2,2 bodu/den)
const DRIFT_POS := 0.004
var _last_shared := {}
## Náhodné události mimo domácnost – mění náladu (a negativní i stres). Hazard za 10 min.
const EVENT_HAZARD := 0.012  # ≈ 1,7 události na postavu za den
const EVENTS_GOOD := [
	["Pochvala od šéfa", 12.0], ["Kamarád poslal vtipnou zprávu", 8.0], ["Venku konečně svítí", 7.0],
	["Vyspal(a) jsem se do růžova", 10.0], ["Vrátili mi přeplatek", 11.0], ["Někdo mi pochválil oblečení", 8.0],
]
const EVENTS_BAD := [
	["Přišel účet za elektřinu", -12.0], ["Nepříjemný telefonát z práce", -11.0], ["Bolí mě hlava", -8.0],
	["Leje a jsem promočen(á)", -7.0], ["Ztratil(a) jsem klíče", -9.0], ["Ex mi napsal(a) blbou zprávu", -13.0],
]
var _mood_buckets := {"dobrá": [0, 0], "střední": [0, 0], "špatná": [0, 0]}  # [rozhovory, hádky]


var _host := {}
var _client: HTTPClient = null
var run_tag := ""
var ok := false
var self_test := {}
var stats := {"calls": 0, "fail": 0, "pos": 0, "neg": 0, "behaviors": {}, "ms": 0,
	"tones": {}, "friction": {}, "shared": {}, "events": {}, "neg_by_tone": {}, "p_game": 0.0, "p_fccs": 0.0, "p_mix": 0.0}
var samples: Array = []
var _last_aff := {}
var _prev_action := {}
var _complaints := {}  # "A>B" -> {"topic": String, "t": float}

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
		"Jsem unavený(á) a ty mi tu furt něco chceš. Fakt ne.",
	],
}
const COMPLAINTS := {
	"noise": "Můžeš se ztišit? Já se tu snažím spát, sakra.",
	"bathroom": "Jak dlouho tam ještě budeš? Taky se potřebuju umýt!",
	"dishes": "Kdo zase nechal špinavý nádobí na lince? Nejsem tvoje služka.",
}
const COMPLAINT_LABEL := {"noise": "hluk v noci", "bathroom": "obsazená koupelna", "dishes": "nádobí po vaření"}


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
	print("FCCS oracle v2: %s, NPC: %s | váhy hra %.1f / FCCS %.1f | samotest: %s" % [
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


func _irritability(sim) -> float:
	var m := 1.0
	var t: Array = sim.trait_ids
	for k in ["pedant", "brucoun", "vznetlivy", "uzkostlivy"]:
		if t.has(k):
			m *= 1.4
	if t.has("lenoch") or t.has("optimista"):
		m *= 0.7
	return m


# ---------------------------------------------------------------- třenice (každých 10 herních minut)

func tick(sims: Array, hour: int, now: float) -> void:
	if not ok:
		return
	for o in sims:
		var oid := String(o.current_action.get("id", ""))
		var prev := String(_prev_action.get(o.sim_name, ""))
		_prev_action[o.sim_name] = oid
		for s in sims:
			if s == o:
				continue
			var sid := String(s.current_action.get("id", ""))
			var near: bool = s.global_position.distance_to(o.global_position) < 9.0
			var irr := _irritability(s)
			# Hluk v noci: někdo spí a druhý poblíž dělá rámus.
			if (hour >= 22 or hour < 6) and SLEEP_IDS.has(sid) and NOISY_IDS.has(oid) and near:
				if _can(s, o, "noise", now) and s.rng.randf() < 0.25 * irr:
					_friction(s, o, "noise", now)
			# Koupelna: druhý se sprchuje a já se potřebuju umýt.
			elif oid == "shower" and not SLEEP_IDS.has(sid) and float(s.needs.values["hygiene"]) < 40.0:
				if _can(s, o, "bathroom", now) and s.rng.randf() < 0.2 * irr:
					_friction(s, o, "bathroom", now)
			# Nádobí: druhý právě dovařil a nechal to být.
			elif prev == "cook" and oid != "cook" and not SLEEP_IDS.has(sid) and near:
				if _can(s, o, "dishes", now) and s.rng.randf() < 0.12 * irr:
					_friction(s, o, "dishes", now)
	if balance:
		_repair(sims, now)
	for x in sims:
		if x.rng.randf() < EVENT_HAZARD:
			_life_event(x, now)


## Společné chvíle (film na gauči, vaření spolu) a pomalý návrat vztahu k neutrálu.
func _repair(sims: Array, now: float) -> void:
	for i in sims.size():
		for j in range(i + 1, sims.size()):
			var a = sims[i]
			var b = sims[j]
			var ia := String(a.current_action.get("id", ""))
			var ib := String(b.current_action.get("id", ""))
			var close: bool = a.global_position.distance_to(b.global_position) < 4.0
			var together := ""
			if close and ["watch_tv", "relax"].has(ia) and ["watch_tv", "relax"].has(ib):
				together = "film"
			elif close and ia == "cook" and ib == "cook":
				together = "vaření"
			var key := "%s+%s" % [a.sim_name, b.sim_name]
			if together != "" and now - float(_last_shared.get(key, -1.0e9)) >= SHARED_COOLDOWN:
				_last_shared[key] = now
				for pr in [[a, b], [b, a]]:
					var x = pr[0]
					var y = pr[1]
					var r := float(x.relationships.get(y.sim_name, 0.0))
					x.relationships[y.sim_name] = clampf(r + 2.0 * x.ledger.warmth_mult(y.sim_name), -100.0, 100.0)
					x.ledger.soften(y.sim_name, 2.0)
					x.mood.add_moodlet("spolu_%s_%s" % [together, y.name], "Chvíle spolu: %s (%s)" % [y.first_name(), together], "stastny", 5.0, 120.0)
				stats["shared"][together] = int(stats["shared"].get(together, 0)) + 1
	for x in sims:
		for y in sims:
			if x == y:
				continue
			var r := float(x.relationships.get(y.sim_name, 0.0))
			if r < 0.0 and float(x.ledger.grudge(y.sim_name)) < 5.0:
				x.relationships[y.sim_name] = minf(0.0, r + DRIFT_NEG)
			elif r > 0.0:
				x.relationships[y.sim_name] = maxf(0.0, r - DRIFT_POS)


func _life_event(x, now: float) -> void:
	var good: bool = x.rng.randf() < 0.5
	var pool: Array = EVENTS_GOOD if good else EVENTS_BAD
	var e: Array = pool[x.rng.randi() % pool.size()]
	var label: String = String(e[0]).replace("(a)", Grammar.past(x.grammar)).replace("(á)", "" if x.grammar == "m" else "á")
	var strength: float = float(e[1]) * x.rng.randf_range(0.7, 1.3)
	x.mood.add_moodlet("udalost_%d" % int(now), label, "stastny" if good else "smutny", strength, x.rng.randf_range(240.0, 480.0))
	if not good:
		x.mental.on_stressor("life", absf(strength) * 0.2, x.mental_cfg())
	stats["events"]["dobré" if good else "špatné"] = int(stats["events"].get("dobré" if good else "špatné", 0)) + 1

func _friction(s, o, topic: String, now: float) -> void:
	var cfg: Dictionary = s.mental_cfg()
	s.mental.on_stressor("friction", 3.0 * Traits.mult_param(s.trait_ids, "stress_gain"), cfg)
	s.ledger.on_hurt_by(o.sim_name, 2.0, now)
	_last_friction["%s>%s>%s" % [s.sim_name, o.sim_name, topic]] = now
	s.mood.add_moodlet("trenice_%s_%s" % [topic, o.name], "Štve mě %s (%s)" % [o.first_name(), COMPLAINT_LABEL[topic]], "nastvany", -6.0, 120.0)
	_complaints["%s>%s" % [s.sim_name, o.sim_name]] = {"topic": topic, "t": now}
	stats["friction"][topic] = int(stats["friction"].get(topic, 0)) + 1


func _can(s, o, topic: String, now: float) -> bool:
	return now - float(_last_friction.get("%s>%s>%s" % [s.sim_name, o.sim_name, topic], -1.0e9)) >= float(FRICTION_COOLDOWN[topic])


# ---------------------------------------------------------------- rozhovor

## Volá SimAgent při pokusu o rozhovor. Vrací {} = nerozhodnuto (hra použije vlastní kostku).
func decide(a, b, p_game: float) -> Dictionary:
	if not ok:
		return {}
	var now: float = float(a._clock.total_minutes)
	var key := "%s>%s" % [a.sim_name, b.sim_name]
	var tone := "neutral"
	var text := ""
	var c = _complaints.get(key, null)
	if c != null and now - float(c["t"]) < COMPLAINT_TTL:
		tone = "complaint:" + String(c["topic"])
		text = COMPLAINTS[c["topic"]]
		_complaints.erase(key)
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
	text = text.replace("(a)", Grammar.past(a.grammar)).replace("ý(á)", Grammar.adj(a.grammar))
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
	# Nálada obou: v dobré náladě člověk víc snese, ve špatné vybuchne dřív.
	var avg_mood: float = (float(a.mood.value) + float(b.mood.value)) * 0.5
	var mood_shift: float = clampf(avg_mood / 100.0, -1.0, 1.0) * MOOD_WEIGHT
	var p := clampf(W_GAME * p_game + W_FCCS * p_fccs + mood_shift, 0.05, 0.95)
	var bucket: String = "dobrá" if avg_mood > 30.0 else ("špatná" if avg_mood < 5.0 else "střední")
	var success: bool = a.rng.randf() < p
	# De-eskalace: posluchač v dobré náladě občas ostrý tón přejde a odpoví smířlivě.
	if not success and float(b.mood.value) > 20.0 and a.rng.randf() < DEESCALATE * clampf((float(b.mood.value) - 20.0) / 30.0, 0.0, 1.0):
		success = true
		stats["deescalated"] = int(stats.get("deescalated", 0)) + 1
	_mood_buckets[bucket][0] += 1
	if not success:
		_mood_buckets[bucket][1] += 1
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
	lines.append("--- FCCS v4 (modulátor %.0f/%.0f + třenice + vyvážení + nálada) ---" % [W_GAME * 100, W_FCCS * 100])
	lines.append("  samotest: %s (vlídná %+.2f %s, nepřátelská %+.2f %s)" % [self_test.get("verdict", "?"),
		float(self_test.get("warm_score", 0.0)), self_test.get("warm_behavior", ""), float(self_test.get("hostile_score", 0.0)), self_test.get("hostile_behavior", "")])
	lines.append("  rozhovory: dobře %d / hádky %d (%.0f %%), dotazů %d, selhalo %d, %.0f ms/dotaz" % [
		stats["pos"], stats["neg"], 100.0 * stats["neg"] / n, stats["calls"], stats["fail"], float(stats["ms"]) / n])
	lines.append("  průměrná šance na dobrý rozhovor: hra %.0f %%, FCCS %.0f %%, výsledná %.0f %%" % [
		100.0 * stats["p_game"] / n, 100.0 * stats["p_fccs"] / n, 100.0 * stats["p_mix"] / n])
	lines.append("  tóny oslovení: %s | hádky podle tónu: %s" % [JSON.stringify(stats["tones"]), JSON.stringify(stats["neg_by_tone"])])
	lines.append("  třenice: %s | společné chvíle: %s" % [JSON.stringify(stats["friction"]), JSON.stringify(stats["shared"])])
	lines.append("  chování FCCS: %s" % JSON.stringify(stats["behaviors"]))
	lines.append("  náhodné události: %s" % JSON.stringify(stats["events"]))
	lines.append("  hádek utnutých dobrou náladou posluchače: %d" % int(stats.get("deescalated", 0)))
	var mb := PackedStringArray()
	for k in ["dobrá", "střední", "špatná"]:
		var v: Array = _mood_buckets[k]
		mb.append("%s nálada: %d rozhovorů, hádky %.0f %%" % [k, v[0], 100.0 * v[1] / maxf(1.0, float(v[0]))])
	lines.append("  hádky podle nálady: " + " | ".join(mb))
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
