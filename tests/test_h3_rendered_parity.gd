extends "res://tests/test_base.gd"
## H3 graphical QA: real cold-loaded SimVisual reparented briefly into the
## exact preview camera/light world. Screenshots are PUBLIC appearance only.
## Run with xvfb-run + --lease=<valid-main-lock>. No production mutation.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const Preview := preload("res://scripts/ui/character_preview.gd")
const SAVE_DIR := "user://test-h3-cold-main-fallback-1793236448-36878"
const PEOPLE := ["Nora Cold", "Mira Cold"]
const SIZES := [Vector2i(1280,900), Vector2i(360,800)]
var lease := ""
var capture_tag := ""

func _ready() -> void:
    watchdog_seconds = 95.0
    _run.call_deferred()

func _metric(a: Image, b: Image) -> Dictionary:
    if a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
        return {"ok":false}
    var delta := 0.0
    var foreground_a := 0
    var foreground_b := 0
    var n := 0
    var first_a := a.get_pixel(0,0)
    var first_b := b.get_pixel(0,0)
    for y in range(0,a.get_height(),4):
        for x in range(0,a.get_width(),4):
            var ca := a.get_pixel(x,y)
            var cb := b.get_pixel(x,y)
            delta += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
            if absf(ca.r-first_a.r)+absf(ca.g-first_a.g)+absf(ca.b-first_a.b) > 0.12:
                foreground_a += 1
            if absf(cb.r-first_b.r)+absf(cb.g-first_b.g)+absf(cb.b-first_b.b) > 0.12:
                foreground_b += 1
            n += 1
    return {"ok":true,"mean_rgb_delta":delta/maxi(1,n*3),
        "preview_foreground":float(foreground_a)/maxi(1,n),
        "spawn_foreground":float(foreground_b)/maxi(1,n)}

## Known RGB clear color of CharacterPreview WorldEnvironment, not a corner
## pixel (the zoomed hand can occupy the corner). Report BOTH unregistered
## and translation-registered silhouette overlap; registration is diagnostic,
## not proof that gameplay and preview hand positions match.
func _hand_mask_metric(a: Image, b: Image) -> Dictionary:
    if a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
        return {"ok":false}
    var bg := Color(0.075,0.09,0.12)
    var count := 0
    var na := 0
    var nb := 0
    var raw_intersection := 0
    var sum_a := Vector2.ZERO
    var sum_b := Vector2.ZERO
    for y in range(0,a.get_height(),2):
        for x in range(0,a.get_width(),2):
            var ca := a.get_pixel(x,y)
            var cb := b.get_pixel(x,y)
            var ma := absf(ca.r-bg.r)+absf(ca.g-bg.g)+absf(ca.b-bg.b) > 0.15
            var mb := absf(cb.r-bg.r)+absf(cb.g-bg.g)+absf(cb.b-bg.b) > 0.15
            count += 1
            if ma:
                na += 1
                sum_a += Vector2(x,y)
            if mb:
                nb += 1
                sum_b += Vector2(x,y)
            if ma and mb:
                raw_intersection += 1
    if na == 0 or nb == 0:
        return {"ok":false,"reason":"empty foreground mask"}
    var dx: int = roundi(((sum_a.x/na)-(sum_b.x/nb))/2.0)*2
    var dy: int = roundi(((sum_a.y/na)-(sum_b.y/nb))/2.0)*2
    var aligned_a := 0
    var aligned_b := 0
    var aligned_intersection := 0
    var delta := 0.0
    for y in range(0,a.get_height(),2):
        for x in range(0,a.get_width(),2):
            var ca := a.get_pixel(x,y)
            var bx: int = x-dx
            var by: int = y-dy
            var cb: Color = b.get_pixel(bx,by) if bx>=0 and by>=0 and bx<b.get_width() and by<b.get_height() else bg
            var ma := absf(ca.r-bg.r)+absf(ca.g-bg.g)+absf(ca.b-bg.b) > 0.15
            var mb := absf(cb.r-bg.r)+absf(cb.g-bg.g)+absf(cb.b-bg.b) > 0.15
            if ma: aligned_a += 1
            if mb: aligned_b += 1
            if ma and mb:
                aligned_intersection += 1
                delta += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
    return {"ok":true,"preview_coverage":float(na)/maxi(1,count),
        "spawn_coverage":float(nb)/maxi(1,count),
        "unaligned_iou":float(raw_intersection)/maxi(1,na+nb-raw_intersection),
        "registered_iou":float(aligned_intersection)/maxi(1,aligned_a+aligned_b-aligned_intersection),
        "registered_rgb_delta":delta/maxi(1,aligned_intersection*3),
        "shift_x":dx,"shift_y":dy}

func _finger_state(visual: Node3D) -> Dictionary:
    var snapshot := {}
    for side in ["l", "r"]:
        for finger in 5:
            var state: Dictionary = visual.finger_joint_values(side, finger)
            if state.is_empty():
                return {}
            snapshot[side+str(finger)] = state.duplicate(true)
    return snapshot

func _restore_finger_state(visual: Node3D, snapshot: Dictionary) -> bool:
    if snapshot.size() != 10:
        return false
    for side in ["l", "r"]:
        for finger in 5:
            var state: Dictionary = snapshot.get(side+str(finger), {})
            if state.get("mode", "") == "joint":
                if not visual.set_finger_joint_bend(side, finger, "proximal", float(state.get("proximal", 0.0))):
                    return false
                if not visual.set_finger_joint_bend(side, finger, "distal", float(state.get("distal", 0.0))):
                    return false
            elif state.get("mode", "") == "legacy":
                if not visual.set_finger_curl(side, finger, float(state.get("combined", 0.0))):
                    return false
            else:
                return false
    return true

func _save_image(img: Image, path: String, G: Script) -> bool:
    if not G.owns(lease):
        check(false, "main lease lost before screenshot "+path)
        return false
    if FileAccess.file_exists(path):
        check(false, "refuse to overwrite screenshot "+path)
        return false
    if not G.heartbeat(lease).get("ok",false):
        check(false, "main lease heartbeat failed before screenshot")
        return false
    return check(img.save_png(path) == OK, "real GPU framebuffer saved "+path)

func _hand_projection(visual: Node3D, camera: Camera3D) -> Dictionary:
    var sk: Skeleton3D = visual._skeleton()
    var pivot: Node3D = visual.get("_body_pivot") as Node3D
    if sk == null or pivot == null:
        return {}
    var result := {"root":str(visual.transform), "pivot":str(pivot.transform),
        "skeleton":str(sk.transform)}
    var anim: AnimationPlayer = visual.get("_anim") as AnimationPlayer
    if anim != null:
        result["animation"] = String(anim.current_animation)
        result["animation_playing"] = anim.is_playing()
        result["animation_time"] = anim.current_animation_position
    for side in ["l", "r"]:
        var idx: int = sk.find_bone("hand_"+side)
        if idx < 0:
            return {}
        var point: Vector3 = sk.to_global(sk.get_bone_global_pose(idx).origin)
        result[side+"_world"] = str(point)
        result[side+"_pixel"] = str(camera.unproject_position(point))
    return result

func _run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-tag="):
            var proposed_tag: String = arg.trim_prefix("--capture-tag=")
            if proposed_tag.is_valid_identifier():
                capture_tag = "-" + proposed_tag
        if arg.begins_with("--lease="):
            lease = arg.trim_prefix("--lease=")
    var G = load("res://tools/automation_lock.gd")
    if not check(lease.begins_with("main-fallback-") and G.owns(lease),
        "valid live main lease required for screenshot writes"):
        finish("test_h3_rendered_parity")
        return
    if not check(FileAccess.file_exists(SAVE_DIR+"/autosave.lss"),
        "real previous producer autosave available"):
        finish("test_h3_rendered_parity")
        return
    var clock = get_node("/root/GameClock")
    clock.running = false
    Assets.enabled = true
    var world = Main.new()
    world.net_config = {"mode":"offline","hud":false,"camera":false,
        "visuals":false,"audio":false,"autoload":true,"autosave":false,
        "save_directory":SAVE_DIR}
    add_child(world)
    await get_tree().process_frame
    check(world.sims.size() == 5, "actual cold-process saved household restored")
    var first_metrics := {}
    for dims in SIZES:
        get_window().content_scale_size = Vector2i.ZERO
        get_window().size = dims
        await get_tree().process_frame
        for person in PEOPLE:
            var found: Node = null
            for sim in world.sims:
                if sim.sim_name == person:
                    found = sim
            if not check(found != null, "cold-loaded resident found "+person):
                continue
            var record: Dictionary = world.read_character_edit(String(found.name))
            if not check(record.get("ok",false), "private record read only for preview construction"):
                continue
            var preview = Preview.new()
            add_child(preview)
            preview.viewport.size = Vector2i(360,280) if dims.x > 500 else Vector2i(320,240)
            preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
            preview.show_draft(record["data"])
            preview.visual.set_hand_pose("open")
            var live: Node3D = found.visual
            check(preview.visual.uses_model() and live.uses_model(),
                "both preview and spawned resident use authored 3D mesh")
            for i in 4:
                await get_tree().process_frame
            await RenderingServer.frame_post_draw
            var preview_image: Image = preview.viewport.get_texture().get_image()
            check(not preview_image.is_empty(), "preview framebuffer nonempty "+person)
            var parent: Node = live.get_parent()
            var old_transform: Transform3D = live.transform
            var old_visible: bool = live.visible
            var old_global_transform: Transform3D = live.global_transform
            var old_hand_pose: String = live.hand_pose_name()
            var old_fingers: Dictionary = _finger_state(live)
            check(old_fingers.size() == 10, "all ten finger states captured before reparent")
            # Exercise the C14 independent two-joint mode, not only preset curls.
            check(live.set_finger_joint_bend("l",1,"proximal",0.37), "left index custom proximal bend")
            check(live.set_finger_joint_bend("l",1,"distal",0.81), "left index custom distal bend")
            check(live.set_finger_joint_bend("r",4,"proximal",0.62), "right thumb custom proximal bend")
            check(live.set_finger_joint_bend("r",4,"distal",0.19), "right thumb custom distal bend")
            var custom_fingers: Dictionary = _finger_state(live)
            check(custom_fingers.get("l1",{}).get("mode","") == "joint" and
                custom_fingers.get("r4",{}).get("mode","") == "joint",
                "both distinct C14 joint-mode fingers active before temporary render")
            var gem: Node = live.get("_gem")
            var label: Node = live.get("_label")
            var old_gem: bool = gem.visible if gem != null else false
            var old_label: bool = label.visible if label != null else false
            live.reparent(preview.viewport,false)
            live.transform = Transform3D.IDENTITY
            live.visible = true
            if gem != null: gem.hide()
            if label != null: label.hide()
            check(live.set_hand_pose("open"), "temporary open-hand render pose applied")
            preview.visual.hide()
            for i in 4:
                await get_tree().process_frame
            await RenderingServer.frame_post_draw
            var pdiag: Dictionary = _hand_projection(preview.visual, preview.camera)
            var ldiag: Dictionary = _hand_projection(live, preview.camera)
            check(not pdiag.is_empty() and not ldiag.is_empty(),
                "actual preview and live hand bone projections available")
            print("H3_HAND_PROJECT ",person," ",dims," ",
                JSON.stringify({"preview":pdiag,"spawn":ldiag}))
            var live_image: Image = preview.viewport.get_texture().get_image()
            # A second real framebuffer pair zooms the preview camera onto the hand.
            preview._hand_closeup = true
            preview._frame_character()
            live.hide()
            preview.visual.show()
            for i in 4:
                await get_tree().process_frame
            await RenderingServer.frame_post_draw
            var hand_preview_image: Image = preview.viewport.get_texture().get_image()
            preview.visual.hide()
            live.show()
            for i in 4:
                await get_tree().process_frame
            await RenderingServer.frame_post_draw
            var hand_live_image: Image = preview.viewport.get_texture().get_image()
            # Causal control: capture both models at identical idle t=0 in the
            # SAME camera. Preserve the live player's clip/phase/running state.
            var phase0_preview_image: Image = null
            var phase0_live_image: Image = null
            var live_anim: AnimationPlayer = live.get("_anim") as AnimationPlayer
            var draft_anim: AnimationPlayer = preview.visual.get("_anim") as AnimationPlayer
            if check(live_anim != null and draft_anim != null,
                "both authored models expose an AnimationPlayer for phase control"):
                var live_clip: String = String(live_anim.assigned_animation)
                var live_time: float = live_anim.current_animation_position
                var live_playing: bool = live_anim.is_playing()
                var live_speed: float = live_anim.speed_scale
                var draft_clip: String = String(draft_anim.assigned_animation)
                var draft_time: float = draft_anim.current_animation_position
                var draft_playing: bool = draft_anim.is_playing()
                var draft_speed: float = draft_anim.speed_scale
                check(live_clip in ["idle","walk"] and draft_clip in ["idle","walk"],
                    "original gameplay and preview animation clips recognized")
                live_anim.play("idle",0.0)
                draft_anim.play("idle",0.0)
                live_anim.advance(0.0)
                draft_anim.advance(0.0)
                live_anim.pause()
                draft_anim.pause()
                live_anim.seek(0.0, true)
                draft_anim.seek(0.0, true)
                live_anim.advance(0.0)
                draft_anim.advance(0.0)
                live.hide()
                preview.visual.show()
                for i in 4:
                    await get_tree().process_frame
                await RenderingServer.frame_post_draw
                phase0_preview_image = preview.viewport.get_texture().get_image()
                preview.visual.hide()
                live.show()
                for i in 4:
                    await get_tree().process_frame
                await RenderingServer.frame_post_draw
                phase0_live_image = preview.viewport.get_texture().get_image()
                var phase_rect := Rect2i(phase0_preview_image.get_width()/6,
                    phase0_preview_image.get_height()/6,
                    phase0_preview_image.get_width()*2/3,
                    phase0_preview_image.get_height()*2/3)
                var baseline_hand := _hand_mask_metric(
                    hand_preview_image.get_region(phase_rect),
                    hand_live_image.get_region(phase_rect))
                var phase_hand := _hand_mask_metric(
                    phase0_preview_image.get_region(phase_rect),
                    phase0_live_image.get_region(phase_rect))
                print("H3_IDLE_PHASE_CONTROL ",person," ",dims," ",
                    JSON.stringify({"before":baseline_hand,"phase0":phase_hand,
                        "live_original_time":live_time,"draft_original_time":draft_time}))
                check(baseline_hand.get("ok",false) and phase_hand.get("ok",false),
                    "both baseline and same-phase real hand silhouettes measurable")
                if baseline_hand.get("ok",false) and phase_hand.get("ok",false):
                    check(float(phase_hand["unaligned_iou"]) > 0.85 and
                        float(phase_hand["unaligned_iou"]) > float(baseline_hand["unaligned_iou"])+0.6 and
                        absi(int(phase_hand["shift_x"])) <= 4,
                        "same-phase hands align without post-hoc translation in both view sizes")
                # H3 walk-phase GPU control: real walk cycle, two same-phase
                # hand silhouettes without any post-hoc image translation.
                var live_process_before: bool = live.is_processing()
                var draft_process_before: bool = preview.visual.is_processing()
                live.set_process(false)
                preview.visual.set_process(false)
                var idle_sk: Skeleton3D = live._skeleton()
                var idle_left: Vector3 = idle_sk.to_global(idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                var max_walk_displacement := 0.0
                var walk_poses: Array[Vector3] = []
                var walk_frames: Array[Image] = []
                for walk_phase in [0.20, 0.70]:
                    live_anim.play("walk", 0.0)
                    draft_anim.play("walk", 0.0)
                    live_anim.advance(0.0)
                    draft_anim.advance(0.0)
                    live_anim.pause()
                    draft_anim.pause()
                    live_anim.seek(walk_phase, true)
                    draft_anim.seek(walk_phase, true)
                    live_anim.advance(0.0)
                    draft_anim.advance(0.0)
                    check(String(live_anim.assigned_animation) == "walk" and
                        String(draft_anim.assigned_animation) == "walk",
                        "both authored models use actual walk clip")
                    var walk_left: Vector3 = idle_sk.to_global(idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                    max_walk_displacement = maxf(max_walk_displacement,walk_left.distance_to(idle_left))
                    walk_poses.append(walk_left)
                    live.hide()
                    preview.visual.show()
                    for i in 4:
                        await get_tree().process_frame
                    await RenderingServer.frame_post_draw
                    var walk_preview: Image = preview.viewport.get_texture().get_image()
                    preview.visual.hide()
                    live.show()
                    for i in 4:
                        await get_tree().process_frame
                    await RenderingServer.frame_post_draw
                    var walk_live: Image = preview.viewport.get_texture().get_image()
                    walk_frames.append(walk_preview)
                    var wm: Dictionary = _hand_mask_metric(walk_preview.get_region(phase_rect),walk_live.get_region(phase_rect))
                    print("H3_WALK_PHASE ",person," ",dims," ",walk_phase," ",JSON.stringify(wm))
                    check(wm.get("ok",false) and float(wm.get("unaligned_iou",0)) > 0.75 and
                        absi(int(wm.get("shift_x",999))) <= 6,
                        "walk hand raw silhouette parity at matched phase")
                    var ws: String = "res://previews/h3-render-"+lease+capture_tag+"-walkfix4-"+person.replace(" ","-")+"-"+str(dims.x)+"-"+str(int(walk_phase*100))
                    _save_image(walk_preview.get_region(phase_rect),ws+"-preview.png",G)
                    _save_image(walk_live.get_region(phase_rect),ws+"-spawn.png",G)
                check(max_walk_displacement > 0.01, "walk phase moves actual hand bone relative to idle")
                check(walk_poses.size() == 2 and walk_poses[0].distance_to(walk_poses[1]) > 0.005,
                    "walk 0.20 and 0.70 have different real hand-bone positions")
                var walk_temporal: Dictionary = _metric(walk_frames[0],walk_frames[1])
                print("H3_WALK_TEMPORAL ",person," ",dims," ",JSON.stringify(walk_temporal))
                check(walk_temporal.get("ok",false) and float(walk_temporal.get("mean_rgb_delta",0)) > 0.002,
                    "distinct walk phases produce visibly different actual GPU frames")
                # Controlled real 0.25-second idle->walk crossfade.
                # Compare both authored models at the same elapsed blend time.
                var blend_samples: Array[Vector3] = []
                for blend_elapsed in [0.08, 0.18]:
                    live_anim.play("idle", 0.0)
                    draft_anim.play("idle", 0.0)
                    live_anim.seek(0.0, true)
                    draft_anim.seek(0.0, true)
                    live_anim.advance(0.0)
                    draft_anim.advance(0.0)
                    var blend_idle: Vector3 = idle_sk.to_global(
                        idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                    live_anim.play("walk", 0.25)
                    draft_anim.play("walk", 0.25)
                    live_anim.advance(blend_elapsed)
                    draft_anim.advance(blend_elapsed)
                    live_anim.pause()
                    draft_anim.pause()
                    var blended_hand: Vector3 = idle_sk.to_global(
                        idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                    blend_samples.append(blended_hand)
                    check(String(live_anim.assigned_animation) == "walk" and
                        String(draft_anim.assigned_animation) == "walk",
                        "both players assigned walk during 0.25s blend")
                    live.hide()
                    preview.visual.show()
                    for i in 4:
                        await get_tree().process_frame
                    await RenderingServer.frame_post_draw
                    var blend_preview: Image = preview.viewport.get_texture().get_image()
                    preview.visual.hide()
                    live.show()
                    for i in 4:
                        await get_tree().process_frame
                    var blend_live: Image = preview.viewport.get_texture().get_image()
                    await RenderingServer.frame_post_draw
                    var bm: Dictionary = _hand_mask_metric(
                        blend_preview.get_region(phase_rect),blend_live.get_region(phase_rect))
                    print("H3_BLEND_PHASE ",person," ",dims," ",blend_elapsed," ",
                        JSON.stringify({"mask":bm,"hand_from_idle_m":blended_hand.distance_to(blend_idle)}))
                    check(bm.get("ok",false) and
                        float(bm.get("unaligned_iou",0.0)) > 0.75 and
                        absi(int(bm.get("shift_x",999))) <= 6,
                        "raw hand silhouettes match during 0.25s blend")
                    var bs: String = "res://previews/h3-render-"+lease+capture_tag+"-blend-"+person.replace(" ","-")+"-"+str(dims.x)+"-"+str(int(blend_elapsed*100))
                    _save_image(blend_preview.get_region(phase_rect),bs+"-preview.png",G)
                    _save_image(blend_live.get_region(phase_rect),bs+"-spawn.png",G)
                    # The blend must not be identical to either endpoint.
                    live_anim.play("walk", 0.0)
                    live_anim.seek(blend_elapsed, true)
                    live_anim.advance(0.0)
                    var pure_walk: Vector3 = idle_sk.to_global(
                        idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                    print("H3_BLEND_DISTANCE ",person," ",dims," ",blend_elapsed,
                        " from_idle=",blended_hand.distance_to(blend_idle),
                        " from_pure_walk=",blended_hand.distance_to(pure_walk))
                    check(blended_hand.distance_to(blend_idle) > 0.0001 and
                        blended_hand.distance_to(pure_walk) > 0.0001,
                        "blend hand pose differs from both idle and zero-blend walk")
                check(blend_samples.size() == 2 and
                    blend_samples[0].distance_to(blend_samples[1]) > 0.0001,
                    "two blend elapsed times produce different actual hand-bone poses")
                # Natural-start regression: idle has already advanced in the
                # real authored AnimationPlayer before a 0.25s walk blend.
                # Third sample replays the first to detect stale blend carryover.
                var natural_poses: Array[Vector3] = []
                for idle_phase in [0.37, 0.79, 0.37]:
                    live_anim.play("idle", 0.0)
                    draft_anim.play("idle", 0.0)
                    live_anim.seek(0.0, true)
                    draft_anim.seek(0.0, true)
                    live_anim.advance(idle_phase)
                    draft_anim.advance(idle_phase)
                    check(is_equal_approx(live_anim.current_animation_position, idle_phase) and
                        is_equal_approx(draft_anim.current_animation_position, idle_phase),
                        "both real idle clips progressed before natural-start transition")
                    var ongoing_idle: Vector3 = idle_sk.to_global(
                        idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                    live_anim.play("walk", 0.25)
                    draft_anim.play("walk", 0.25)
                    live_anim.advance(0.11)
                    draft_anim.advance(0.11)
                    live_anim.pause()
                    draft_anim.pause()
                    var ongoing_blend: Vector3 = idle_sk.to_global(
                        idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin)
                    natural_poses.append(ongoing_blend)
                    check(ongoing_blend.distance_to(ongoing_idle) > 0.0001,
                        "ongoing idle-to-walk blend moves actual left hand")
                    live.hide()
                    preview.visual.show()
                    for i in 4:
                        await get_tree().process_frame
                    await RenderingServer.frame_post_draw
                    var natural_preview: Image = preview.viewport.get_texture().get_image()
                    preview.visual.hide()
                    live.show()
                    for i in 4:
                        await get_tree().process_frame
                    await RenderingServer.frame_post_draw
                    var natural_live: Image = preview.viewport.get_texture().get_image()
                    var nm: Dictionary = _hand_mask_metric(
                        natural_preview.get_region(phase_rect),
                        natural_live.get_region(phase_rect))
                    print("H3_NATURAL_IDLE_BLEND ",person," ",dims," ",idle_phase," ",
                        JSON.stringify({"mask":nm,"hand_delta_m":ongoing_blend.distance_to(ongoing_idle)}))
                    check(nm.get("ok",false) and
                        float(nm.get("unaligned_iou",0.0)) > 0.75 and
                        absi(int(nm.get("shift_x",999))) <= 6,
                        "natural-start blend matches hand silhouettes without image translation")
                    var ns: String = "res://previews/h3-render-"+lease+capture_tag+"-natural-"+person.replace(" ","-")+"-"+str(dims.x)+"-"+str(int(idle_phase*100))+"-"+str(natural_poses.size())
                    _save_image(natural_preview.get_region(phase_rect),ns+"-preview.png",G)
                    _save_image(natural_live.get_region(phase_rect),ns+"-spawn.png",G)
                check(natural_poses.size() == 3 and
                    natural_poses[0].distance_to(natural_poses[1]) > 0.0001 and
                    natural_poses[0].distance_to(natural_poses[2]) < 0.0001,
                    "different ongoing idle phases yield distinct blends, repeated phase resets blend state")
                # H3 realtime: no seek()/advance() between idle and walk.
                # CharacterPreview deliberately disables its SimVisual subtree.
                # Temporarily enable only the draft AnimationPlayer's idle clock.
                var draft_anim_mode_before: int = draft_anim.process_mode
                check(preview.visual.process_mode == Node.PROCESS_MODE_DISABLED,
                    "character preview normally freezes its authored visual")
                draft_anim.process_mode = Node.PROCESS_MODE_ALWAYS
                live_anim.speed_scale = 1.0
                draft_anim.speed_scale = 1.0
                live_anim.play("idle", 0.0)
                draft_anim.play("idle", 0.0)
                for tick in 6:
                    await get_tree().process_frame
                var tick_idle_live: float = live_anim.current_animation_position
                var tick_idle_draft: float = draft_anim.current_animation_position
                check(tick_idle_live > 0.0 and tick_idle_draft > 0.0 and
                    absf(tick_idle_live-tick_idle_draft) < 0.05,
                    "real process frames advanced both idle players")
                live_anim.play("walk", 0.25)
                draft_anim.play("walk", 0.25)
                var tick_walk_times: Array[float] = []
                var tick_hand_positions: Array[Vector3] = []
                for sample in 2:
                    for tick in 4:
                        await get_tree().process_frame
                    var tick_live: float = live_anim.current_animation_position
                    var tick_draft: float = draft_anim.current_animation_position
                    tick_walk_times.append(tick_live)
                    tick_hand_positions.append(idle_sk.to_global(
                        idle_sk.get_bone_global_pose(idle_sk.find_bone("hand_l")).origin))
                    check(tick_live > 0.0 and tick_draft > 0.0 and
                        absf(tick_live-tick_draft) < 0.05,
                        "real frame-ticked walk clips have matching elapsed times")
                live_anim.pause()
                draft_anim.pause()
                check(tick_walk_times.size() == 2 and
                    tick_walk_times[1] > tick_walk_times[0],
                    "walk phase progressed on actual frames without manual advance")
                check(tick_hand_positions.size() == 2 and
                    tick_hand_positions[0].distance_to(tick_hand_positions[1]) > 0.00001,
                    "hand bone moved during frame-ticked transition")
                live.hide()
                preview.visual.show()
                for tick in 4:
                    await get_tree().process_frame
                await RenderingServer.frame_post_draw
                var tick_preview: Image = preview.viewport.get_texture().get_image()
                preview.visual.hide()
                live.show()
                for tick in 4:
                    await get_tree().process_frame
                await RenderingServer.frame_post_draw
                var tick_live_image: Image = preview.viewport.get_texture().get_image()
                var tick_mask: Dictionary = _hand_mask_metric(
                    tick_preview.get_region(phase_rect),
                    tick_live_image.get_region(phase_rect))
                print("H3_FRAME_TICK_BLEND ",person," ",dims," ",
                    JSON.stringify({"idle_live":tick_idle_live,"idle_preview":tick_idle_draft,
                        "walk_times":tick_walk_times,"hand_move_m":
                        tick_hand_positions[0].distance_to(tick_hand_positions[1]),
                        "mask":tick_mask}))
                check(tick_mask.get("ok",false) and
                    float(tick_mask.get("unaligned_iou",0.0)) > 0.75 and
                    absi(int(tick_mask.get("shift_x",999))) <= 6,
                    "frame-ticked transition retains raw hand GPU parity")
                draft_anim.process_mode = draft_anim_mode_before
                check(draft_anim.process_mode == draft_anim_mode_before and
                    preview.visual.process_mode == Node.PROCESS_MODE_DISABLED,
                    "static draft preview processing contract restored after frame-tick QA")
                live.set_process(live_process_before)
                preview.visual.set_process(draft_process_before)
                check(live.is_processing() == live_process_before and
                    preview.visual.is_processing() == draft_process_before,
                    "visual processing restored after walk phase intervention")
                # Restore BEFORE returning the gameplay visual to its parent.
                live_anim.play(live_clip)
                live_anim.seek(live_time, true)
                live_anim.speed_scale = live_speed
                if not live_playing:
                    live_anim.pause()
                draft_anim.play(draft_clip)
                draft_anim.seek(draft_time, true)
                draft_anim.speed_scale = draft_speed
                if not draft_playing:
                    draft_anim.pause()
                check(String(live_anim.assigned_animation) == live_clip and
                    is_equal_approx(live_anim.current_animation_position,live_time) and
                    live_anim.is_playing() == live_playing and
                    is_equal_approx(live_anim.speed_scale,live_speed),
                    "gameplay AnimationPlayer clip/phase/running/speed restored")
                check(String(draft_anim.assigned_animation) == draft_clip and
                    is_equal_approx(draft_anim.current_animation_position,draft_time) and
                    draft_anim.is_playing() == draft_playing and
                    is_equal_approx(draft_anim.speed_scale,draft_speed),
                    "draft AnimationPlayer clip/phase/running/speed restored")
            preview._hand_closeup = false
            preview._frame_character()
            live.reparent(parent,false)
            live.transform = old_transform
            live.visible = old_visible
            if gem != null: gem.visible = old_gem
            if label != null: label.visible = old_label
            check(live.set_hand_pose(old_hand_pose), "original hand gesture restored after render")
            check(_restore_finger_state(live, custom_fingers), "custom C14 joint-mode bends restored")
            check(_finger_state(live) == custom_fingers, "custom proximal/distal bends and joint modes exact")
            check(_restore_finger_state(live, old_fingers), "all original individual finger bends restored")
            check(_finger_state(live) == old_fingers, "finger curl and joint morph values match pre-render state")
            check(live.get_parent() == parent, "live SimVisual parent restored")
            check(live.transform.is_equal_approx(old_transform) and live.global_transform.is_equal_approx(old_global_transform),
                "local and world transforms restored")
            check(live.visible == old_visible and (gem == null or gem.visible == old_gem) and (label == null or label.visible == old_label),
                "body and accessory visibility restored")
            check(live.hand_pose_name() == old_hand_pose, "hand pose name restored")
            preview.visual.show()
            var stats := _metric(preview_image,live_image)
            check(stats.get("ok",false), "matching image dimensions "+person)
            if stats.get("ok",false):
                print("H3_RENDER_METRIC ",person," ",dims," ",JSON.stringify(stats))
                check(float(stats["preview_foreground"]) > 0.03 and
                    float(stats["spawn_foreground"]) > 0.03,
                    "both actual rendered frames contain >3% foreground pixels")
                check(float(stats["mean_rgb_delta"]) < 0.02,
                    "cold-loaded live visual and creator preview have <2% mean RGB pixel difference")
                first_metrics[person+"-"+str(dims.x)] = stats
            var stem: String = "res://previews/h3-render-"+lease+capture_tag+"-phasewalk4-"+person.replace(" ","-")+"-"+str(dims.x)
            if not _save_image(preview_image,stem+"-preview.png",G):
                preview.queue_free()
                finish("test_h3_rendered_parity")
                return
            if not _save_image(live_image,stem+"-spawn.png",G):
                preview.queue_free()
                finish("test_h3_rendered_parity")
                return
            # Use a fixed central crop of the actual zoomed hand view.
            var w: int = hand_preview_image.get_width()
            var h: int = hand_preview_image.get_height()
            var hand_rect := Rect2i(w/6,h/6,w*2/3,h*2/3)
            var crop_preview: Image = hand_preview_image.get_region(hand_rect)
            var crop_spawn: Image = hand_live_image.get_region(hand_rect)
            var hm: Dictionary = _hand_mask_metric(crop_preview,crop_spawn)
            print("H3_HAND_CROP ",person," ",dims," ",JSON.stringify(hm))
            check(hm.get("ok",false) and
                float(hm.get("preview_coverage",0)) > 0.08 and
                float(hm.get("spawn_coverage",0)) > 0.08 and
                float(hm.get("preview_coverage",1)) < 0.7 and
                float(hm.get("spawn_coverage",1)) < 0.7,
                "zoomed hand foreground masks are nonempty and do not include the full background")
            check(hm.get("ok",false) and
                absf(float(hm.get("shift_x",999))) < float(crop_preview.get_width()) and
                absf(float(hm.get("shift_y",999))) <= 10.0 and
                float(hm.get("registered_iou",0)) > 0.75 and
                float(hm.get("registered_rgb_delta",1)) < 0.06,
                "unsynchronized-phase registered hand similarity; raw shift diagnostic only")
            if not _save_image(crop_preview,stem+"-handcrop-preview.png",G):
                preview.queue_free()
                finish("test_h3_rendered_parity")
                return
            if not _save_image(crop_spawn,stem+"-handcrop-spawn.png",G):
                preview.queue_free()
                finish("test_h3_rendered_parity")
                return
            if phase0_preview_image != null and phase0_live_image != null:
                if not _save_image(phase0_preview_image.get_region(hand_rect),
                    stem+"-phase0-handcrop-preview.png",G):
                    preview.queue_free()
                    finish("test_h3_rendered_parity")
                    return
                if not _save_image(phase0_live_image.get_region(hand_rect),
                    stem+"-phase0-handcrop-spawn.png",G):
                    preview.queue_free()
                    finish("test_h3_rendered_parity")
                    return
            preview.queue_free()
            await get_tree().process_frame
    check(first_metrics.size() == 4, "two residents captured at normal and narrow window sizes")
    world.queue_free()
    await get_tree().process_frame
    finish("test_h3_rendered_parity")