extends RefCounted
## Non-graphic, private response to actual or perceived interpersonal rejection.
## Independent of hypervigilance (attention) and social_threat (expectation).
## Never generates self-harm actions, methods, achievements or rewards.
## A concern flag exists only when the adult-only sensitive-topic setting opts in.

var reactivity := 0.5
var distress := 0.0
var recent_cues := 0.0
var concern := false

func configure(d: Dictionary, reset := true) -> void:
	reactivity = clampf(float(d.get("rejection_reactivity", 0.5)), 0.0, 1.0)
	if reset:
		distress = 0.0
		recent_cues = 0.0
		concern = false

## A real rejection differs from a perceived one. The latter is an appraisal,
## not a statement about what the other person actually meant.
## importance (0..1): interpersonal significance. Interpretation is taken from
## the separate threat/expectation system, not dictated by emotional reactivity.
func on_cue(kind: String, importance: float, interpretation: float,
		support: float = 0.0, regulation: float = 0.5) -> Dictionary:
	if kind not in ["real", "perceived", "dismissed"]:
		return {"distress_added": 0.0, "stress": 0.0, "arousal": 0.0, "support_needed": needs_support()}
	var close := clampf(importance, 0.0, 1.0)
	var certainty := clampf(interpretation, 0.0, 1.0)
	var sup := clampf(support, 0.0, 1.0)
	var reg := clampf(regulation, 0.0, 1.0)
	var cue := 1.0 if kind == "real" else (0.75 if kind == "dismissed" else 0.5)
	# Keep strong and mild reactions possible without predetermining behaviour.
	var impact := cue * (0.04 + 0.26 * reactivity) * (0.12 + 0.88 * close)
	impact *= (0.55 + 0.45 * certainty) * (1.0 - 0.35 * sup) * (1.15 - 0.3 * reg)
	# Repeated very rapid cues cannot be used to farm a crisis or spiral without limit.
	impact *= 1.0 / (1.0 + 0.35 * recent_cues)
	var old := distress
	distress = clampf(distress + impact * (1.0 - 0.2 * distress), 0.0, 1.0)
	recent_cues = minf(recent_cues + 1.0, 5.0)
	var inc := distress - old
	return {"distress_added": inc, "stress": minf(inc * 9.0, 3.0),
		"arousal": minf(inc * 18.0, 6.0), "support_needed": needs_support()}

func needs_support() -> bool:
	return distress >= 0.42

## Explicitly NOT a diagnosis, prediction or probability. A private contextual
## care flag can be raised when prolonged distress coexists with serious strain;
## it does not enact injury or force the player into anything.
func update_concern(stress: float, regulation: float, support: float, allow_sensitive: bool) -> void:
	if not allow_sensitive:
		concern = false
		return
	if concern:
		concern = distress >= 0.52 and stress > 45.0 and support < 0.5
	else:
		concern = distress >= 0.68 and stress >= 60.0 and regulation < 0.45 and support < 0.25

## No spontaneous growth in a quiet setting. Sleep and social support aid recovery.
func tick(minutes: float, sleeping := false, support: float = 0.0,
		stress: float = 0.0, regulation: float = 0.5, allow_sensitive := false) -> void:
	if minutes > 0.0:
		var tau := lerpf(90.0, 280.0, reactivity)
		if sleeping:
			tau *= 0.65
		tau *= lerpf(1.0, 0.6, clampf(support, 0.0, 1.0))
		distress *= exp(-minutes / tau)
		recent_cues *= exp(-minutes / 150.0)
	update_concern(stress, regulation, support, allow_sensitive)

## Server/private-only: no numerical self-harm score in HUD or public spawn state.
func private_status(allow_sensitive: bool = false) -> Dictionary:
	var label := "klid"
	if distress >= 0.42:
		label = "potřebuje oporu"
	elif distress >= 0.15:
		label = "zasažené vztahy"
	var d := {"state": label, "support_needed": needs_support()}
	if allow_sensitive:
		d["safety_concern"] = concern
	return d

func to_dict() -> Dictionary:
	return {"reactivity": reactivity, "distress": distress, "recent_cues": recent_cues, "concern": concern}
