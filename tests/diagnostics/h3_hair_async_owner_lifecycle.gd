extends "res://tests/test_base.gd"
## Isolated test-only HairRig async lifecycle: live owner versus disposed owner.
## No network, private character data, or disk I/O from callbacks.
const HairRig = preload("res://scripts/assets/hair_rig.gd")

class ProbeOwner:
	extends Node3D
	var tag := ""
	var reporter: Node
	var mesh_instance: MeshInstance3D

	func _ready() -> void:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)

	func _on_hair_mesh_ready(part: String, style: String) -> void:
		if reporter != null and is_instance_valid(reporter):
			reporter.call("_record_callback", tag, part, style)
		var result: Dictionary = load("res://scripts/assets/hair_rig.gd").request_mesh(part, style, self)
		if mesh_instance != null and bool(result.get("ready", false)):
			mesh_instance.mesh = result.get("mesh")
			mesh_instance.visible = true

var _callbacks: Dictionary = {}
var _events: Array = []

func _record_callback(tag: String, part: String, style: String) -> void:
	_callbacks[tag] = int(_callbacks.get(tag, 0)) + 1
	_events.append({"owner": tag, "part": part, "style": style, "ms": Time.get_ticks_msec()})

func _ready() -> void:
	watchdog_seconds = 105.0
	_run.call_deferred()

func _run() -> void:
	section("H3 HairRig async owner lifecycle: isolated, bounded, test-only")
	var old_async: bool = HairRig.async_build
	HairRig.async_build = true
	HairRig.clear_cache() # Isolated fresh test process: no tasks exist yet.
	var ctx: Dictionary = HairRig.context()
	if not check(not ctx.is_empty(), "source/context available"):
		HairRig.async_build = old_async
		finish("h3_hair_async_owner_lifecycle")
		return

	var live := ProbeOwner.new()
	live.tag = "live"
	live.reporter = self
	add_child(live)
	var started_live := Time.get_ticks_msec()
	var live_request: Dictionary = HairRig.request_mesh("scalp", "kratke", live)
	check(not bool(live_request.get("ready", true)), "cold live owner request queued")
	var live_done: bool = await wait_until(func(): return int(_callbacks.get("live", 0)) > 0 and not HairRig.is_pending("scalp", "kratke"), 42.0)
	check(live_done, "live owner callback completed before 42s")
	if live_done:
		check(int(_callbacks.get("live", 0)) == 1, "live owner received exactly one callback")
		check(live.mesh_instance.mesh != null and live.mesh_instance.visible, "live owner has assigned visible mesh")
		check(HairRig.mesh_for("scalp", "kratke") == live.mesh_instance.mesh, "live mesh equals shared cache")
	var live_elapsed := Time.get_ticks_msec() - started_live

	var disposed := ProbeOwner.new()
	disposed.tag = "disposed"
	disposed.reporter = self
	add_child(disposed)
	var disposed_ref: WeakRef = weakref(disposed)
	var started_disposed := Time.get_ticks_msec()
	var disposed_request: Dictionary = HairRig.request_mesh("scalp", "dlouhe_vlnite", disposed)
	var was_pending: bool = HairRig.is_pending("scalp", "dlouhe_vlnite")
	check(not bool(disposed_request.get("ready", true)) and was_pending, "cold disposed owner request queued")
	disposed.queue_free()
	await get_tree().process_frame
	check(disposed_ref.get_ref() == null, "disposed owner actually freed")
	var disposed_done: bool = await wait_until(func(): return not HairRig.is_pending("scalp", "dlouhe_vlnite"), 42.0)
	check(disposed_done, "disposed-owner background task settles before 42s")
	if disposed_done:
		check(HairRig.mesh_for("scalp", "dlouhe_vlnite") != null, "result cached despite disposed owner")
		check(int(_callbacks.get("disposed", 0)) == 0, "no callback delivered to disposed owner")
	var disposed_elapsed := Time.get_ticks_msec() - started_disposed

	print("H3_HAIR_OWNER_LIFECYCLE ", JSON.stringify({"live_done": live_done, "live_ms": live_elapsed, "disposed_done": disposed_done, "disposed_ms": disposed_elapsed, "disposed_freed": disposed_ref.get_ref() == null, "callback_counts": _callbacks, "events": _events, "no_timeout": live_done and disposed_done}))
	# No cache clearing while a task may still be running.
	HairRig.async_build = old_async
	finish("h3_hair_async_owner_lifecycle")
