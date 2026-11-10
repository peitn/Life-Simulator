extends SceneTree
## H3 test-only: dense real-frame reverse interruption continuity and endpoint parity.
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
    # Dense real-frame reverse sampling of both hands, including transient parity.
    var reverse_samples := 0
    var max_frame_jump := 0.0
    var max_clock_gap := 0.0
    var max_model_delta := 0.0
    var previous_left: Vector3 = bone(v,"hand_l")
    var previous_right: Vector3 = bone(v,"hand_r")
    var previous_t := 0.0
    var bins := {}
    var time_monotonic := true
    while va.current_animation_position < 0.17 and reverse_samples < 500:
        await process_frame
        var t: float = va.current_animation_position
        var left: Vector3 = bone(v,"hand_l")
        var right: Vector3 = bone(v,"hand_r")
        max_frame_jump = maxf(max_frame_jump,maxf(left.distance_to(previous_left),right.distance_to(previous_right)))
        max_clock_gap = maxf(max_clock_gap,t-previous_t)
        max_model_delta = maxf(max_model_delta,maxf(left.distance_to(bone(p.visual,"hand_l")),
            right.distance_to(bone(p.visual,"hand_r"))))
        if t < previous_t: time_monotonic = false
        bins[int(floorf(t/0.015))] = true
        previous_left = left
        previous_right = right
        previous_t = t
        reverse_samples += 1
    var idle_t: float = va.current_animation_position
    print("H3_DENSE_REVERSE ",JSON.stringify({"samples":reverse_samples,"time":idle_t,
        "bins":bins.size(),"max_frame_jump_m":max_frame_jump,
        "max_clock_gap_s":max_clock_gap,"max_preview_live_delta_m":max_model_delta}))
    ck(reverse_samples>=12 and reverse_samples<500 and bins.size()>=7,
        "dense real-frame coverage of reverse transition")
    ck(time_monotonic and idle_t>=0.17 and idle_t<0.35,
        "reverse animation time progresses and completes")
    ck(max_model_delta<0.001,"preview and live hand bones agree at all reverse frames")
    ck(max_frame_jump<0.10,"no hand-bone teleport over 100mm in any sampled frame")
    ck(absf(pa.current_animation_position-idle_t)<0.015,"preview and live clocks agree after interruption")
    # Mutation control: a deliberate 150mm hand-bone displacement MUST break parity.
    var live_skeleton: Skeleton3D = v._skeleton()
    var hand_idx: int = live_skeleton.find_bone("hand_l")
    var saved_local: Vector3 = live_skeleton.get_bone_pose_position(hand_idx)
    live_skeleton.set_bone_pose_position(hand_idx,saved_local+Vector3(0.15,0.0,0.0))
    var mutated_delta: float = bone(v,"hand_l").distance_to(bone(p.visual,"hand_l"))
    print("H3_DENSE_NEGATIVE ",JSON.stringify({"mutated_delta_m":mutated_delta}))
    ck(mutated_delta>0.10,"150mm injected hand offset is detected by parity assertion")
    live_skeleton.set_bone_pose_position(hand_idx,saved_local)
    ck(bone(v,"hand_l").distance_to(bone(p.visual,"hand_l"))<0.001,
        "mutation fully restored before endpoint checks")
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
    print("H3_DENSE_REVERSE_RESULT passed=",passed," failed=",failed)
    quit(0 if failed==0 else 1)