extends RefCounted
## Independent vigilance system. Not FCCS, not sensory loudness sensitivity.
## "hypervigilance" = persistent scanning / duration of alertness;
## "threat_sensitivity" = how an ambiguous cue is interpreted;
## "social_threat" = expectation of negative judgement or rejection.
## All values 0..1, no diagnosis, no forced player actions.

var hypervigilance := 0.5
var threat_sensitivity := 0.5
var social_threat := 0.5
var alertness := 0.25

func baseline() -> float:
	return 0.1 + 0.3 * hypervigilance

## Reconfigure from private, validated psyche D. Live edits retain the current
## state; first spawn starts at each character's own baseline.
func configure(d: Dictionary, reset := true) -> void:
	hypervigilance = clampf(float(d.get("hypervigilance", 0.5)), 0.0, 1.0)
	threat_sensitivity = clampf(float(d.get("threat_sensitivity", 0.5)), 0.0, 1.0)
	social_threat = clampf(float(d.get("social_threat", 0.5)), 0.0, 1.0)
	if reset:
		alertness = baseline()

## Perception/attention, NOT whether the event is objectively dangerous.
func notice_probability(salience: float) -> float:
	return clampf(0.25 + 0.48 * hypervigilance + 0.25 * clampf(salience, 0.0, 1.0), 0.0, 1.0)

## Event-specific appraisal. Explicit rejection is separate from ambiguous social cues.
func appraisal(kind: String, ambiguity: float = 0.0) -> float:
	var social := kind in ["argument", "insulted", "rejection", "unclear_reply"]
	var interpretation := 0.3 + 0.35 * threat_sensitivity
	if social:
		interpretation += 0.25 * (social_threat - 0.5)
	if kind == "rejection" or kind == "insulted":
		interpretation += 0.1 # Actual adverse experience, not just a guess.
	interpretation += clampf(ambiguity, 0.0, 1.0) * 0.2 * threat_sensitivity
	return clampf(interpretation, 0.05, 0.95)

## Returns an extra, bounded threat impulse for the existing mental state.
## Neutral/old hypervigilance (0.5) adds no extra threat = legacy stable.
## Safe contact lowers vigilance but does not force the character to trust anyone.
func observe(kind: String, salience: float = 1.0, ambiguity: float = 0.0) -> float:
	if kind == "safe_social":
		alertness = maxf(baseline(), alertness - 0.07 * clampf(salience, 0.0, 1.0))
		return 0.0
	var intensity := clampf(salience, 0.0, 1.0)
	if intensity <= 0.0:
		return 0.0
	var perceived := intensity * notice_probability(intensity) * appraisal(kind, ambiguity)
	var rise := perceived * (0.12 + 0.26 * hypervigilance)
	alertness = clampf(alertness + rise, baseline(), 1.0)
	return clampf(rise * maxf(hypervigilance - 0.5, 0.0) * 0.45, 0.0, 0.08)

## Rest/safety eventually restore individual baseline; vigilant characters
## settle more slowly. No indefinite stress accumulation from simply being awake.
func tick(minutes: float, sleeping := false, supportive := false) -> void:
	if minutes <= 0.0:
		return
	var tau := lerpf(25.0, 175.0, hypervigilance)
	if sleeping:
		tau *= 0.55
	if supportive:
		tau *= 0.7
	alertness = baseline() + (alertness - baseline()) * exp(-minutes / tau)

func to_dict() -> Dictionary:
	return {"hypervigilance": hypervigilance, "threat_sensitivity": threat_sensitivity,
		"social_threat": social_threat, "alertness": alertness}
