extends RefCounted
## Private adult intimate drives/consent. Attraction, desire, arousal, and
## compulsive preoccupation are independent; no orientation is pathologized.
const CONSENT_MINUTES := 30.0
const PRESSURE_COOLDOWN := 4320.0
const MAX_PARTNERS := 24
const GROUPS := ["muzi", "zeny", "nebinarni"]
var age := 30
var asexual := false
var aromantic := false
var sexual_attraction: Array = [] # empty = unspecified, not "attracted to nobody"
var romantic_attraction: Array = []
var libido_baseline := 0.5
var drive_dysregulation := 0.0
var sexual_preoccupation := 0.0
var sexual_arousal := 0.0
var interest: Dictionary = {}
var pressure_until: Dictionary = {}
var refusal_until: Dictionary = {}
var last_intimacy := -1.0e12

func configure(profile: Dictionary) -> bool:
	var years: Variant = profile.get("age", 30)
	var drive: Variant = profile.get("libido", 0.5)
	var dys: Variant = profile.get("drive_dysregulation", 0.0)
	if typeof(years) not in [TYPE_INT,TYPE_FLOAT] or typeof(drive) not in [TYPE_INT,TYPE_FLOAT] or typeof(dys) not in [TYPE_INT,TYPE_FLOAT]:
		return false
	if not is_finite(float(years)) or not is_finite(float(drive)) or not is_finite(float(dys)):
		return false
	if int(years) < 18 or int(years) > 95 or float(drive) < 0.0 or float(drive) > 1.0 or float(dys) < 0.0 or float(dys) > 1.0:
		return false
	var sexual = profile.get("sexual_attraction", [])
	var romantic = profile.get("romantic_attraction", [])
	if typeof(sexual) != TYPE_ARRAY or typeof(romantic) != TYPE_ARRAY:
		return false
	for arr in [sexual, romantic]:
		if arr.size() > 3:
			return false
		for group in arr:
			if typeof(group) != TYPE_STRING or not GROUPS.has(group):
				return false
	if typeof(profile.get("asexual", false)) != TYPE_BOOL or typeof(profile.get("aromantic", false)) != TYPE_BOOL:
		return false
	age = int(years)
	libido_baseline = float(drive)
	drive_dysregulation = float(dys)
	asexual = bool(profile.get("asexual", false))
	aromantic = bool(profile.get("aromantic", false))
	sexual_attraction = sexual.duplicate(true)
	romantic_attraction = romantic.duplicate(true)
	return true

func tick(minutes: float, context: Dictionary = {}) -> void:
	if not is_finite(minutes) or minutes <= 0.0:
		return
	var dt := minf(minutes, 10080.0)
	var safety := _bound(context.get("safety", 0.65), 0.0, 1.0, 0.65)
	var stress := _bound(context.get("stress", 0.0), 0.0, 100.0, 0.0)
	var energy := _bound(context.get("energy", 80.0), 0.0, 100.0, 80.0)
	var target := clampf(libido_baseline * 21.0 * safety * (1.0 - 0.006 * stress) * (0.25 + 0.75 * energy / 100.0), 0.0, 24.0)
	sexual_arousal = clampf(target + (sexual_arousal - target) * exp(-dt / 160.0), 0.0, 100.0)
	var preoccupation_target := clampf(drive_dysregulation * (10.0 + 0.3 * stress), 0.0, 45.0)
	sexual_preoccupation = clampf(preoccupation_target + (sexual_preoccupation - preoccupation_target) * exp(-dt / 220.0), 0.0, 100.0)
	# Never initiate intimacy from arousal, dysregulation, or this tick.
	for k in interest.keys():
		if float(interest[k]) <= float(context.get("now", -1.0e12)):
			interest.erase(k)


static func _bound(raw: Variant, lo: float, hi: float, fallback: float) -> float:
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
		return fallback
	return clampf(float(raw), lo, hi)


func stimulus(amount: float) -> void:
	if is_finite(amount):
		sexual_arousal = clampf(sexual_arousal + clampf(amount, -100.0, 100.0), 0.0, 100.0)


static func valid_partner(who: String) -> bool:
	return not who.is_empty() and who.length() <= 64 and who == who.validate_node_name()


func is_under_pressure(who: String, now: float) -> bool:
	return is_finite(now) and now < float(pressure_until.get(who, -1.0e12))


func offer_consent(who: String, now: float, freely_wants: bool, able: bool) -> bool:
	if age < 18 or not valid_partner(who) or not is_finite(now) or not freely_wants or not able:
		return false
	if is_under_pressure(who, now) or now < float(refusal_until.get(who, -1.0e12)):
		return false
	if not interest.has(who) and interest.size() >= MAX_PARTNERS:
		return false
	interest[who] = now + CONSENT_MINUTES
	return true


func has_consent(who: String, now: float) -> bool:
	return age >= 18 and valid_partner(who) and is_finite(now) and not is_under_pressure(who, now) and now < float(interest.get(who, -1.0e12)) and now >= float(refusal_until.get(who, -1.0e12))


func mutual_consent(partner: Variant, my_id: String, partner_id: String, now: float, enabled: bool) -> bool:
	if not enabled or not partner is Object or partner == self or not partner.has_method("has_consent"):
		return false
	return age >= 18 and int(partner.get("age")) >= 18 and has_consent(partner_id, now) and partner.has_consent(my_id, now)


## Existing consent may cover an encounter once it has begun but stays
## revocable at every tick; extending DOES NOT create a new agreement.
func extend_started_encounter(who: String, now: float, duration: float) -> bool:
	if not has_consent(who, now) or not is_finite(duration) or duration <= 0.0 or duration > 90.0:
		return false
	interest[who] = maxf(float(interest[who]), now + duration + 2.0)
	return true


func revoke_consent(who: String) -> void:
	interest.erase(who)


func refuse(who: String, now: float) -> void:
	if not valid_partner(who) or not is_finite(now):
		return
	interest.erase(who)
	refusal_until[who] = now + 180.0


func pressure_from(who: String, now: float) -> void:
	if not valid_partner(who) or not is_finite(now):
		return
	interest.erase(who)
	pressure_until[who] = maxf(float(pressure_until.get(who, -1.0e12)), now + PRESSURE_COOLDOWN)


func complete(partner: Variant, my_id: String, partner_id: String, now: float, enabled: bool) -> bool:
	if not mutual_consent(partner, my_id, partner_id, now, enabled):
		return false
	interest.erase(partner_id)
	partner.revoke_consent(my_id)
	last_intimacy = now
	partner.set("last_intimacy", now)
	sexual_arousal = maxf(0.0, sexual_arousal - 22.0)
	partner.set("sexual_arousal", maxf(0.0, float(partner.get("sexual_arousal")) - 22.0))
	return true


func to_dict() -> Dictionary:
	return {"age": age, "asexual": asexual, "aromantic": aromantic,
		"sexual_attraction": sexual_attraction.duplicate(true), "romantic_attraction": romantic_attraction.duplicate(true),
		"libido": libido_baseline, "drive_dysregulation": drive_dysregulation,
		"sexual_preoccupation": sexual_preoccupation, "sexual_arousal": sexual_arousal,
		"interest": interest.duplicate(true), "pressure_until": pressure_until.duplicate(true),
		"refusal_until": refusal_until.duplicate(true), "last_intimacy": last_intimacy}


static func validate_snapshot(raw: Variant) -> bool:
	if typeof(raw) != TYPE_DICTIONARY or raw.size() != 13:
		return false
	if typeof(raw.get("age")) != TYPE_INT or int(raw["age"]) < 18 or int(raw["age"]) > 95:
		return false
	for k in ["libido", "drive_dysregulation", "sexual_preoccupation", "sexual_arousal", "last_intimacy"]:
		if typeof(raw.get(k)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw[k])):
			return false
	if not (float(raw["libido"]) >= 0 and float(raw["libido"]) <= 1 and float(raw["drive_dysregulation"]) >= 0 and float(raw["drive_dysregulation"]) <= 1):
		return false
	if not (float(raw["sexual_preoccupation"]) >= 0 and float(raw["sexual_preoccupation"]) <= 100 and float(raw["sexual_arousal"]) >= 0 and float(raw["sexual_arousal"]) <= 100):
		return false
	for k in ["asexual", "aromantic"]:
		if typeof(raw.get(k)) != TYPE_BOOL:
			return false
	for k in ["sexual_attraction", "romantic_attraction"]:
		if typeof(raw.get(k)) != TYPE_ARRAY or raw[k].size() > 3:
			return false
		for value in raw[k]:
			if typeof(value) != TYPE_STRING or not GROUPS.has(value):
				return false
	for k in ["interest", "pressure_until", "refusal_until"]:
		if typeof(raw.get(k)) != TYPE_DICTIONARY or raw[k].size() > MAX_PARTNERS:
			return false
		for who in raw[k]:
			if typeof(who) != TYPE_STRING or not valid_partner(who):
				return false
			if typeof(raw[k][who]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw[k][who])):
				return false
	return true


func from_dict(raw: Variant) -> bool:
	if not validate_snapshot(raw):
		return false
	age = int(raw["age"])
	asexual = bool(raw["asexual"])
	aromantic = bool(raw["aromantic"])
	sexual_attraction = raw["sexual_attraction"].duplicate(true)
	romantic_attraction = raw["romantic_attraction"].duplicate(true)
	libido_baseline = float(raw["libido"])
	drive_dysregulation = float(raw["drive_dysregulation"])
	sexual_preoccupation = float(raw["sexual_preoccupation"])
	sexual_arousal = float(raw["sexual_arousal"])
	interest = raw["interest"].duplicate(true)
	pressure_until = raw["pressure_until"].duplicate(true)
	refusal_until = raw["refusal_until"].duplicate(true)
	last_intimacy = float(raw["last_intimacy"])
	return true
