extends RefCounted
## Nálada a emoce postavy.
## Celková nálada = potřeby + dočasné „moodlety“ (vzpomínky na zážitky) + povaha.
## Dominantní emoce navíc mění, po čem postava touží (emoce řídí chování, ne jen ikonku).

const Traits := preload("res://scripts/sim/traits.gd")

const EMOTIONS := {
	"spokojeny": {"label": "V pohodě", "color": Color(0.55, 0.85, 0.55)},
	"stastny": {"label": "Šťastný", "color": Color(0.35, 0.95, 0.4)},
	"energicky": {"label": "Plný energie", "color": Color(1.0, 0.65, 0.2)},
	"soustredeny": {"label": "Soustředěný", "color": Color(0.4, 0.6, 1.0)},
	"napjaty": {"label": "Napjatý", "color": Color(0.95, 0.85, 0.25)},
	"smutny": {"label": "Smutný", "color": Color(0.35, 0.45, 0.9)},
	"nastvany": {"label": "Naštvaný", "color": Color(0.95, 0.2, 0.2)},
	"znudeny": {"label": "Znuděný", "color": Color(0.6, 0.6, 0.6)},
	"unaveny": {"label": "Unavený", "color": Color(0.55, 0.45, 0.7)},
	"nesvuj": {"label": "Nesvůj", "color": Color(0.8, 0.55, 0.3)},
	"uzkostny": {"label": "Úzkostný", "color": Color(0.62, 0.5, 0.78)},
	"sklesly": {"label": "Sklíčený", "color": Color(0.42, 0.46, 0.55)},
}

## Jak emoce mění chuť na typy akcí.
const EMOTION_TAG_AFFINITY := {
	"energicky": {"exercise": 1.6, "fun": 1.2, "rest": 0.7},
	"napjaty": {"rest": 1.4, "quiet": 1.3, "social": 0.85, "coping": 1.25},
	"smutny": {"social": 1.45, "food": 1.15, "exercise": 0.7, "repair": 1.1},
	"znudeny": {"fun": 1.5, "social": 1.2},
	"unaveny": {"sleep": 1.5, "rest": 1.3, "exercise": 0.3},
	"soustredeny": {"reading": 1.4},
	"stastny": {"social": 1.2, "fun": 1.1},
	"nastvany": {"exercise": 1.4, "social": 0.6, "quiet": 1.2, "repair": 0.3},
	# Úzkost táhne k uklidnění a stažení se; sociální akce jsou náročnější (ne zakázané).
	"uzkostny": {"coping": 1.5, "quiet": 1.3, "social": 0.7, "fun": 0.8},
	# Sklíčenost: táhne k odpočinku a stažení; nic není zakázané, jen „těžší“.
	"sklesly": {"rest": 1.3, "sleep": 1.15, "social": 0.8, "exercise": 0.6, "fun": 0.9, "coping": 1.1},
}

## Aktivní moodlety: {id, label, emotion, strength, remaining}
var moodlets: Array = []
## Moodlety odvozené z aktuálního stavu potřeb (přepočítávají se každý krok).
var need_moodlets: Array = []
var value := 0.0  # -100 .. 100
var emotion := "spokojeny"


static func emotion_label(id: String) -> String:
	return String(EMOTIONS.get(id, {}).get("label", id))


static func emotion_color(id: String) -> Color:
	return EMOTIONS.get(id, {}).get("color", Color.WHITE)


static func emotion_tag_multiplier(emo: String, tag: String) -> float:
	var aff: Dictionary = EMOTION_TAG_AFFINITY.get(emo, {})
	return float(aff.get(tag, 1.0))


func add_moodlet(id: String, label: String, emo: String, strength: float, duration: float) -> void:
	for m in moodlets:
		if m["id"] == id:
			m["remaining"] = maxf(m["remaining"], duration)
			if absf(strength) > absf(m["strength"]):
				m["strength"] = strength
			return
	moodlets.append({"id": id, "label": label, "emotion": emo, "strength": strength, "remaining": duration})


func remove_moodlet(id: String) -> void:
	for i in range(moodlets.size() - 1, -1, -1):
		if moodlets[i]["id"] == id:
			moodlets.remove_at(i)


func has_moodlet(id: String) -> bool:
	for m in moodlets:
		if m["id"] == id:
			return true
	return false


func tick(minutes: float) -> void:
	for i in range(moodlets.size() - 1, -1, -1):
		moodlets[i]["remaining"] -= minutes
		if moodlets[i]["remaining"] <= 0.0:
			moodlets.remove_at(i)


## extra = moodlety z jiných systémů (duševní stav), přepočítávané každý krok.
func evaluate(needs, trait_ids: Variant, extra: Array = []) -> void:
	need_moodlets = _compute_need_moodlets(needs, trait_ids) + extra
	var neg_scale := Traits.negative_scale(trait_ids)
	var total: float = (needs.average() - 55.0) * 0.5 + Traits.mood_bias(trait_ids)
	var per_emotion := {}
	for m in moodlets + need_moodlets:
		var s: float = m["strength"]
		if s < 0.0:
			s *= neg_scale
		total += s
		per_emotion[m["emotion"]] = float(per_emotion.get(m["emotion"], 0.0)) + absf(s)
	value = clampf(total, -100.0, 100.0)
	var best := ""
	var best_v := 9.0
	for e in per_emotion:
		if per_emotion[e] > best_v:
			best_v = per_emotion[e]
			best = e
	if best == "":
		best = "stastny" if value > 35.0 else "spokojeny"
	emotion = best


func all_moodlets() -> Array:
	return moodlets + need_moodlets


func _compute_need_moodlets(needs, trait_ids: Variant) -> Array:
	var out: Array = []
	var v: Dictionary = needs.values
	if v["hunger"] < 20.0:
		out.append(_nm("hlad", "Hladový", "nesvuj", -16.0))
	if v["energy"] < 20.0:
		out.append(_nm("unava", "Vyčerpaný", "unaveny", -18.0))
	if v["hygiene"] < 20.0:
		out.append(_nm("spina", "Špinavý", "nesvuj", -12.0))
	elif v["hygiene"] < Traits.get_param(trait_ids, "hygiene_threshold", -1.0):
		out.append(_nm("necisty", "Necítí se čistý", "napjaty", -12.0))
	if v["fun"] < 20.0:
		out.append(_nm("nuda", "Nuda", "znudeny", -14.0))
	if v["social"] < 20.0:
		out.append(_nm("samota", "Osamělý", "smutny", -14.0))
	elif v["social"] < Traits.get_param(trait_ids, "social_threshold", -1.0):
		out.append(_nm("chybi_lidi", "Chybí mu lidi", "smutny", -9.0))
	if v["comfort"] < 20.0:
		out.append(_nm("nepohodli", "Nepohodlí", "nesvuj", -8.0))
	var all_good := true
	for k in v:
		if v[k] < 75.0:
			all_good = false
			break
	if all_good:
		out.append(_nm("vse_ok", "Všechno je v pořádku", "stastny", 12.0))
	return out


func _nm(id: String, label: String, emo: String, strength: float) -> Dictionary:
	return {"id": id, "label": label, "emotion": emo, "strength": strength, "remaining": -1.0}


func to_dict() -> Dictionary:
	return {"moodlets": moodlets.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	moodlets = d.get("moodlets", []).duplicate(true)
