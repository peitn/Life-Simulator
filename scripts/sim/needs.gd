extends RefCounted
## Potřeby postavy. 100 = plně uspokojeno, 0 = kritický stav.

const KEYS: Array[String] = ["hunger", "energy", "hygiene", "fun", "social", "comfort"]
const LABELS := {
	"hunger": "Hlad",
	"energy": "Energie",
	"hygiene": "Hygiena",
	"fun": "Zábava",
	"social": "Společnost",
	"comfort": "Pohodlí",
}
## Základní úbytek za herní hodinu (hlad z plna na nulu za ~15 h, energie ~20 h).
const DECAY_PER_HOUR := {
	"hunger": 6.5,
	"energy": 5.0,
	"hygiene": 4.2,
	"fun": 5.8,
	"social": 4.0,
	"comfort": 3.6,
}
## Váha potřeby při rozhodování (hlad a energie jsou pro přežití důležitější).
const WEIGHTS := {
	"hunger": 1.35,
	"energy": 1.3,
	"hygiene": 1.0,
	"fun": 0.9,
	"social": 0.85,
	"comfort": 0.7,
}

var values := {}
## Násobiče úbytku (z osobnostních rysů, později z věku, nemoci…).
var decay_mult := {}


func _init(rng: RandomNumberGenerator = null) -> void:
	for k in KEYS:
		var jitter := rng.randf_range(-15.0, 20.0) if rng != null else 0.0
		values[k] = clampf(70.0 + jitter, 0.0, 100.0)
		decay_mult[k] = 1.0


## `suppress`: potřeba -> faktor úbytku během aktuální akce (0 = neubývá, >1 rychleji).
func tick(minutes: float, suppress: Dictionary = {}) -> void:
	for k in KEYS:
		var f: float = float(suppress.get(k, 1.0))
		var loss: float = DECAY_PER_HOUR[k] * decay_mult[k] * f * minutes / 60.0
		values[k] = clampf(values[k] - loss, 0.0, 100.0)


func add(k: String, amount: float) -> void:
	if values.has(k):
		values[k] = clampf(values[k] + amount, 0.0, 100.0)


func get_value(k: String) -> float:
	return float(values.get(k, 0.0))


func lowest() -> String:
	var best := KEYS[0]
	for k in KEYS:
		if values[k] < values[best]:
			best = k
	return best


func average() -> float:
	var s := 0.0
	for k in KEYS:
		s += values[k]
	return s / KEYS.size()


## Naléhavost potřeby – kvadratická křivka: nízké hodnoty jsou mnohem naléhavější.
static func urgency(v: float) -> float:
	var x := clampf((100.0 - v) / 100.0, 0.0, 1.0)
	return x * x * 100.0


func to_dict() -> Dictionary:
	return {"values": values.duplicate(), "decay_mult": decay_mult.duplicate()}


func from_dict(d: Dictionary) -> void:
	for k in KEYS:
		values[k] = float(d.get("values", {}).get(k, values[k]))
		decay_mult[k] = float(d.get("decay_mult", {}).get(k, decay_mult[k]))
