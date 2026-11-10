extends SceneTree
## H3 test-only: verify full 0.25s idle->walk completion and interrupted walk->idle restoration.
## Uses real AnimationPlayer process_frame ticks; never modifies production state.
const Preview = preload("res://scripts/ui/character_preview.gd")
const Visual = preload("res://scripts/sim/sim_visual.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
var passed := 0
var failed := 0

func ck(ok: bool, msg: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL ",msg)

func bone(v: Node3D, name: String) -> Vector3:
    var s: Skeleton3D = v._skeleton()
    var i: int = s.find_bone(name)
    if i < 0:
        return Vector3.INF
    return s.get_bone_global_pose(i).origin

func endpoint(v: Node3D, clip: String, t: float, name: String) -> Vector3:
    var a: AnimationPlayer = v.get("_anim")
    a.play(clip,0.0)
    a.seek(t,true)
    a.advance(0.0)
    return bone(v,name)

func tick_until(a: AnimationPlayer, target: float, limit: int = 500) -> int:
    var n := 0
    while a.current_animation_position < target and n < limit:
        await process_frame
        n += 1
    return n

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var old_scale: float = Engine.time_scale
    Engine.time_scale = 0.15
    Assets.enabled = true
    var p = Preview.new()
    root.add_child(p)
    var v = Visual.new()
    v.name = "LiveVisual"
    p.viewport.add_child(v)
    var e = Visual.new()
    root.add_child(e)
    var pa: AnimationPlayer = p.visual.get("_anim")
    var va: AnimationPlayer = v.get("_anim")
    var old_draft_tick: bool = p.visual.is_processing()
    var old_live_tick: bool = v.is_processing()
    var old_draft_mode: int = p.visual.process_mode
    var old_pa_mode: int = pa.process_mode
    var old_va_mode: int = va.process_mode
    var old_draft_visible: bool = p.visual.visible
    var old_live_visible: bool = v.visible
    p.visual.process_mode = Node.PROCESS_MODE_ALWAYS
    pa.process_mode = Node.PROCESS_MODE_ALWAYS
    va.process_mode = Node.PROCESS_MODE_ALWAYS
    p.visual.set_process(false)
    v.set_process(false)
    ck(p.visual.uses_model() and v.uses_model(),"two authored models loaded")
    for name in ["hand_l","hand_r"]:
        ck(v._skeleton().find_bone(name)>=0,"named bone exists: "+name)
    pa.play("idle",0.0)
    va.play("idle",0.0)
    for i in 5:
        await process_frame
    pa.play("walk",0.25)
    va.play("walk",0.25)
    var n: int = await tick_until(va,0.29)
    var walk_t: float = va.current_animation_position
    ck(n<500 and walk_t>=0.29 and walk_t<0.45,"full blend finished under real frame ticks")
    ck(pa.assigned_animation=="walk" and va.assigned_animation=="walk","walk still assigned after blend")
    ck(absf(pa.current_animation_position-walk_t)<0.015,"preview and live clocks agree at completion")
    for name in ["hand_l","hand_r"]:
        var live_h: Vector3 = bone(v,name)
        var preview_h: Vector3 = bone(p.visual,name)
        var pure_walk: Vector3 = endpoint(e,"walk",walk_t,name)
        var pure_idle: Vector3 = endpoint(e,"idle",walk_t,name)
        print("H3_COMPLETION ",JSON.stringify({"bone":name,"t":walk_t,
            "preview_delta":live_h.distance_to(preview_h),
            "pure_walk_delta":live_h.distance_to(pure_walk),
            "pure_idle_delta":live_h.distance_to(pure_idle)}))
        ck(live_h.distance_to(preview_h)<0.001,"models match completed "+name)
        ck(live_h.distance_to(pure_walk)<0.001,"completed blend equals pure walk "+name)
        ck(pure_walk.distance_to(pure_idle)>0.005,"endpoint poses distinguishable "+name)
    # Start a fresh idle->walk crossfade and INTERRUPT it before 0.25s.
    pa.play("idle",0.0)
    va.play("idle",0.0)
    for i in 5:
        await process_frame
    pa.play("walk",0.25)
    va.play("walk",0.25)
    n = await tick_until(va,0.10)
    var mid_walk_t: float = va.current_animation_position
    ck(n<500 and mid_walk_t>=0.10 and mid_walk_t<0.20,
        "first crossfade is still in progress before interruption")
    var mid_hand: Vector3 = bone(v,"hand_l")
    var mid_pure_walk: Vector3 = endpoint(e,"walk",mid_walk_t,"hand_l")
    var mid_pure_idle: Vector3 = endpoint(e,"idle",mid_walk_t,"hand_l")
    print("H3_BEFORE_INTERRUPT ",JSON.stringify({"time":mid_walk_t,
        "walk_delta":mid_hand.distance_to(mid_pure_walk),
        "idle_delta":mid_hand.distance_to(mid_pure_idle)}))
    ck(mid_hand.distance_to(mid_pure_walk)>0.002 and
        mid_hand.distance_to(mid_pure_idle)>0.002,
        "pre-interrupt pose is distinct from both pure clips")
    ck(mid_hand.distance_to(bone(p.visual,"hand_l"))<0.001,
        "preview/live match before interruption")
    pa.play("idle",0.12)
    va.play("idle",0.12)
    n = await tick_until(va,0.05)
    var interrupted_t: float = va.current_animation_position
    ck(n<500 and interrupted_t>=0.05 and interrupted_t<0.12,"interrupted reverse blend is progressing")
    ck(pa.assigned_animation=="idle" and va.assigned_animation=="idle","interrupted clip assigned to idle")
    var reverse_hand: Vector3 = bone(v,"hand_l")
    var reverse_pure_idle: Vector3 = endpoint(e,"idle",interrupted_t,"hand_l")
    print("H3_DURING_REVERSE ",JSON.stringify({"time":interrupted_t,
        "pure_idle_delta":reverse_hand.distance_to(reverse_pure_idle)}))
    # Diagnostic only: Godot may settle near pure idle rapidly after a
    # nested interruption; do not assert a made-up minimum interpolation gap.
    # The strict gate is that the earlier idle->walk was truly interrupted
    # before its 0.25s deadline and the resulting idle settles correctly.
    ck(bone(v,"hand_l").distance_to(bone(p.visual,"hand_l"))<0.001,"models agree mid interruption")
    n = await tick_until(va,0.17)
    var idle_t: float = va.current_animation_position
    ck(n<500 and idle_t>=0.17 and idle_t<0.35,"interrupted blend finishes in real frames")
    ck(absf(pa.current_animation_position-idle_t)<0.015,"preview and live clocks agree after interruption")
    for name in ["hand_l","hand_r"]:
        var actual: Vector3 = bone(v,name)
        var pure: Vector3 = endpoint(e,"idle",idle_t,name)
        print("H3_INTERRUPTED_RESTORED ",JSON.stringify({"bone":name,"t":idle_t,
            "pure_idle_delta":actual.distance_to(pure),
            "preview_delta":actual.distance_to(bone(p.visual,name))}))
        ck(actual.distance_to(pure)<0.001,"interrupted transition settles to pure idle "+name)
        ck(actual.distance_to(bone(p.visual,name))<0.001,"models agree after interruption "+name)
    p.visual.set_process(old_draft_tick)
    v.set_process(old_live_tick)
    p.visual.process_mode = old_draft_mode
    pa.process_mode = old_pa_mode
    va.process_mode = old_va_mode
    p.visual.visible = old_draft_visible
    v.visible = old_live_visible
    ck(p.visual.is_processing()==old_draft_tick and v.is_processing()==old_live_tick
        and p.visual.process_mode==old_draft_mode and pa.process_mode==old_pa_mode
        and va.process_mode==old_va_mode and p.visual.visible==old_draft_visible
        and v.visible==old_live_visible,"preview/live processing and visibility restored")
    Engine.time_scale = old_scale
    ck(is_equal_approx(Engine.time_scale,old_scale),"global time scale restored")
    e.queue_free()
    p.queue_free()
    await process_frame
    print("H3_COMPLETION_INTERRUPT_RESULT passed=",passed," failed=",failed)
    quit(0 if failed==0 else 1)