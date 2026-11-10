extends SceneTree
## H3 independent fresh-process crossfade at 0.05, 0.14, 0.20s with hand-centered GPU ROI.
## No production character or network state is mutated.
const Preview = preload("res://scripts/ui/character_preview.gd")
const Visual = preload("res://scripts/sim/sim_visual.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
var lease := ""
var capture_tag := ""
var target_time := 0.14
var passed := 0
var failed := 0

func ck(ok: bool, message: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL ", message)

func hand(v: Node3D) -> Vector3:
    var s: Skeleton3D = v._skeleton()
    return s.get_bone_global_pose(s.find_bone("hand_l")).origin

func mask(a: Image, b: Image) -> Dictionary:
    if a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
        return {"ok":false}
    var bg := Color(0.075,0.09,0.12)
    var na := 0
    var nb := 0
    var inter := 0
    var rgb := 0.0
    for y in range(0,a.get_height(),2):
        for x in range(0,a.get_width(),2):
            var ca := a.get_pixel(x,y)
            var cb := b.get_pixel(x,y)
            var aa := absf(ca.r-bg.r)+absf(ca.g-bg.g)+absf(ca.b-bg.b)>0.15
            var bb := absf(cb.r-bg.r)+absf(cb.g-bg.g)+absf(cb.b-bg.b)>0.15
            if aa: na += 1
            if bb: nb += 1
            if aa and bb: inter += 1
            rgb += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
    return {"ok":na>0 and nb>0,"iou":float(inter)/maxi(1,na+nb-inter),
        "rgb_delta":rgb/maxf(1.0,float(a.get_width()*a.get_height())*0.75),
        "pixels_a":na,"pixels_b":nb}

func snapshot(p: Node, draft: bool) -> Image:
    p.visual.visible = draft
    p.viewport.get_node("LiveVisual").visible = not draft
    for i in 3:
        await process_frame
    await RenderingServer.frame_post_draw
    return p.viewport.get_texture().get_image()

func _init() -> void:
    call_deferred("run")

func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-tag="):
            capture_tag = arg.trim_prefix("--capture-tag=")
        if arg.begins_with("--target="):
            target_time = float(arg.trim_prefix("--target="))
        if arg.begins_with("--lease="):
            lease = arg.trim_prefix("--lease=")
    var G = load("res://tools/automation_lock.gd")
    if not lease.begins_with("main-fallback-") or not G.owns(lease):
        print("FAIL no owned main lease")
        quit(2)
        return
    var old_scale: float = Engine.time_scale
    Engine.time_scale = 0.15
    Assets.enabled = true
    var p = Preview.new()
    root.add_child(p)
    p.viewport.size = Vector2i(360,280)
    p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var v = Visual.new()
    v.name = "LiveVisual"
    p.viewport.add_child(v)
    v.get("_gem").hide()
    v.get("_label").hide()
    var pa: AnimationPlayer = p.visual.get("_anim")
    var va: AnimationPlayer = v.get("_anim")
    ck(p.visual.uses_model() and v.uses_model(), "both independent authored meshes")
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
    # Freeze only SimVisual's automatic idle/walk selector; child AnimationPlayers still tick.
    p.visual.set_process(false)
    v.set_process(false)
    p._hand_closeup = true
    p._frame_character()
    pa.play("idle",0.0)
    va.play("idle",0.0)
    for i in 5:
        await process_frame
    var idle_start_t: float = va.current_animation_position
    var idle_h: Vector3 = hand(v)
    ck(va.current_animation_position>0 and
        absf(pa.current_animation_position-va.current_animation_position)<0.01,
        "both idle clocks advanced in real frames")
    pa.play("walk",0.25)
    va.play("walk",0.25)
    var samples: Array[Dictionary] = []
    for k in 1:
        var target: float = target_time
        var ticks := 0
        while va.current_animation_position < target and ticks < 100:
            await process_frame
            ticks += 1
        await RenderingServer.frame_post_draw
        var t: float = va.current_animation_position
        ck(pa.assigned_animation=="walk" and va.assigned_animation=="walk",
            "walk clip stays assigned during crossfade (not overwritten by SimVisual)")
        pa.pause()
        va.pause()
        var h: Vector3 = hand(v)
        var hp: Vector3 = hand(p.visual)
        var draft_img: Image = await snapshot(p,true)
        var live_img: Image = await snapshot(p,false)
        var bone_screen: Vector2 = p.camera.unproject_position(p.visual._skeleton().to_global(hp))
        var roi_center := Vector2i(roundi(bone_screen.x),roundi(bone_screen.y))
        ck(roi_center.x>=48 and roi_center.x<312 and roi_center.y>=48 and roi_center.y<232,
            "left hand bone projects inside valid 96px hand ROI")
        var crop := Rect2i(clampi(roi_center.x-48,0,264),clampi(roi_center.y-48,0,184),96,96)
        print("H3_HAND_ROI ",JSON.stringify({"center":roi_center,"crop":crop,"target":target_time}))
        var m := mask(draft_img.get_region(crop),live_img.get_region(crop))
        print("H3_GPU_BLEND ",JSON.stringify({"sample":k,"time":t,
            "bone_delta_m":h.distance_to(hp),"idle_delta_m":h.distance_to(idle_h),
            "mask":m}))
        var valid_time: bool = absf(t-target_time)<=0.025 and t>0.0 and t<0.25
        ck(valid_time, "real frame-ticked blend sample inside expected time window")
        print("H3_LATE_CLOCKS ",JSON.stringify({"draft":pa.current_animation_position,"live":t}))
        ck(absf(pa.current_animation_position-t)<0.01, "draft/live frame clocks agree")
        ck(h.distance_to(hp)<0.001, "both skeletons match at intermediate instant")
        ck(m.get("ok",false) and float(m.get("iou",0.0))>0.95,
            "raw unregistered GPU hand masks agree at intermediate instant")
        ck(float(m.get("rgb_delta",1.0))<0.04, "raw GPU pixel colors agree")
        samples.append({"time":t,"hand":h})
        if G.owns(lease) and G.heartbeat(lease).get("ok",false):
            var name: String = "res://previews/h3-blend-gpu-"+lease+"-"+capture_tag+"-"+str(k)
            if not FileAccess.file_exists(name+"-preview.png") and not FileAccess.file_exists(name+"-live.png"):
                ck(draft_img.get_region(crop).save_png(name+"-preview.png")==OK,
                    "preview GPU image saved")
                ck(live_img.get_region(crop).save_png(name+"-live.png")==OK,
                    "live GPU image saved")
            else:
                ck(false,"refuse screenshot overwrite")
        else:
            ck(false,"lease lost during GPU screenshots")
        # One clean late sample: no prior pause/resume may reset blending.
    ck(samples.size()==1 and absf(float(samples[0]["time"])-target_time)<=0.025,
        "one clean real-clock sample at requested target without prior pause/resume")
    # Endpoint comparisons use a disposable third visual, never the two
    # frame-ticked blend players (their blend accumulators remain untouched).
    var endpoint = Visual.new()
    root.add_child(endpoint)
    var ea: AnimationPlayer = endpoint.get("_anim")
    for s in samples:
        var t: float = s["time"]
        ea.play("walk",0.0)
        ea.seek(t,true)
        ea.advance(0.0)
        var blended: Vector3 = s["hand"]
        var walk_h: Vector3 = hand(endpoint)
        ea.play("idle",0.0)
        ea.seek(idle_start_t+t,true)
        ea.advance(0.0)
        var pure_idle_h: Vector3 = hand(endpoint)
        var d_idle: float = blended.distance_to(pure_idle_h)
        var d_walk: float = blended.distance_to(walk_h)
        var d_ends: float = pure_idle_h.distance_to(walk_h)
        print("H3_GPU_ENDPOINT ",JSON.stringify({"time":t,"idle_m":d_idle,
            "walk_m":d_walk,"endpoints_m":d_ends}))
        ck(d_idle>0.001 and d_walk>0.001 and d_ends>0.02,
            "frame-ticked blend differs from both matched-time pure endpoints")
    endpoint.queue_free()
    p.visual.set_process(old_draft_tick)
    v.set_process(old_live_tick)
    p.visual.process_mode = old_draft_mode
    pa.process_mode = old_pa_mode
    va.process_mode = old_va_mode
    p.visual.visible = old_draft_visible
    v.visible = old_live_visible
    ck(p.visual.process_mode==old_draft_mode and pa.process_mode==old_pa_mode
        and va.process_mode==old_va_mode and p.visual.visible==old_draft_visible
        and v.visible==old_live_visible and p.visual.is_processing()==old_draft_tick
        and v.is_processing()==old_live_tick,
        "original process modes, processing flags and visibility restored")
    Engine.time_scale = old_scale
    p.queue_free()
    await process_frame
    print("H3_BLEND_GPU_RESULT passed=",passed," failed=",failed)
    quit(0 if failed==0 else 1)