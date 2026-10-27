extends RefCounted
## Osobnostní akcenty (psychika D, 27. 10. 2026) – konfigurovatelná osobnost se zvýrazněnými rysy, které
## mohou působit potíže ve vztazích. Není to „přepínač poruchy“: soukromé posuvníky mind.accents (0..1).
##
## Účinky jdou přes EXISTUJÍCÍ systémy, takže z nich vznikají mezilidské vzorce, ne skript:
##   - parametry rysů (Traits.ACCENTS: chemie, sklon k hádce, zášť, odpuštění, pýcha, stigma, žárlivost,
##     úbytek potřeby lidí, chuť na sociální akce …) se přidají do trait_profile jako váhy acc_*;
##   - háčky: síla reakce na odmítnutí, výklad úmyslu, domnělé odmítnutí, růst důvěry, amplituda emocí,
##     učení citové závislosti, náročnost sociálních akcí, smyčky přemítání.
## Výkladový název (např. „rysy emoční nestability“) je jen volitelná soukromá vrstva (mind.accent_labels),
## nikdy veřejný a nikdy podmínka chování. Postavy nejsou šablony záporáků: každý akcent má i lidský
## důvod a nic se nevynucuje.

const KEYS := ["abandonment", "suspicious", "attention", "perfectionism", "avoidance", "dependency",
	"grandiosity", "detachment"]
## Volitelné výkladové názvy (jen soukromě, jen když hráč chce): [akcent, práh, název].
const LABELS := [
	["abandonment", 0.6, "rysy emoční nestability (hraniční styl)"],
	["suspicious", 0.6, "paranoidní rysy (nedůvěřivý styl)"],
	["attention", 0.6, "histrionské rysy (styl hledající pozornost)"],
	["perfectionism", 0.6, "anankastické rysy (perfekcionistický styl)"],
	["avoidance", 0.6, "vyhýbavé rysy (úzkostně vyhýbavý styl)"],
	["dependency", 0.6, "závislé rysy (styl opírající se o druhé)"],
	["grandiosity", 0.6, "narcistické rysy (styl hledající obdiv)"],
	["detachment", 0.6, "schizoidní rysy (odtažitý styl)"],
]

## Hodnoty škálované režimem obsahu (full 1, muted 0,5, off 0).
var w := {}
var show_labels := false


func a(id: String) -> float:
	return float(w.get(id, 0.0))


func is_empty() -> bool:
	return w.is_empty()


func configure(accents: Variant, labels: Variant, k: float) -> void:
	w = {}
	show_labels = bool(labels) if typeof(labels) == TYPE_BOOL else false
	if typeof(accents) != TYPE_DICTIONARY or k <= 0.0:
		return
	for id in accents:
		if KEYS.has(id) and typeof(accents[id]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(accents[id])):
			var v := clampf(float(accents[id]), 0.0, 1.0) * clampf(k, 0.0, 1.0)
			if v > 0.0:
				w[String(id)] = v


## Váhy do trait_profile (acc_<id>). Prázdné = profil beze změny.
func profile_weights() -> Dictionary:
	var out := {}
	for id in w:
		out["acc_" + String(id)] = float(w[id])
	return out


## Síla reakce na odmítnutí (násobí přírůstek stresu a emoční odezvu).
func rejection_mult() -> float:
	return 1.0 + 0.6 * a("abandonment") + 0.35 * a("attention") + 0.3 * a("avoidance") + 0.2 * a("dependency") \
		- 0.3 * a("detachment")


## Posun vyhodnocení nejasného úmyslu (podezíravost čte víc „schválně“).
func appraisal_shift() -> float:
	return 0.25 * a("suspicious") + 0.05 * a("abandonment")


func perceived_rejection_add() -> float:
	return 0.08 * a("suspicious") + 0.05 * a("abandonment") + 0.03 * a("avoidance")


## Kladná důvěra roste pomaleji u podezíravosti, rychleji u závislosti.
func trust_gain_mult() -> float:
	return clampf(1.0 - 0.5 * a("suspicious") + 0.25 * a("dependency") - 0.3 * a("detachment"), 0.3, 1.5)


## Amplituda emočních impulzů: výkyvy u emoční nestability, oploštění u odstupu.
func emotion_amplitude() -> float:
	return clampf(1.0 + 0.5 * a("abandonment") + 0.15 * a("attention") - 0.4 * a("detachment"), 0.5, 1.6)


## Učení citové závislosti na konkrétním člověku.
func attachment_mult() -> float:
	return clampf(1.0 + 0.5 * a("dependency") + 0.4 * a("abandonment") - 0.5 * a("detachment"), 0.3, 1.9)


## Přídavek k náročnosti sociálních akcí (MentalState.social_difficulty), omezený.
func social_cost() -> float:
	return clampf(0.25 * a("avoidance") + 0.05 * a("suspicious"), 0.0, 0.3)


## Smyčky přemítání: nezdar u perfekcionismu, křivda u podezíravosti a citlivosti na opuštění.
func rumination_mult(topic: String) -> float:
	match topic:
		"failure":
			return 1.0 + 0.8 * a("perfectionism") + 0.3 * a("avoidance")
		"grievance":
			return 1.0 + 0.5 * a("suspicious") + 0.3 * a("abandonment") + 0.3 * a("grandiosity")
		"self_critical":
			return 1.0 + 0.4 * a("perfectionism") + 0.3 * a("avoidance")
	return 1.0


## Výběr akce: závislost a potřeba pozornosti víc ke svěřování, odstup méně.
func action_weight(act: Dictionary) -> float:
	if w.is_empty():
		return 1.0
	var id := String(act.get("id", ""))
	var m := 1.0
	if id == "confide":
		m *= 1.0 + 0.3 * a("dependency") + 0.15 * a("attention") - 0.35 * a("detachment") - 0.2 * a("suspicious")
	elif id == "apologize":
		m *= 1.0 - 0.3 * a("grandiosity") + 0.2 * a("abandonment")
	return clampf(m, 0.5, 1.6)


func mood_entries(social_need: float) -> Array:
	var out: Array = []
	if a("attention") > 0.2 and social_need < 35.0:
		out.append({"id": "acc_pozornost", "label": "Nikdo si mě nevšímá", "emotion": "smutny",
			"strength": -6.0 * a("attention"), "remaining": -1.0})
	if a("dependency") > 0.2 and social_need < 30.0:
		out.append({"id": "acc_sam", "label": "Bez ostatních jsem ztracený/á", "emotion": "uzkostny",
			"strength": -6.0 * a("dependency"), "remaining": -1.0})
	return out


## Soukromé výkladové názvy – jen když je hráč výslovně zapnul (mind.accent_labels).
func labels() -> PackedStringArray:
	var out := PackedStringArray()
	if not show_labels:
		return out
	for row in LABELS:
		if a(String(row[0])) >= float(row[1]):
			out.append(String(row[2]))
	return out


func private_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var l := labels()
	if not l.is_empty():
		out.append("Výklad osobnosti (soukromý, ne diagnóza): " + ", ".join(l) + ".")
	return out
