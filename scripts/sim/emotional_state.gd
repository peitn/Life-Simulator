extends RefCounted
## Private simultaneous emotions (0..100). Separate from Mood, physiology,
## depression, stable dispositions and diagnostic labels. No SH actions.
## All computation uses game-time minutes and is deterministic (no RNG).
const KEYS := ["sadness", "anger", "fear", "uncertainty", "joy", "loneliness",
	"shame", "guilt", "hope", "safety", "frustration", "disappointment",
	"jealousy", "envy", "calm", "excitement", "emotional_numbness",
	"overload", "compassion"]
const LABELS := {
	"sadness": "Smutek", "anger": "Vztek", "fear": "Strach",
	"uncertainty": "Nejistota", "joy": "Radost", "loneliness": "Osamělost",
	"shame": "Stud", "guilt": "Vina", "hope": "Naděje",
	"safety": "Pocit bezpečí", "frustration": "Frustrace",
	"disappointment": "Zklamání", "jealousy": "Žárlivost",
	"envy": "Závist", "calm": "Klid", "excitement": "Nadšení",
	"emotional_numbness": "Citová otupělost",
	"overload": "Emoční zahlcení", "compassion": "Soucit"}
const TAU := {
	"sadness": 500.0, "anger": 140.0, "fear": 120.0,
	"uncertainty": 320.0, "joy": 210.0, "loneliness": 650.0,
	"shame": 440.0, "guilt": 680.0, "hope": 720.0,
	"safety": 530.0, "frustration": 160.0,
	"disappointment": 430.0, "jealousy": 360.0, "envy": 360.0,
	"calm": 250.0, "excitement": 80.0,
	"emotional_numbness": 900.0, "overload": 160.0,
	"compassion": 360.0}
const DEFAULTS := {"hope": 22.0, "safety": 35.0, "calm": 18.0,
	"joy": 8.0}
## Mixed events can raise incompatible feelings at once. A positive event never
## simply overwrites sadness. A perceived cue is explicitly NOT a real rejection.
const EVENTS := {
	"chat": {"joy": 10.0, "safety": 4.0, "hope": 3.0, "calm": 2.0},
	"shared": {"joy": 8.0, "safety": 8.0, "calm": 6.0, "loneliness": -7.0},
	"argue": {"anger": 16.0, "frustration": 13.0, "fear": 4.0,
		"sadness": 6.0, "safety": -10.0},
	"awkward": {"uncertainty": 9.0, "shame": 5.0, "frustration": 3.0},
	"misunderstanding": {"uncertainty": 14.0, "frustration": 9.0,
		"disappointment": 7.0},
	"insulted": {"anger": 20.0, "shame": 12.0, "sadness": 14.0, "safety": -14.0},
	"insulted_other": {"anger": 7.0, "guilt": 9.0},
	"dismissed": {"sadness": 14.0, "shame": 9.0, "uncertainty": 13.0,
		"loneliness": 12.0, "safety": -14.0},
	"confided": {"safety": 14.0, "hope": 12.0, "calm": 9.0,
		"loneliness": -10.0, "sadness": -6.0},
	"helped": {"safety": 18.0, "hope": 15.0, "calm": 12.0,
		"fear": -10.0, "uncertainty": -10.0},
	"rejection_perceived": {"uncertainty": 23.0, "fear": 11.0,
		"sadness": 10.0, "safety": -10.0},
	"rejection_real": {"sadness": 23.0, "fear": 11.0,
		"loneliness": 17.0, "hope": -12.0, "safety": -12.0},
	"apology_accepted": {"hope": 12.0, "safety": 9.0, "calm": 7.0,
		"anger": -8.0, "guilt": -7.0},
	"apology_partial": {"hope": 5.0, "uncertainty": 5.0, "anger": -3.0},
	"apology_rejected": {"sadness": 11.0, "disappointment": 12.0,
		"shame": 7.0, "uncertainty": 7.0},
	"friction": {"anger": 10.0, "frustration": 14.0},
	"envy": {"envy": 14.0, "uncertainty": 2.0},
	"jealousy": {"jealousy": 21.0, "fear": 9.0, "uncertainty": 12.0},
	"life_good": {"joy": 13.0, "hope": 9.0, "excitement": 9.0},
	"life_bad": {"sadness": 12.0, "disappointment": 13.0, "uncertainty": 6.0},
	"activity_good": {"joy": 8.0, "excitement": 5.0, "frustration": -4.0},
	"activity_bad": {"frustration": 9.0, "disappointment": 10.0},
	"comforted_other": {"compassion": 13.0, "hope": 4.0},
	"panic_start": {"fear": 17.0, "overload": 10.0},
	"panic_end": {"fear": -12.0, "calm": 7.0}
}
const DIRECTED := ["sadness", "anger", "fear", "uncertainty", "joy", "shame",
	"guilt", "safety", "disappointment", "jealousy", "compassion", "hope",
	"envy", "frustration"]
const MAX_PEOPLE := 32
var levels: Dictionary = {}
var directed: Dictionary = {}  # stable SimAgent node name -> {axis -> intensity}
var dispositions: Dictionary = {}
## Crying is a transient emotional expression, NOT an inner belief.
const CRY_START := 70.0
const CRY_STOP := 55.0
var crying := false

func _init() -> void:
	for k in KEYS:
		levels[k] = float(DEFAULTS.get(k, 0.0))


static func label(key: String) -> String:
	return String(LABELS.get(key, key))


func level(key: String) -> float:
	return float(levels.get(key, 0.0))


func towards(who: String, key: String) -> float:
	if typeof(directed.get(who)) != TYPE_DICTIONARY:
		return 0.0
	return float((directed[who] as Dictionary).get(key, 0.0))


func configure(d: Dictionary) -> void:
	for k in ["rejection_reactivity", "regulation_capacity", "reward_sensitivity",
			"threat_sensitivity", "social_threat", "predictability_need"]:
		var v: Variant = d.get(k)
		if typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)):
			dispositions[k] = clampf(float(v), 0.0, 1.0)


## Explicit impulses represent an event, NOT probabilities or clinical scores.
## A named target is allowed only if it is a stable and valid NPC node name.
func impulse(event_name: String, who: String = "", intensity: float = 1.0) -> void:
	if not EVENTS.has(event_name) or not is_finite(intensity) or intensity <= 0.0:
		return
	var scale := clampf(intensity, 0.0, 3.0)
	var rejection_weight := 0.7 + 0.6 * float(dispositions.get("rejection_reactivity", 0.5))
	var reward_weight := 0.7 + 0.6 * float(dispositions.get("reward_sensitivity", 0.5))
	if event_name in ["rejection_perceived", "rejection_real", "dismissed"]:
		scale *= rejection_weight
	elif event_name in ["chat", "shared", "life_good", "activity_good"]:
		scale *= reward_weight
	var effects: Dictionary = EVENTS[event_name]
	for k in KEYS:
		if effects.has(k):
			shift(k, float(effects[k]) * scale, who)


func shift(key: String, delta: float, who: String = "") -> void:
	if not KEYS.has(key) or not is_finite(delta):
		return
	var changed: float = clampf(level(key) + clampf(delta, -100.0, 100.0), 0.0, 100.0)
	levels[key] = changed
	if key == "sadness":
		_refresh_crying()
	if not DIRECTED.has(key) or who.is_empty() or who.length() > 64 			or who != who.validate_node_name():
		return
	if not directed.has(who):
		if directed.size() >= MAX_PEOPLE:
			return
		directed[who] = {}
	var d: Dictionary = directed[who]
	d[key] = clampf(float(d.get(key, 0.0)) + delta * 0.7, 0.0, 100.0)
	directed[who] = d


## Exponential decay avoids frame-rate dependence; the contextual targets are
## gentle read-only interpretations. No feedback into stress/depression and no
## scripted behavior, self-harm or diagnosis. Opposites NEVER cancel each other.
func tick(dm: float, context: Dictionary = {}) -> void:
	if not is_finite(dm) or dm <= 0.0:
		return
	var dt := minf(dm, 10080.0)
	var social: float = _safe01_100(context.get("social", 70.0), 70.0)
	var stress: float = _safe01_100(context.get("stress", 0.0), 0.0)
	var burden: float = _safe01(context.get("burden", 0.0), 0.0)
	var threat: float = _safe01(context.get("threat", 0.0), 0.0)
	var regulation: float = _safe01(context.get("regulation", 0.5), 0.5)
	var support: float = _safe01(context.get("support", 0.0), 0.0)
	var sleeping: bool = bool(context.get("sleeping", false))
	var desires_company: float = _safe01(context.get("social_drive", 0.5), 0.5)
	var base := DEFAULTS.duplicate()
	base["sadness"] = burden * 17.0
	base["fear"] = threat * 18.0
	base["loneliness"] = clampf((60.0 - social) * 0.45 * (0.5 + desires_company), 0.0, 28.0)
	base["hope"] = clampf(24.0 - burden * 10.0 + support * 12.0, 0.0, 40.0)
	base["safety"] = clampf(35.0 - threat * 16.0 + support * 16.0, 4.0, 60.0)
	base["emotional_numbness"] = burden * 29.0
	base["calm"] = clampf(18.0 + regulation * 8.0 - stress * 0.08, 4.0, 32.0)
	var mixed: float = (level("fear") + level("anger") + level("sadness") +
		level("uncertainty") + level("frustration")) / 5.0
	base["overload"] = clampf(maxf(0.0, mixed - 15.0) * 0.35 + stress * 0.08, 0.0, 45.0)
	for k in KEYS:
		var tau := float(TAU[k]) * (1.0 + (1.0 - regulation) * 0.55)
		if sleeping and k in ["anger", "fear", "frustration", "overload"]:
			tau *= 0.7
		var target: float = float(base.get(k, 0.0))
		var decay := exp(-dt / tau)
		levels[k] = clampf(target + (level(k) - target) * decay, 0.0, 100.0)
	_refresh_crying()
	# Person-directed feelings decay independently: retain them without
	# inferring their source was objectively right or wrong.
	for person in directed.keys():
		var d: Dictionary = directed[person]
		for k in d.keys():
			var v := float(d[k]) * exp(-dt / float(TAU.get(k, 360.0)))
			if v < 0.0001:
				d.erase(k)
			else:
				d[k] = v
		if d.is_empty():
			directed.erase(person)
		else:
			directed[person] = d


## Crying hysteresis prevents repeated toggling at the sadness boundary.
func _refresh_crying() -> void:
	if crying:
		if level("sadness") <= CRY_STOP:
			crying = false
	elif level("sadness") >= CRY_START:
		crying = true


static func _safe01(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return clampf(float(value), 0.0, 1.0)


static func _safe01_100(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return clampf(float(value), 0.0, 100.0)


## Small and bounded preference biases, never mandatory actions or bans.
func action_weight(action_id: String, tags: Array) -> float:
	var boost := 0.0
	if action_id == "confide":
		boost += (level("loneliness") + level("fear") + level("uncertainty")) * 0.0009
	elif action_id == "apologize":
		boost += level("guilt") * 0.0015
	elif tags.has("social"):
		boost += level("loneliness") * 0.00075
		boost -= level("shame") * 0.0005
	if tags.has("rest"):
		boost += (level("fear") + level("overload")) * 0.0005
	if tags.has("fun"):
		boost += level("joy") * 0.00035
	return clampf(1.0 + boost, 0.84, 1.16)


func top_emotions(count: int = 3) -> Array:
	var vals: Array = []
	for k in KEYS:
		vals.append({"key": k, "label": label(k), "value": level(k)})
	vals.sort_custom(func(a, b):
		if is_equal_approx(float(a["value"]), float(b["value"])):
			return String(a["key"]) < String(b["key"])
		return float(a["value"]) > float(b["value"]))
	return vals.slice(0, clampi(count, 0, KEYS.size()))


func top_people(limit: int = 6) -> Array:
	var entries: Array = []
	for who in directed:
		var d: Dictionary = directed[who]
		var highest_key := ""
		var strongest := 0.0
		for k in DIRECTED:
			var v: float = float(d.get(k, 0.0))
			if v > strongest:
				strongest = v
				highest_key = k
		if strongest >= 8.0:
			entries.append({"who": String(who), "emotion": highest_key,
				"label": label(highest_key), "value": strongest})
	entries.sort_custom(func(a, b):
		if is_equal_approx(float(a["value"]), float(b["value"])):
			return String(a["who"]) < String(b["who"])
		return float(a["value"]) > float(b["value"]))
	return entries.slice(0, clampi(limit, 0, MAX_PEOPLE))


func to_dict() -> Dictionary:
	return {"levels": levels.duplicate(true), "directed": directed.duplicate(true),
		"dispositions": dispositions.duplicate(true), "crying": crying}


## Save-game validator rejects malformed optional emotion snapshots before
## changing the world. Legacy saves omit the entire field.
static func validate_snapshot(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.size() > 4:
		return false
	if typeof(data.get("levels")) != TYPE_DICTIONARY or typeof(data.get("directed")) != TYPE_DICTIONARY:
		return false
	var l: Dictionary = data["levels"]
	## Accept prior 20-axis snapshots, but discard the retired emotional
	## defectiveness meter. The permanent belief lives in CharacterData.mind.
	if l.size() != KEYS.size() and not (l.size() == KEYS.size() + 1 and l.has("defectiveness")):
		return false
	for k in KEYS:
		if not l.has(k) or not _numeric_level(l[k]):
			return false
	for k in l:
		if not KEYS.has(String(k)) and String(k) != "defectiveness":
			return false
		if String(k) == "defectiveness" and not _numeric_level(l[k]):
			return false
	var people: Dictionary = data["directed"]
	if people.size() > MAX_PEOPLE:
		return false
	for who in people:
		if typeof(who) != TYPE_STRING or String(who).is_empty() or String(who).length() > 64 				or String(who) != String(who).validate_node_name() or typeof(people[who]) != TYPE_DICTIONARY:
			return false
		var d: Dictionary = people[who]
		if d.size() > DIRECTED.size():
			return false
		for k in d:
			if not DIRECTED.has(String(k)) or not _numeric_level(d[k]):
				return false
	var disp: Variant = data.get("dispositions", {})
	if typeof(disp) != TYPE_DICTIONARY or disp.size() > 6:
		return false
	for k in disp:
		if String(k) not in ["rejection_reactivity", "regulation_capacity", "reward_sensitivity",
				"threat_sensitivity", "social_threat", "predictability_need"]:
			return false
		if typeof(disp[k]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(disp[k])) 				or float(disp[k]) < 0.0 or float(disp[k]) > 1.0:
			return false
	if data.has("crying") and typeof(data["crying"]) != TYPE_BOOL:
		return false
	return true


static func _numeric_level(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) 		and float(value) >= 0.0 and float(value) <= 100.0


func from_dict(data: Variant) -> bool:
	if not validate_snapshot(data):
		return false
	levels = (data["levels"] as Dictionary).duplicate(true)
	levels.erase("defectiveness")
	crying = bool(data.get("crying", level("sadness") >= CRY_START))
	directed = (data["directed"] as Dictionary).duplicate(true)
	dispositions = (data.get("dispositions", {}) as Dictionary).duplicate(true)
	return true
