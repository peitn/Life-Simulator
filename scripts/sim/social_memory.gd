extends RefCounted
## Sociální a afektivní paměť (psychika B, 27. 10. 2026) – strukturované stopy „kdo → komu, co se stalo“.
##
## Stopa NENÍ volný text ani autobiografie: je to záznam z pevného katalogu druhů (křivda, omluva, stížnost,
## opora, společná chvíle, zrada důvěry, odmítnutí, nedorozumění, příjemný rozhovor, zahanbení, nátlak):
##   who        – stabilní uid osoby, která jednala (nikdy jméno; jméno je jen popisek pro HUD)
##   whom       – komu to udělala ("" = mně; u viděného / slyšeného uid oběti)
##   kind       – druh události (fakt), role – zda se stala mně, nebo jsem ji jen viděl(a) / slyšel(a)
##   t          – herní čas, charge – emoční náboj −1..1, severity – závažnost 0..1
##   certainty  – jak jistě si postava pamatuje, že se to stalo (zažila > viděla > slyšela)
##   interp     – výklad postavy („schválně“ / „nejasné“ / „nechtěně“) – odděleně od faktu
##   strength   – současná síla stopy 0..1 (vyhasíná, silné stopy pomaleji)
##
## Dynamika: postupné vyhasínání (τ podle druhu × závažnosti × schopnosti pamatovat si), zesílení stejným
## druhem od stejné osoby, přepsání opačnou událostí (omluva oslabí křivdu), oživení podnětem (setkání
## s osobou, stejné místo) s omezením – stejná stopa se znovu oživí nejdřív po COOLDOWN, takže se nedá
## „farmit“ ani nekmitá. Hystereze popisku vztahu: popisek se změní až po překročení hranice o rezervu.
##
## Paměť jen mění náklady a pravděpodobnosti (omezené násobiče 0,85–1,15, posun šance na dobrý rozhovor
## nejvýš ±0,04); nikdy nediktuje akci. Soukromé: druzí znají jen to, co viděli, slyšeli nebo jim někdo
## řekl (source = self / witnessed / told). Do sítě ani snapshotu nejde nic.
## Čistý a deterministický modul: žádná náhoda, jen čas.

const KINDS := {
	"grievance": {"charge": -0.8, "tau_days": 6.0, "label": "ublížil(a) mi"},
	"insult": {"charge": -1.0, "tau_days": 8.0, "label": "urazil(a) mě"},
	"complaint": {"charge": -0.35, "tau_days": 2.0, "label": "štvalo mě, co dělá"},
	"misunderstanding": {"charge": -0.3, "tau_days": 2.0, "label": "nepochopili jsme se"},
	"trust_breach": {"charge": -0.9, "tau_days": 12.0, "label": "odbyl(a) mě, když jsem se svěřil(a)"},
	"rejection": {"charge": -0.6, "tau_days": 5.0, "label": "odmítl(a) mě"},
	"humiliation": {"charge": -0.8, "tau_days": 8.0, "label": "zesměšnil(a) mě před ostatními"},
	"pressure": {"charge": -0.85, "tau_days": 9.0, "label": "tlačil(a) na mě"},
	"apology": {"charge": 0.6, "tau_days": 9.0, "label": "omluvil(a) se mi"},
	"support": {"charge": 0.9, "tau_days": 10.0, "label": "stál(a) při mně"},
	"shared_moment": {"charge": 0.6, "tau_days": 5.0, "label": "měli jsme spolu hezkou chvíli"},
	"pleasant_talk": {"charge": 0.3, "tau_days": 2.0, "label": "příjemně jsme si popovídali"},
	"conflict_seen": {"charge": -0.3, "tau_days": 3.0, "label": "viděl(a) jsem, jak se hádá"},
}
## Které kladné druhy oslabují které záporné (přepsání), a naopak.
const COUNTERS := {
	"apology": ["grievance", "insult", "complaint", "misunderstanding", "trust_breach", "humiliation", "pressure"],
	"support": ["trust_breach", "rejection", "grievance"],
	"shared_moment": ["complaint", "misunderstanding", "grievance"],
	"pleasant_talk": ["misunderstanding", "complaint"],
	"insult": ["shared_moment", "pleasant_talk"],
	"trust_breach": ["support"],
	"pressure": ["shared_moment", "pleasant_talk", "support"],
}
const SOURCES := ["self", "witnessed", "told"]
const INTERPS := ["intended", "unclear", "accidental", "none"]
const ROLES := ["me", "seen", "heard"]
const MAX_TRACES := 64
## Oživení podnětem: nejvýš jednou za 6 h na stopu, malý krok, strop podle závažnosti. Krok roste s tím,
## jak dlouho se na stopu nevzpomnělo (CUE_RECALL) – časté běžné setkání stopu jen udržuje a vyhasínání
## vyhraje, takže každodenní soužití bez nové křivdy hojí (žádné „věčné“ udržování ani kmitání).
const CUE_COOLDOWN := 360.0
const CUE_GAIN := 0.06
const CUE_RECALL := 4320.0
## Stopa pod touto silou se zapomene (odstraní).
const FORGET_BELOW := 0.02
## Hystereze popisků vztahu (body vztahu).
const LABEL_MARGIN := 4.0
const LABELS := [[60.0, "blízký vztah"], [25.0, "přátelský vztah"], [-24.9, "neutrální vztah"],
	[-60.0, "napjatý vztah"], [-100.0, "nepřátelský vztah"]]

## Schopnosti paměti (mind.memory, 0..1, 0,5 = průměr): retention – jak dlouho, precision – jak přesně
## (jistota vybavení), emotional_weight – jak silně nese emoční náboj.
var retention := 0.5
var precision := 0.5
var emotional_weight := 0.5

var traces: Array = []
var _next_id := 1
var _acc := 0.0
## Popisky vztahu s hysterezí: uid → index v LABELS.
var view_labels := {}
## uid → poslední známé jméno (jen pro soukromý HUD; klíčem je uid).
var names := {}


func configure(memory: Variant, k: float) -> void:
	var m: Dictionary = memory if typeof(memory) == TYPE_DICTIONARY else {}
	retention = _ability(m, "retention", k)
	precision = _ability(m, "precision", k)
	emotional_weight = _ability(m, "emotional_weight", k)


## Režim obsahu tlumí jen individuální odchylku schopností (off = průměr), samotná paměť běží vždy.
static func _ability(m: Dictionary, key: String, k: float) -> float:
	var v = m.get(key, 0.5)
	var f := float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)) else 0.5
	return 0.5 + (clampf(f, 0.0, 1.0) - 0.5) * clampf(k, 0.0, 1.0)


func _tau(kind: String, severity: float) -> float:
	var base := float(KINDS[kind]["tau_days"]) * 1440.0
	# Silné stopy vyhasínají pomaleji; schopnost pamatovat si ×0,45 … ×1,8.
	return base * (0.5 + severity) * lerpf(0.45, 1.8, retention)


## Zapíše událost. who = uid druhé osoby, name = popisek. source: self / witnessed / told.
## interp: výklad (záporné události), place = tag místa (oživení místem). Vrací id stopy (0 = nic).
func record(who: String, name: String, kind: String, severity: float, now: float, source := "self",
		interp := "none", place := "", whom := "") -> int:
	if who == "" or not KINDS.has(kind) or not SOURCES.has(source) or not is_finite(now) or not is_finite(severity):
		return 0
	severity = clampf(severity, 0.0, 1.0)
	if not INTERPS.has(interp):
		interp = "none"
	names[who] = name.substr(0, 40)
	var charge := float(KINDS[kind]["charge"])
	var src_k := {"self": 1.0, "witnessed": 0.6, "told": 0.4}[source] as float
	var certainty := clampf(lerpf(0.65, 1.0, precision) * src_k, 0.05, 1.0)
	var initial := clampf(severity * lerpf(0.7, 1.25, emotional_weight) * (1.0 if source == "self" else 0.7), 0.05, 1.0)
	# Strop síly podle závažnosti: sto drobností nenadělá jednu velkou událost (opakování jen udržuje).
	var cap := clampf(0.35 + 0.65 * severity, 0.0, 1.0)
	# Přepsání: opačná událost oslabí starší stopy od stejné osoby.
	for c in COUNTERS.get(kind, []):
		for tr in traces:
			if tr["who"] == who and tr["kind"] == c:
				tr["strength"] = float(tr["strength"]) * (1.0 - 0.5 * severity * certainty)
	# Zesílení: stejný druh, stejná osoba, stejný zdroj → jedna silnější stopa místo nové.
	for tr in traces:
		if tr["who"] == who and tr["kind"] == kind and tr["source"] == source and String(tr.get("whom", "")) == whom:
			var s := float(tr["strength"])
			tr["severity"] = maxf(float(tr["severity"]), severity)
			var c2 := clampf(0.35 + 0.65 * float(tr["severity"]), 0.0, 1.0)
			tr["strength"] = maxf(s, minf(s + initial * (1.0 - s) * 0.8, c2))
			tr["certainty"] = maxf(float(tr["certainty"]), certainty)
			tr["t"] = now
			tr["cue_t"] = now
			tr["count"] = mini(int(tr["count"]) + 1, 9999)
			if interp != "none":
				tr["interp"] = interp
			if place != "":
				tr["place"] = place.substr(0, 24)
			_prune()
			return int(tr["id"])
	var id := _next_id
	_next_id += 1
	traces.append({"id": id, "who": who, "kind": kind, "t": now, "charge": charge, "severity": severity,
		"certainty": certainty, "source": source, "interp": interp, "strength": minf(initial, cap),
		"place": place.substr(0, 24), "count": 1, "cue_t": now, "whom": whom.substr(0, 64)})
	_prune()
	return id


func _prune() -> void:
	var keep: Array = []
	for tr in traces:
		if float(tr["strength"]) >= FORGET_BELOW:
			keep.append(tr)
	traces = keep
	if traces.size() > MAX_TRACES:
		# Nejslabší se zapomenou první (deterministicky: síla, pak id).
		traces.sort_custom(func(x, y): return float(x["strength"]) > float(y["strength"]) \
			or (float(x["strength"]) == float(y["strength"]) and int(x["id"]) < int(y["id"])))
		traces = traces.slice(0, MAX_TRACES)
		traces.sort_custom(func(x, y): return int(x["id"]) < int(y["id"]))


## Vyhasínání (po herních hodinách, nezávisle na délce kroku).
func tick(dm: float) -> void:
	if dm <= 0.0 or traces.is_empty():
		_acc = 0.0
		return
	_acc += dm
	if _acc < 60.0:
		return
	var step := _acc
	_acc = 0.0
	for tr in traces:
		tr["strength"] = float(tr["strength"]) * exp(-step / _tau(String(tr["kind"]), float(tr["severity"])))
	_prune()


## Podnět: setkání s osobou (případně na místě). Oživí stopy o ní (omezeně) a stopy vázané na místo.
func cue(who: String, now: float, place := "") -> void:
	for tr in traces:
		var match_who: bool = who != "" and tr["who"] == who
		var match_place: bool = place != "" and tr["place"] == place
		if not (match_who or match_place) or now - float(tr["cue_t"]) < CUE_COOLDOWN:
			continue
		var cap := clampf(0.35 + 0.65 * float(tr["severity"]), 0.0, 1.0)
		var s := float(tr["strength"])
		var recall := clampf((now - float(tr["cue_t"])) / CUE_RECALL, 0.0, 1.0)
		if s < cap:
			tr["strength"] = minf(s + CUE_GAIN * recall * (0.5 if match_place and not match_who else 1.0) * (cap - s), cap)
		tr["cue_t"] = now


## Afektivní bilance vůči osobě −1..1 (záporné = opatrnost, kladné = důvěra). Výklad „schválně“ váží víc.
func bias(who: String) -> float:
	var s := 0.0
	for tr in traces:
		if tr["who"] != who:
			continue
		var w := float(tr["charge"]) * float(tr["strength"]) * float(tr["certainty"])
		if String(tr["interp"]) == "intended" and w < 0.0:
			w *= 1.3
		elif String(tr["interp"]) == "accidental" and w < 0.0:
			w *= 0.6
		s += w
	return clampf(tanh(s * 1.2), -1.0, 1.0)


## Výběr partnera: omezený násobič (opora víc váží u svěření).
func target_weight(who: String, action_id: String) -> float:
	if traces.is_empty() or who == "":
		return 1.0
	var b := bias(who)
	if b == 0.0:
		return 1.0
	var k := 0.15
	if action_id == "confide":
		k = 0.2
	return clampf(1.0 + k * b, 0.85, 1.15)


## Posun šance na dobrý rozhovor (±0,04).
func talk_bias(who: String) -> float:
	if traces.is_empty():
		return 0.0
	return 0.04 * bias(who)


## Nejsilnější záporná stopa o někom jiném než `except` – co postava může někomu svěřit („řekl(a) mi…“).
func strongest_negative(except: String) -> Dictionary:
	var best := {}
	for tr in traces:
		if tr["who"] == except or float(tr["charge"]) >= 0.0 or String(tr["source"]) == "told":
			continue
		if best.is_empty() or float(tr["strength"]) * float(tr["severity"]) > float(best["strength"]) * float(best["severity"]):
			best = tr
	return best


## Hodinová obnova popisků s hysterezí pro všechny vztahy {uid: hodnota vztahu}.
func update_views(values: Dictionary) -> void:
	var ids: Array = values.keys()
	ids.sort()
	for who in ids:
		view_label(String(who), float(values[who]))


func current_view(who: String) -> String:
	if not view_labels.has(who):
		return ""
	return String(LABELS[clampi(int(view_labels[who]), 0, LABELS.size() - 1)][1])


## Popisek vztahu s hysterezí (pro soukromý HUD): mění se až po překročení hranice o LABEL_MARGIN.
func view_label(who: String, value: float) -> String:
	var idx := LABELS.size() - 1
	for i in LABELS.size():
		if value >= float(LABELS[i][0]):
			idx = i
			break
	if not view_labels.has(who):
		view_labels[who] = idx
		return String(LABELS[idx][1])
	var cur: int = int(view_labels[who])
	if idx < cur:
		# Zlepšení: hranice vyšší kategorie musí být překročena o rezervu.
		if value >= float(LABELS[idx][0]) + LABEL_MARGIN or idx < cur - 1:
			cur = idx
	elif idx > cur:
		# Zhoršení: pod dolní hranici současné kategorie o rezervu.
		if value < float(LABELS[cur][0]) - LABEL_MARGIN or idx > cur + 1:
			cur = idx
	view_labels[who] = cur
	return String(LABELS[cur][1])


## Slovní souhrn nejsilnějších vzpomínek o osobě (žádná čísla, pevné šablony).
func describe(who: String, grammar_form: Callable, limit := 2) -> PackedStringArray:
	var mine: Array = []
	for tr in traces:
		if tr["who"] == who and float(tr["strength"]) >= 0.08:
			mine.append(tr)
	mine.sort_custom(func(x, y): return float(x["strength"]) > float(y["strength"]) \
		or (float(x["strength"]) == float(y["strength"]) and int(x["id"]) < int(y["id"])))
	var out := PackedStringArray()
	for tr in mine.slice(0, limit):
		var txt := String(KINDS[tr["kind"]]["label"])
		if grammar_form.is_valid():
			txt = String(grammar_form.call(txt))
		var sure := "jistě" if float(tr["certainty"]) >= 0.75 else ("nejspíš" if float(tr["certainty"]) >= 0.45 else "možná")
		var vivid := "živě" if float(tr["strength"]) >= 0.5 else "matně"
		var src := "" if tr["source"] == "self" else (" (viděl(a) jsem to)" if tr["source"] == "witnessed" else " (slyšel(a) jsem to)")
		var why := ""
		match String(tr["interp"]):
			"intended": why = ", myslím, že schválně"
			"accidental": why = ", asi nechtěně"
		out.append("%s %s, %s%s%s" % [txt, sure, vivid, why, src])
	return out


func traces_about(who: String) -> Array:
	var out: Array = []
	for tr in traces:
		if tr["who"] == who:
			out.append(tr)
	return out


func to_dict() -> Dictionary:
	return {"traces": traces.duplicate(true), "next_id": _next_id, "acc": _acc,
		"view_labels": view_labels.duplicate(), "names": names.duplicate()}


static func _num(v: Variant, lo: float, hi: float) -> bool:
	return typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 8:
		return false
	for key in d:
		if not ["traces", "next_id", "acc", "view_labels", "names"].has(key):
			return false
	var tr = d.get("traces", [])
	if typeof(tr) != TYPE_ARRAY or tr.size() > MAX_TRACES:
		return false
	for t in tr:
		if typeof(t) != TYPE_DICTIONARY or t.size() > 16:
			return false
		if typeof(t.get("who")) != TYPE_STRING or String(t["who"]).length() > 64 or String(t["who"]) == "":
			return false
		if typeof(t.get("kind")) != TYPE_STRING or not KINDS.has(t["kind"]):
			return false
		if typeof(t.get("source")) != TYPE_STRING or not SOURCES.has(t["source"]):
			return false
		if typeof(t.get("interp")) != TYPE_STRING or not INTERPS.has(t["interp"]):
			return false
		if typeof(t.get("place", "")) != TYPE_STRING or String(t.get("place", "")).length() > 24:
			return false
		if typeof(t.get("whom", "")) != TYPE_STRING or String(t.get("whom", "")).length() > 64:
			return false
		if not _num(t.get("id"), 1.0, 1.0e9) or not _num(t.get("t"), -1.0e12, 1.0e12) \
				or not _num(t.get("charge"), -1.0, 1.0) or not _num(t.get("severity"), 0.0, 1.0) \
				or not _num(t.get("certainty"), 0.0, 1.0) or not _num(t.get("strength"), 0.0, 1.0) \
				or not _num(t.get("count", 1), 1.0, 9999.0) or not _num(t.get("cue_t", -1.0e9), -1.0e12, 1.0e12):
			return false
	if d.has("next_id") and not _num(d["next_id"], 1.0, 1.0e9):
		return false
	if d.has("acc") and not _num(d["acc"], 0.0, 1.0e6):
		return false
	var vl = d.get("view_labels", {})
	if typeof(vl) != TYPE_DICTIONARY or vl.size() > 64:
		return false
	for key in vl:
		if typeof(key) != TYPE_STRING or not _num(vl[key], 0.0, float(LABELS.size() - 1)):
			return false
	var nm = d.get("names", {})
	if typeof(nm) != TYPE_DICTIONARY or nm.size() > 128:
		return false
	for key in nm:
		if typeof(key) != TYPE_STRING or typeof(nm[key]) != TYPE_STRING or String(nm[key]).length() > 40:
			return false
	return true


func from_dict(d: Variant) -> bool:
	if not validate_snapshot(d):
		return false
	traces = []
	for t in d.get("traces", []):
		traces.append({"id": int(t["id"]), "who": String(t["who"]), "kind": String(t["kind"]), "t": float(t["t"]),
			"charge": float(t["charge"]), "severity": float(t["severity"]), "certainty": float(t["certainty"]),
			"source": String(t["source"]), "interp": String(t["interp"]), "strength": float(t["strength"]),
			"place": String(t.get("place", "")), "count": int(t.get("count", 1)), "cue_t": float(t.get("cue_t", -1.0e9)),
			"whom": String(t.get("whom", ""))})
	_next_id = int(d.get("next_id", traces.size() + 1))
	for t in traces:
		_next_id = maxi(_next_id, int(t["id"]) + 1)
	_acc = float(d.get("acc", 0.0))
	view_labels = {}
	for key in d.get("view_labels", {}):
		view_labels[String(key)] = int(d["view_labels"][key])
	names = (d.get("names", {}) as Dictionary).duplicate()
	return true
