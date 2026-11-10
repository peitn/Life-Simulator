extends "res://tests/test_base.gd"
## H4b boundary regression only; not a restart/persistence integration test.
const Save := preload("res://scripts/save/game_save.gd")
class FakeNet:
    extends RefCounted
    var networked := false
    var authority := true
    func is_networked() -> bool:
        return networked
    func is_authority() -> bool:
        return authority
class FakeWorld:
    extends Node
    var net: FakeNet
func _ready() -> void:
    _run.call_deferred()
func _run() -> void:
    section("H4b offline serializer boundary")
    var world := FakeWorld.new()
    add_child(world)
    var missing := Save.capture(world)
    check(not missing.get("ok", true) and missing.get("reason") == "offline_only", "missing network context rejected")
    world.net = FakeNet.new()
    world.net.networked = true
    var networked := Save.capture(world)
    check(not networked.get("ok", true) and networked.get("reason") == "offline_only", "networked authority rejected")
    world.net.networked = false
    world.net.authority = false
    var client := Save.capture(world)
    check(not client.get("ok", true) and client.get("reason") == "offline_only", "non-authority rejected")
    world.queue_free()
    finish("H4b boundary")
