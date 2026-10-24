extends "res://tests/test_base.gd"
## Attachments are directional and distinct from relationship quality.
## The opt-in implied SH presentation is not an action and reveals no methods.
const Ledger := preload("res://scripts/sim/rel_ledger.gd")
const Agent := preload("res://scripts/sim/sim_agent.gd")
const Mask := preload("res://scripts/sim/sensitive_privacy_mask.gd")
const Rejection := preload("res://scripts/sim/rejection_response.gd")
const Actions := preload("res://scripts/sim/action_library.gd")

class FakeNet:
	extends Node
	var networked := false
	func is_networked() -> bool:
		return networked

class FakeHud:
	extends Node
	var notifications: Array = []
	func show_notice(value: String) -> void:
		notifications.append(value)

class FakeWorld:
	extends Node3D
	var net: Node
	var hud: Node

func _ready() -> void:
	section("Independent attachment and dependency by person")
	var bonds := Ledger.new()
	var indifferent: Dictionary = bonds.attachment_to("Alex", 0.0)
	var liked: Dictionary = bonds.attachment_to("Alex", 90.0)
	check(float(indifferent["impact"]) < float(liked["impact"]), "Closeness increases default importance")
	check(float(liked["dependency"]) == 0.0, "High liking alone does not create emotional dependency")
	check(bonds.set_attachment("Alex", 1.0, 0.0), "Explicit strong attachment without dependency")
	var independent: Dictionary = bonds.attachment_to("Alex", -70.0)
	check(float(independent["importance"]) == 1.0 and float(independent["dependency"]) == 0.0, "Attachment can exist without positive relationship")
	check(bonds.set_attachment("Alex", 0.65, 0.95), "Separate high dependency per specific person")
	var dependent: Dictionary = bonds.attachment_to("Alex", -70.0)
	check(float(dependent["impact"]) > 0.9 and String(bonds.attachment_label("Alex", -70.0)).contains("emoční závislost"), "Ambivalent/negative relationship can have emotional dependency")
	check(not bonds.set_attachment("Alex", INF, 0.3), "Non-finite dependency input rejected")
	check(not bonds.set_attachment("Alex", 0.1, 1.3), "Out-of-range dependence rejected")
	check(not bonds.set_attachment("", 0.5, 0.2), "Empty target rejected")
	check(float(bonds.attachment_to("Robin", 0.0)["dependency"]) == 0.0, "One bond does not affect another")
	var restored := Ledger.new()
	restored.from_dict(bonds.to_dict())
	check(restored.attachment_to("Alex", 0.0) == bonds.attachment_to("Alex", 0.0), "Per-person attachment persists in legacy ledger storage")
	restored.from_dict({"grudges": {"Alex": 4.0}})
	check(float(restored.attachment_to("Alex", 50.0)["dependency"]) == 0.0, "Legacy saves missing attachment data remain valid")
	section("Rejection response depends on this particular bond")
	var relationship_based := Rejection.new()
	relationship_based.configure({"rejection_reactivity": 0.85})
	var small: Dictionary = relationship_based.on_cue("real", float(indifferent["impact"]), 0.8)
	relationship_based.configure({"rejection_reactivity": 0.85})
	var large: Dictionary = relationship_based.on_cue("real", float(dependent["impact"]), 0.8)
	check(float(large["distress_added"]) > float(small["distress_added"]) * 2.0, "Same rejection affects important/dependent person more")
	check(float(large["distress_added"]) < 1.0, "Strong attachment does not guarantee extreme emotional outcome")
	section("Simulation wires particular partner to emotional response")
	var world := FakeWorld.new()
	var server := FakeNet.new()
	var hud := FakeHud.new()
	world.net = server
	world.hud = hud
	add_child(world)
	world.add_child(server)
	world.add_child(hud)
	var actor := Node3D.new()
	actor.set_script(Agent)
	actor.setup("Alex", "m", [], Color.WHITE, 71, world)
	world.add_child(actor)
	var partner := Node3D.new()
	partner.set_script(Agent)
	partner.setup("Robin", "n", [], Color.WHITE, 72, world)
	world.add_child(partner)
	actor.relationships["Robin"] = 75.0
	check(actor.set_attachment_to("Robin", 0.0, 0.0), "Server-side bond override possible")
	var response_low: Dictionary = actor._on_rejection_cue("real", partner)
	actor.rejection.configure({"rejection_reactivity": actor.rejection.reactivity}, true)
	check(actor.set_attachment_to("Robin", 1.0, 0.95), "Server-side dependency can differ from liking")
	var response_high: Dictionary = actor._on_rejection_cue("real", partner)
	check(float(response_high["distress_added"]) > float(response_low["distress_added"]), "Real runtime rejection respects attachment")
	check(actor.private_attachment_labels().has("Robin"), "Attachment is available to private relationship view")
	check(not actor._build_detail().has("attachments"), "Attachment never sent in replicated net_detail")
	check(not actor._build_detail().has("sensitive_event"), "No private sensitive incident in network snapshot")
	section("Opt-in fully obscured, owner-only implied event presentation")
	var gs = get_node("/root/GameSettings")
	gs.persist = false
	var old_mode := String(gs.get_value("mental_health"))
	var old_sh := bool(gs.get_value("sh_ed_topics"))
	gs.set_value("mental_health", "full", false)
	gs.set_value("sh_ed_topics", false, false)
	check(not actor.present_implied_sensitive_incident(), "Non-consenting setting prevents display")
	gs.set_value("sh_ed_topics", true, false)
	gs.set_value("mental_health", "muted", false)
	check(not actor.present_implied_sensitive_incident(), "Muted mental-health mode prevents display")
	gs.set_value("mental_health", "full", false)
	server.networked = true
	check(not actor.present_implied_sensitive_incident(), "No private event broadcast into networked sessions")
	server.networked = false
	check(not Actions.get_action("self_harm").has("id"), "No playable/self-harm action exists")
	check(actor.present_implied_sensitive_incident(), "Offline opt-in presentation starts")
	var masker = actor._privacy_mask
	check(masker != null and masker.is_covering() and not actor.visual.visible, "Original visual completely hidden behind mosaic mask")
	check(not actor.present_implied_sensitive_incident(), "No stacked or repeated mask while active")
	check(masker._mosaic != null and masker._mosaic.visible, "Opaque mosaic is present")
	masker.end()
	check(actor.visual.visible and not masker.is_covering(), "Visible character restored when presentation ends")
	check(hud.notifications.size() == 1 and String(hud.notifications[0]).contains("sebepoškozování"), "Private HUD receives neutral post-event notification")
	check(not actor._build_detail().has("sensitive_event"), "Even after presentation nothing added to public state")
	gs.set_value("sh_ed_topics", old_sh, false)
	gs.set_value("mental_health", old_mode, false)
	world.queue_free()
	finish("test_attachment_sensitive_scene")
