extends RefCounted
## Potíže s jídlem a vztahem k tělu (psychika G, 27. 10. 2026) – VÝHRADNĚ přes emoce, myšlenky a následky.
##
## Přísná pravidla obsahu: žádná čísla (kalorie, váha, BMI, doby omezování), žádné metody ani návody,
## žádná akce „nejíst“ ani odměna za ni. Nejde vybrat při tvorbě postavy (žádná predispozice ani
## posuvník) – stav jen vzniká z dat a jen se zapnutým citlivým obsahem (sh_ed, výchozí vypnuto) a plnými
## tématy duševního zdraví:
##   body_image   – tíseň z vlastního těla 0..1 (z vnitřního přesvědčení o vlastní nedostatečnosti,
##                  perfekcionismu, srovnávání s druhými a odmítnutí; tlumí ji opora a čas)
##   food_anxiety – úzkost kolem jídla 0..1 (z tísně a stresu)
## Následky: vyhýbání se společnému jídlu (jídlo před ostatními méně láká – hlad má vždy přednost),
## výčitky po jídle, méně energie, napětí ve vztazích (blízcí mají obavu). Cesta ven: svěřit se,
## opora, vyhledat pomoc, nižší stres a čas.

var body_image := 0.0
var food_anxiety := 0.0
var _last_meal_guilt := -1.0e9


func active() -> bool:
	return body_image > 0.0 or food_anxiety > 0.0


## Krok. ctx: allow (opt-in + full), self_belief, perfectionism, envy (0..100), rejection (0..1), stress, support.
func tick(dm: float, ctx: Dictionary) -> void:
	if dm <= 0.0:
		return
	if not bool(ctx.get("allow", false)):
		body_image = 0.0
		food_anxiety = 0.0
		return
	var src := 0.5 * float(ctx.get("self_belief", 0.0)) + 0.35 * float(ctx.get("perfectionism", 0.0)) \
		+ 0.25 * clampf(float(ctx.get("envy", 0.0)) / 60.0, 0.0, 1.0) + 0.2 * float(ctx.get("rejection", 0.0))
	var support := clampf(float(ctx.get("support", 0.0)), 0.0, 1.0)
	var tgt := clampf(src * (0.7 + float(ctx.get("stress", 15.0)) / 200.0) * (1.0 - 0.6 * support), 0.0, 1.0)
	var tau := 4320.0 if tgt > body_image else 2880.0
	body_image += (tgt - body_image) * (1.0 - exp(-dm / tau))
	var ft := clampf(body_image * (0.6 + float(ctx.get("stress", 15.0)) / 150.0), 0.0, 1.0)
	food_anxiety += (ft - food_anxiety) * (1.0 - exp(-dm / 1440.0))
	# Bez zdroje stav doozní úplně (žádný trvalý zbytek), roste-li, nic se neořezává.
	if tgt < 0.01 and body_image < 0.01:
		body_image = 0.0
	if ft < 0.01 and food_anxiety < 0.01:
		food_anxiety = 0.0


## Jídlo před ostatními láká méně (vyhýbání se společnému jídlu). Kritický hlad tuto váhu ruší.
func food_weight(others_near: int, hunger: float) -> float:
	if food_anxiety <= 0.0 or others_near <= 0 or hunger < 25.0:
		return 1.0
	return clampf(1.0 - 0.35 * food_anxiety, 0.6, 1.0)


## Po jídle: výčitky (emoce), ne číslo. Vrací sílu moodletu (≤ 0) nebo 0.
func after_meal(now: float) -> float:
	if food_anxiety < 0.2 or now - _last_meal_guilt < 240.0:
		return 0.0
	_last_meal_guilt = now
	return -lerpf(3.0, 8.0, clampf(food_anxiety, 0.0, 1.0))


func energy_mult() -> float:
	return 1.0 + 0.1 * food_anxiety


## Opora (svěření, pomoc) uleví.
func on_support(amount: float) -> void:
	body_image = maxf(body_image - 0.12 * amount, 0.0)
	food_anxiety = maxf(food_anxiety - 0.1 * amount, 0.0)


func help_need() -> float:
	return clampf(body_image - 0.5, 0.0, 1.0)


func mood_entries() -> Array:
	var out: Array = []
	if body_image > 0.35:
		out.append({"id": "ed_telo", "label": "Necítím se dobře ve svém těle", "emotion": "smutny",
			"strength": -lerpf(3.0, 10.0, clampf((body_image - 0.35) / 0.65, 0.0, 1.0)), "remaining": -1.0})
	return out


## Soukromé věty jen pro vlastníka offline (bez čísel, bez metod), vždy s nabídkou opory.
func private_lines(crisis_lines: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if body_image > 0.35 or food_anxiety > 0.35:
		out.append("Jídlo a vlastní tělo jsou teď těžké téma. Pomáhá svěřit se někomu blízkému nebo vyhledat odbornou pomoc.")
		if body_image > 0.6:
			for line in crisis_lines:
				if typeof(line) == TYPE_ARRAY and line.size() >= 2:
					out.append("%s: %s" % [String(line[0]), String(line[1])])
	return out


func to_dict() -> Dictionary:
	return {"body_image": body_image, "food_anxiety": food_anxiety, "last_meal_guilt": _last_meal_guilt}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 4:
		return false
	for key in d:
		if not ["body_image", "food_anxiety", "last_meal_guilt"].has(key):
			return false
	for key in ["body_image", "food_anxiety"]:
		if d.has(key) and (typeof(d[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d[key])) or float(d[key]) < 0.0 or float(d[key]) > 1.0):
			return false
	if d.has("last_meal_guilt") and (typeof(d["last_meal_guilt"]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(d["last_meal_guilt"]))):
		return false
	return true


func from_dict(d: Variant) -> void:
	if not validate_snapshot(d):
		return
	body_image = float(d.get("body_image", 0.0))
	food_anxiety = float(d.get("food_anxiety", 0.0))
	_last_meal_guilt = float(d.get("last_meal_guilt", -1.0e9))
