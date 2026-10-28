extends RefCounted
## Světonázor, názory a hodnoty (psychika J, 27. 10. 2026).
##
## Postoje k obecným herním tématům (−1..1, žádné skutečné strany, politici ani náboženství): tradice ↔ změna,
## důvěra v instituce, jednotlivec ↔ komunita, hmotné ↔ prožitky, duchovno a smysl, optimismus o světě,
## práce jako povinnost ↔ rovnováha, význam rodiny, opatrnost ↔ riziko; a základní hodnoty (0..1):
## poctivost, loajalita, férovost, svoboda, bezpečí, úspěch, péče.
##
## Názor má sílu (|postoj|) a jistotu. Posouvá se pomalu: rozhovory s lidmi, kterým postava věří, zkušenosti
## (opora, zrada, dobré a zlé události). Konfirmační zkreslení: velmi vzdálené názory hýbou jen málo,
## shoda s důvěryhodným člověkem jistotu posílí; odpor roste s jistotou. Meze: od vlastního výchozího
## postoje se posun drží do ±0,4 a pomalu se k němu vrací, takže domácnost se nepolarizuje bez konce.
## Shoda je jen JEDEN z mnoha faktorů vřelosti vztahu a rozhovoru (omezeně); nesouhlas se snese s
## velkou náklonností. Soukromé: navenek jen to, co postava sama řekne (mind.voice_opinions).

const TOPICS := ["tradition", "institutions", "community", "materialism", "meaning", "optimism", "work", "family", "risk"]
const VALUES := ["honesty", "loyalty", "fairness", "freedom", "security", "achievement", "care"]
## Která hodnota dělá téma důležitým (salience).
const TOPIC_VALUE := {"tradition": "security", "institutions": "fairness", "community": "care", "materialism": "achievement",
	"meaning": "care", "optimism": "security", "work": "achievement", "family": "loyalty", "risk": "freedom"}
## Repliky (veřejné jen s mind.voice_opinions): [pro kladný pól, pro záporný pól].
const LINES := {
	"tradition": ["Osvědčené věci dávají životu pevnost.", "Svět se mění a my bychom měli taky."],
	"institutions": ["Úřadům a pravidlům se dá většinou věřit.", "Spoléhat se na instituce? To radši ne."],
	"community": ["Spolu toho zvládneme víc.", "Každý se má hlavně postarat sám o sebe."],
	"materialism": ["Jistota je mít něco svého.", "Věci nejsou všechno, zážitky jsou víc."],
	"meaning": ["Myslím, že všechno má nějaký hlubší smysl.", "Smysl si člověk dělá sám."],
	"optimism": ["Svět se nakonec zlepšuje.", "Mám pocit, že to jde z kopce."],
	"work": ["Práce je povinnost a čest.", "Práce není všechno, život je jinde."],
	"family": ["Rodina je základ.", "Rodina nemusí být všechno."],
	"risk": ["Kdo neriskuje, nic nezíská.", "Radši dvakrát měř, jednou řež."],
}
const MAX_DRIFT := 0.4
const RATE := 0.03
const RETURN_TAU := 20.0 * 1440.0

var base := {}
var stance := {}
var certainty := {}
var values := {}
var voice_opinions := false
var shifts := 0


func active() -> bool:
	return not base.is_empty()


func configure(wv: Variant, vals: Variant, cert: Variant, voice: Variant, keep_state: bool) -> void:
	var old_stance := stance.duplicate()
	var old_cert := certainty.duplicate()
	base = {}
	if typeof(wv) == TYPE_DICTIONARY:
		for t in wv:
			if TOPICS.has(t) and typeof(wv[t]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(wv[t])):
				var v := clampf(float(wv[t]), -1.0, 1.0)
				if v != 0.0:
					base[String(t)] = v
	values = {}
	if typeof(vals) == TYPE_DICTIONARY:
		for v in vals:
			if VALUES.has(v) and typeof(vals[v]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(vals[v])):
				values[String(v)] = clampf(float(vals[v]), 0.0, 1.0)
	var c0 := clampf(float(cert), 0.0, 1.0) if typeof(cert) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(cert)) else 0.5
	voice_opinions = bool(voice) if typeof(voice) == TYPE_BOOL else false
	stance = {}
	certainty = {}
	for t in base:
		stance[t] = clampf(float(old_stance.get(t, base[t])), float(base[t]) - MAX_DRIFT, float(base[t]) + MAX_DRIFT) if keep_state else float(base[t])
		stance[t] = clampf(float(stance[t]), -1.0, 1.0)
		certainty[t] = float(old_cert.get(t, c0)) if keep_state else c0
	if not keep_state:
		shifts = 0


func value(v: String) -> float:
	return float(values.get(v, 0.5))


func salience(t: String) -> float:
	return clampf(absf(float(stance.get(t, 0.0))) * (0.5 + value(String(TOPIC_VALUE.get(t, "care")))), 0.0, 1.5)


## Nejvýraznější téma (deterministicky; při shodě podle pořadí v TOPICS).
func top_topic() -> String:
	var best := ""
	var bs := 0.0
	for t in TOPICS:
		if stance.has(t) and salience(t) > bs:
			bs = salience(t)
			best = t
	return best


## Shoda s druhým na tématu (0 = protiklad, 1 = stejně). Bez názoru jednoho z nich = neutrální 0,5.
func agreement_with(other, t: String) -> float:
	if other == null or not stance.has(t) or not other.stance.has(t):
		return 0.5
	return 1.0 - absf(float(stance[t]) - float(other.stance[t])) / 2.0


## Posun šance na dobrý rozhovor podle shody na tom nejvýraznějším tématu (±0,03, jen jeden z faktorů).
func talk_bias(other) -> float:
	if not active() or other == null or not other.active():
		return 0.0
	var t := top_topic()
	if t == "":
		return 0.0
	return 0.06 * (agreement_with(other, t) - 0.5) * clampf(salience(t), 0.0, 1.0)


## Násobič změny vztahu po dobrém rozhovoru (0,93–1,07).
func warmth_mult(other) -> float:
	if not active() or other == null or not other.active():
		return 1.0
	var t := top_topic()
	if t == "":
		return 1.0
	var shared := 0.0
	for v in ["care", "loyalty", "honesty"]:
		shared += 1.0 - absf(value(v) - other.value(v))
	shared /= 3.0
	return clampf(1.0 + 0.1 * (agreement_with(other, t) - 0.5) * clampf(salience(t), 0.0, 1.0) + 0.04 * (shared - 0.5), 0.93, 1.07)


## Rozhovor: posluchač se pomalu posune k mluvčímu – víc u důvěry, méně u jistoty, skoro vůbec u velmi
## vzdáleného názoru (konfirmační zkreslení, žádný „backfire“). Vrací posun.
func hear(speaker, t: String, trust: float, positive: bool) -> float:
	if not positive or speaker == null or not stance.has(t) or not speaker.stance.has(t):
		return 0.0
	var diff := float(speaker.stance[t]) - float(stance[t])
	var trust_k := clampf((trust - 30.0) / 70.0, 0.0, 1.0)
	var bias := 1.0 if absf(diff) <= 1.0 else 0.2
	var d := RATE * diff * trust_k * (1.0 - float(certainty[t])) * bias
	var b := float(base[t])
	stance[t] = clampf(float(stance[t]) + d, maxf(b - MAX_DRIFT, -1.0), minf(b + MAX_DRIFT, 1.0))
	# Shoda s důvěryhodným člověkem jistotu posílí, nesouhlas ji trochu nahlodá.
	if absf(diff) < 0.3:
		certainty[t] = clampf(float(certainty[t]) + 0.01 * trust_k, 0.05, 0.95)
	elif absf(diff) > 1.0:
		certainty[t] = clampf(float(certainty[t]) - 0.005 * trust_k, 0.05, 0.95)
	if absf(d) > 1e-6:
		shifts += 1
	return d


## Zkušenost posune postoj o malý krok (opora → komunita, optimismus; zrada → méně optimismu …).
func experience(t: String, amount: float) -> void:
	if not stance.has(t) or not is_finite(amount):
		return
	var b := float(base[t])
	stance[t] = clampf(float(stance[t]) + amount * (1.0 - float(certainty[t])), maxf(b - MAX_DRIFT, -1.0), minf(b + MAX_DRIFT, 1.0))


func tick(dm: float) -> void:
	if dm <= 0.0 or base.is_empty():
		return
	var k := 1.0 - exp(-dm / RETURN_TAU)
	for t in stance:
		stance[t] = float(stance[t]) + (float(base[t]) - float(stance[t])) * k


## Veřejná replika (jen s mind.voice_opinions) – vyjádření názoru vlastními slovy postavy.
func opinion_line(t: String) -> String:
	if not voice_opinions or not stance.has(t) or absf(float(stance[t])) < 0.3:
		return ""
	return String(LINES[t][0 if float(stance[t]) > 0.0 else 1])


func private_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var t := top_topic()
	if t != "" and absf(float(stance[t])) >= 0.3:
		out.append("Na čem jí/mu teď záleží: „%s“ (%s)." % [String(LINES[t][0 if float(stance[t]) > 0.0 else 1]),
			"jistě" if float(certainty[t]) >= 0.7 else ("spíš" if float(certainty[t]) >= 0.4 else "váhavě")])
	return out


func to_dict() -> Dictionary:
	return {"stance": stance.duplicate(), "certainty": certainty.duplicate(), "shifts": shifts}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 4:
		return false
	for key in d:
		if not ["stance", "certainty", "shifts"].has(key):
			return false
	for key in ["stance", "certainty"]:
		var m = d.get(key, {})
		if typeof(m) != TYPE_DICTIONARY or m.size() > TOPICS.size():
			return false
		for t in m:
			if not TOPICS.has(t) or typeof(m[t]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(m[t])) or absf(float(m[t])) > 1.0:
				return false
			if key == "certainty" and float(m[t]) < 0.0:
				return false
	if d.has("shifts"):
		var n = d["shifts"]
		# JSON decodes integral numbers as floats: accept 2.0, never 2.5/NaN/Inf.
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(n)) or float(n) < 0.0 or float(n) != floor(float(n)) or float(n) > 9007199254740991.0:
			return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	for t in d.get("stance", {}):
		if base.has(t):
			stance[t] = clampf(float(d["stance"][t]), maxf(float(base[t]) - MAX_DRIFT, -1.0), minf(float(base[t]) + MAX_DRIFT, 1.0))
	for t in d.get("certainty", {}):
		if base.has(t):
			certainty[t] = clampf(float(d["certainty"][t]), 0.05, 0.95)
	shifts = int(d.get("shifts", 0))
