extends SceneTree
## H3 independent headless test: two real frame-ticked intermediate
## idle->walk poses versus pure endpoints, preview/live skeleton parity.
const Preview = preload("res://scripts/ui/character_preview.gd")
const Visual = preload("res://scripts/sim/sim_visual.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL ", label)

func hand(v: Node3D) -> Vector3:
    var sk: Skeleton3D = v._skeleton()
    return sk.get_bone_global_pose(sk.find_bone("hand_l")).origin

func _init() -> void:
    call_deferred("run")

func run() -> void:
    Assets.enabled = true
    var p = Preview.new()
    root.add_child(p)
    var v = Visual.new()
    root.add_child(v)
    var pa: AnimationPlayer = p.visual.get("_anim")
    var va: AnimationPlayer = v.get("_anim")
    if pa == null or va == null:
        print("FAIL missing AnimationPlayer")
        quit(2)
        return
    check(p.visual.uses_model() and v.uses_model(), "independent authored 3D models")
    var old_visual_mode: int = p.visual.process_mode
    var old_pa_mode: int = pa.process_mode
    var old_va_mode: int = va.process_mode
    check(old_visual_mode == Node.PROCESS_MODE_DISABLED, "draft normally frozen")
    # Tick the entire visual, not only its AnimationPlayer: otherwise
    # skeleton poses can be stale while the clock advances.
    p.visual.process_mode = Node.PROCESS_MODE_ALWAYS
    pa.process_mode = Node.PROCESS_MODE_ALWAYS
    va.process_mode = Node.PROCESS_MODE_ALWAYS
    pa.play("idle", 0.0)
    va.play("idle", 0.0)
    for i in 5:
        await process_frame
    var idle: Vector3 = hand(v)
    check(va.current_animation_position > 0.0 and
        absf(va.current_animation_position-pa.current_animation_position) < 0.005,
        "real idle clocks advanced together")
    check(hand(p.visual).distance_to(idle) < 0.001, "idle skeleton parity")
    pa.play("walk", 0.25)
    va.play("walk", 0.25)
    var samples: Array[Dictionary] = []
    for ticks in [3, 4]:
        for i in ticks:
            await process_frame
        var t: float = va.current_animation_position
        var h: Vector3 = hand(v)
        var draft_h: Vector3 = hand(p.visual)
        print("H3_BLEND_FRAME ", JSON.stringify({"t":t,
            "draft_t":pa.current_animation_position,
            "parity_m":h.distance_to(draft_h),
            "from_idle_m":h.distance_to(idle)}))
        check(t > 0.0 and t < 0.25 and
            absf(pa.current_animation_position-t) < 0.005,
            "sample is inside real 0.25s frame-ticked blend")
        check(h.distance_to(draft_h) < 0.001, "intermediate preview/live hand parity")
        samples.append({"t":t, "hand":h})
    var h0: Vector3 = samples[0]["hand"]
    var h1: Vector3 = samples[1]["hand"]
    check(float(samples[1]["t"]) > float(samples[0]["t"]) and
        h0.distance_to(h1) > 0.00001, "two distinct frame-ticked intermediate poses")
    pa.pause()
    va.pause()
    for sample in samples:
        var t: float = sample["t"]
        var blended: Vector3 = sample["hand"]
        va.play("walk", 0.0)
        va.seek(t, true)
        va.advance(0.0)
        var pure_walk: Vector3 = hand(v)
        var from_idle: float = blended.distance_to(idle)
        var from_walk: float = blended.distance_to(pure_walk)
        var endpoint: float = idle.distance_to(pure_walk)
        print("H3_BLEND_ENDPOINT ", JSON.stringify({"t":t,
            "from_idle_m":from_idle, "from_walk_m":from_walk,
            "pure_endpoints_m":endpoint}))
        check(from_idle > 0.00001 and from_walk > 0.00001 and
            from_idle < endpoint and from_walk < endpoint,
            "actual blend pose is distinct from both pure endpoints")
    p.visual.process_mode = old_visual_mode
    pa.process_mode = old_pa_mode
    va.process_mode = old_va_mode
    check(p.visual.process_mode == old_visual_mode and
        pa.process_mode == old_pa_mode and va.process_mode == old_va_mode,
        "draft and animation processing modes restored")
    p.queue_free()
    v.queue_free()
    await process_frame
    print("H3_BLEND_CLOCK_RESULT passed=",passed," failed=",failed)
    quit(0 if failed == 0 else 1)
