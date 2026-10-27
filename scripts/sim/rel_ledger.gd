extends RefCounted
## Kniha křivd a viny – co mám proti komu (grudge) a čím jsem ublížil/a já (guilt).
##
## Vztah (−100..100) říká, jak se lidé mají rádi; křivda říká, co mezi nimi „visí“.
## Dokud křivda nevyprchá nebo ji neuzavře omluva, brzdí oteplování vztahu (příjemný hovor
## pomůže méně). Vina vede k omluvě (AI) – nebo k výčitkám, které nikdo nevidí.
##
## Upřímnost omluvy se odvozuje z chování, ne z textu: kolik omluv v poslední době přišlo
## a jestli po předchozí omluvě přišlo nové ublížení („sorry, a zase“). Omluva tedy nejde
## farmit ani zneužít ke griefingu – opakované omluvy ztrácí váhu a spam druhého otráví.
##
## Čistý modul bez uzlů; čas v herních minutách.

const GRUDGE_TAU := 4320.0  # ~3 dny (násobí povaha)
const GUILT_TAU := 2880.0   # ~2 dny
const TOO_SOON := 45.0       # minut po křivdě: „teď ne“
const SPAM_WINDOW := 120.0
const RECENT_WINDOW := 2880.0
const BROKEN_WINDOW := 4320.0  # nové ublížení do 3 dnů po omluvě = porušená omluva
const MIN_VALUE := 0.5

var grudges := {}          # jméno -> 0..100
var guilt := {}            # jméno -> 0..100
var hurt_at := {}          # jméno -> kdy mi naposledy ublížil/a
var apologies_from := {}   # jméno -> Array[float] časů omluv, které jsem dostal/a
var broken := {}           # jméno -> „počet“ porušených omluv (pomalu vyprchává)
var apologized_to := {}    # jméno -> kdy jsem se mu/jí naposledy omluvil/a
## Private, direction-specific bond. This is NOT identical to liking (relationship −100..100).
## A character can love someone without depending on them, or depend on an ambivalent relationship.
## name -> {"importance": 0..1, "dependency": 0..1}; absent = importance inferred from liking only.
var attachments := {}
## Directional private trust is distinct from affection and emotional dependency.
const TRUST_BASE := 45.0
var trust := {}
## Bounded summaries of repeated experience survive the rolling text memories.
var relational_history := {}


func trust_in(who: String) -> float:
	return clampf(float(trust.get(who, TRUST_BASE)), 0.0, 100.0)


func record_trust(who: String, kind: String, change: float) -> void:
	if who.is_empty() or who.length() > 160 or not is_finite(change):
		return
	if kind not in ["warm", "hurt", "awkward", "misunderstanding", "repair", "support", "dismissed"]:
		return
	var h: Dictionary = relational_history.get(who, {})
	h[kind] = mini(int(h.get(kind, 0)) + 1, 255)
	relational_history[who] = h
	trust[who] = clampf(trust_in(who) + clampf(change, -20.0, 20.0), 0.0, 100.0)


## A reliable repeatedly sought person can become emotionally important,
## particularly for socially oriented agents with rejection sensitivity.
## Dependency is not a diagnosis or a guarantee that the bond is reciprocated.
func learn_attachment(who: String, liking: float, sociability: float,
		rejection_sensitivity: float, other_reliable_bonds: int = 0) -> void:
	if who.is_empty() or liking < 25.0:
		return
	var social_drive := clampf((sociability - 0.35) / 0.65, 0.0, 1.0)
	var sensitive := clampf((rejection_sensitivity - 0.55) / 0.45, 0.0, 1.0)
	var old := attachment_to(who, liking)
	var importance := maxf(float(old["importance"]),
		clampf(0.08 + maxf(liking, 0.0) * 0.0072, 0.08, 0.8))
	var trust_factor := clampf((trust_in(who) + 25.0) / 100.0, 0.35, 1.0)
	var diversity := clampf(1.0 - 0.15 * maxi(other_reliable_bonds, 0), 0.55, 1.0)
	var growth := 0.018 * social_drive * sensitive * 		clampf((liking - 15.0) / 60.0, 0.0, 1.0) * trust_factor * diversity
	set_attachment(who, minf(importance + 0.002, 1.0),
		clampf(float(old["dependency"]) + growth, 0.0, 1.0))



## Attachments are authored/learned per individual, not by global psychological traits.
## Validated here because NPC/AI code can supply values in addition to character UI.
func set_attachment(who: String, importance: float, dependency: float) -> bool:
	if who.is_empty() or who.length() > 160 or not is_finite(importance) or not is_finite(dependency):
		return false
	if importance < 0.0 or importance > 1.0 or dependency < 0.0 or dependency > 1.0:
		return false
	attachments[who] = {"importance": importance, "dependency": dependency}
	return true


## Liking determines a baseline importance, never emotional dependency.
## Explicit bonds allow high dependency with negative or ambivalent feelings.
func attachment_to(who: String, liking: float) -> Dictionary:
	var default_importance := clampf(0.08 + maxf(liking, 0.0) / 100.0 * 0.72, 0.08, 0.8)
	var a: Dictionary = attachments.get(who, {})
	var importance := clampf(float(a.get("importance", default_importance)), 0.0, 1.0)
	var dependency := clampf(float(a.get("dependency", 0.0)), 0.0, 1.0)
	# The dependent person may matter intensely even during conflict, without being trusted.
	var impact := clampf(importance * (0.84 + dependency * 0.16) + dependency * 0.35, 0.0, 1.0)
	return {"importance": importance, "dependency": dependency, "impact": impact}


## Display is a qualitative private description; the returned label is not a diagnosis.
func attachment_label(who: String, liking: float) -> String:
	var a := attachment_to(who, liking)
	if float(a["dependency"]) >= 0.75:
		return "silná emoční závislost"
	if float(a["dependency"]) >= 0.4:
		return "zvýšená emoční závislost"
	if float(a["dependency"]) >= 0.12:
		return "začínající emoční závislost"
	if float(a["impact"]) < 0.18:
		return "spíše lhostejný vztah"
	if float(a["importance"]) >= 0.7:
		return "velmi důležitý člověk"
	if float(a["importance"]) >= 0.4:
		return "důležitý člověk"
	return "slabší citová vazba"


func grudge(who: String) -> float:
	return float(grudges.get(who, 0.0))


func guilt_of(who: String) -> float:
	return float(guilt.get(who, 0.0))


func max_guilt() -> float:
	var m := 0.0
	for k in guilt:
		m = maxf(m, float(guilt[k]))
	return m


## Někdo mi ublížil (urážka, hádka, stigma, odbytí…).
func on_hurt_by(who: String, amount: float, now: float) -> void:
	grudges[who] = clampf(grudge(who) + amount, 0.0, 100.0)
	var log: Array = apologies_from.get(who, [])
	if not log.is_empty() and now - float(log[-1]) < BROKEN_WINDOW and now > float(log[-1]):
		broken[who] = float(broken.get(who, 0.0)) + 1.0
	hurt_at[who] = now
	record_trust(who, "hurt", -minf(amount * 0.45, 12.0))


## Ublížil/a jsem já. amount = jak moc to cítím (Bručoun v ráži skoro vůbec).
func on_hurt_other(who: String, amount: float) -> void:
	guilt[who] = clampf(guilt_of(who) + amount, 0.0, 100.0)


## Pozvolné vyprchávání. grudge_mult / guilt_mult > 1 = pomaleji (zášť, výčitky).
func decay(dm: float, grudge_mult := 1.0, guilt_mult := 1.0) -> void:
	var kg := exp(-dm / (GRUDGE_TAU * maxf(grudge_mult, 0.1)))
	var kv := exp(-dm / (GUILT_TAU * maxf(guilt_mult, 0.1)))
	for k in grudges.keys():
		grudges[k] = float(grudges[k]) * kg
		if grudges[k] < MIN_VALUE:
			grudges.erase(k)
	for k in guilt.keys():
		guilt[k] = float(guilt[k]) * kv
		if guilt[k] < MIN_VALUE:
			guilt.erase(k)
	# Dependency eases slowly instead of becoming an inescapable permanent state.
	for who in attachments:
		var a: Dictionary = attachments[who]
		a["dependency"] = clampf(float(a["dependency"]) * exp(-dm / 86400.0), 0.0, 1.0)
		attachments[who] = a
	# Porušené omluvy se po dlouhé době „odpouštějí“ (nic není navždy).
	var kb := exp(-dm / 20160.0)  # ~2 týdny
	for k in broken.keys():
		broken[k] = float(broken[k]) * kb
		if broken[k] < 0.05:
			broken.erase(k)


## Jak moc křivda brzdí oteplování vztahu (násobič kladné změny).
func warmth_mult(who: String) -> float:
	return clampf(1.0 - grudge(who) / 120.0, 0.15, 1.0)


## Upřímnost omluvy od `who` z pohledu toho, kdo ji dostává (0..1).
func sincerity(who: String, now: float) -> float:
	var recent := 0
	for t in apologies_from.get(who, []):
		if now - float(t) < RECENT_WINDOW:
			recent += 1
	return clampf(1.0 - 0.3 * recent - 0.35 * float(broken.get(who, 0.0)), 0.0, 1.0)


## Vyhodnocení omluvy od `who`. Vrací {"outcome": accepted|partial|rejected|spam|none,
## "p": pravděpodobnost přijetí, "reason": String}. roll = náhodné číslo 0..1.
## forgiveness = povaha (+ smířlivější), rel = můj vztah k němu, stress = můj stres.
func evaluate_apology(who: String, now: float, rel: float, forgiveness: float, stress: float, roll: float) -> Dictionary:
	var log: Array = apologies_from.get(who, [])
	if not log.is_empty() and now - float(log[-1]) < SPAM_WINDOW:
		return {"outcome": "spam", "p": 0.0, "reason": "zase"}
	var g := grudge(who)
	if g < 3.0:
		return {"outcome": "none", "p": 1.0, "reason": "nic se nestalo"}
	var p := 0.3 + 0.35 * sincerity(who, now) + rel / 250.0 + forgiveness - g / 140.0 - stress / 350.0
	var reason := ""
	if now - float(hurt_at.get(who, -1.0e9)) < TOO_SOON:
		p -= 0.35
		reason = "příliš brzy"
	p = clampf(p, 0.03, 0.95)
	var outcome := "rejected"
	if roll < p:
		outcome = "accepted"
	elif roll < p + 0.3:
		outcome = "partial"
	return {"outcome": outcome, "p": p, "reason": reason}


## Zapíše přijatou omluvu (u toho, kdo ji dostal) a její následky na křivdu.
func receive_apology(who: String, outcome: String, now: float) -> void:
	if outcome == "none":
		return
	var log: Array = apologies_from.get(who, [])
	log.append(now)
	while log.size() > 6:
		log.pop_front()
	apologies_from[who] = log
	match outcome:
		"accepted":
			grudges[who] = maxf(grudge(who) * 0.35 - 10.0, 0.0)
			# Repeated broken apologies cannot immediately restore trust.
			record_trust(who, "repair", 7.0 / (1.0 + float(broken.get(who, 0.0))))
		"partial":
			grudges[who] = maxf(grudge(who) - 10.0, 0.0)
			record_trust(who, "repair", 1.5)
		"spam":
			grudges[who] = clampf(grudge(who) + 2.0, 0.0, 100.0)
	if grudge(who) < MIN_VALUE:
		grudges.erase(who)


## Následky u toho, kdo se omlouval.
func apology_given(who: String, outcome: String, now := 0.0) -> void:
	apologized_to[who] = now
	match outcome:
		"accepted":
			guilt[who] = guilt_of(who) * 0.25
		"partial":
			guilt[who] = guilt_of(who) * 0.7
		"none":
			guilt[who] = guilt_of(who) * 0.5
		"rejected":
			# Odmítnutá omluva: „aspoň jsem to zkusil/a“ – vina trochu poleví.
			# (Spam omluv vinu nesnižuje – výčitky se nedají „odklikat“.)
			guilt[who] = guilt_of(who) * 0.8
	if guilt_of(who) < MIN_VALUE:
		guilt.erase(who)


## Příjemný hovor pomalu obrušuje křivdu.
func soften(who: String, amount: float) -> void:
	if grudges.has(who):
		grudges[who] = maxf(grudge(who) - amount, 0.0)
		if grudges[who] < MIN_VALUE:
			grudges.erase(who)


func to_dict() -> Dictionary:
	return {"grudges": grudges.duplicate(), "guilt": guilt.duplicate(), "hurt_at": hurt_at.duplicate(),
		"apologized_to": apologized_to.duplicate(),
		"apologies_from": apologies_from.duplicate(true), "broken": broken.duplicate(),
		"attachments": attachments.duplicate(true), "trust": trust.duplicate(),
		"relational_history": relational_history.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	trust = _num_dict(d.get("trust", {}), 0.0, 100.0)
	relational_history = {}
	var raw_history = d.get("relational_history", {})
	if typeof(raw_history) == TYPE_DICTIONARY:
		for who in raw_history:
			if typeof(raw_history[who]) != TYPE_DICTIONARY:
				continue
			if String(who).is_empty() or String(who).length() > 160:
				continue
			var clean := {}
			for kind in ["warm", "hurt", "awkward", "misunderstanding", "repair", "support", "dismissed"]:
				if not raw_history[who].has(kind):
					continue
				var count = raw_history[who][kind]
				if typeof(count) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(count)):
					clean[kind] = clampi(int(count), 0, 255)
			relational_history[String(who)] = clean
	attachments = {}
	var raw: Variant = d.get("attachments", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for who in raw:
			if typeof(raw[who]) == TYPE_DICTIONARY:
				var a: Dictionary = raw[who]
				var imp: Variant = a.get("importance", null)
				var dep: Variant = a.get("dependency", null)
				if (typeof(imp) in [TYPE_INT, TYPE_FLOAT]) and (typeof(dep) in [TYPE_INT, TYPE_FLOAT]):
					set_attachment(String(who), float(imp), float(dep))
	grudges = _num_dict(d.get("grudges", {}), 0.0, 100.0)
	guilt = _num_dict(d.get("guilt", {}), 0.0, 100.0)
	hurt_at = _num_dict(d.get("hurt_at", {}), -1.0e12, 1.0e12)
	apologized_to = _num_dict(d.get("apologized_to", {}), -1.0e12, 1.0e12)
	broken = _num_dict(d.get("broken", {}), 0.0, 100.0)
	apologies_from = {}
	var a = d.get("apologies_from", {})
	if typeof(a) == TYPE_DICTIONARY:
		for k in a:
			if typeof(a[k]) == TYPE_ARRAY:
				var arr: Array = []
				for t in a[k]:
					arr.append(float(t))
				apologies_from[String(k)] = arr.slice(-6)


static func _num_dict(src, lo: float, hi: float) -> Dictionary:
	var out := {}
	if typeof(src) == TYPE_DICTIONARY:
		for k in src:
			if typeof(src[k]) == TYPE_FLOAT or typeof(src[k]) == TYPE_INT:
				if is_finite(float(src[k])) and not String(k).is_empty() and String(k).length() <= 160:
					out[String(k)] = clampf(float(src[k]), lo, hi)
	return out
