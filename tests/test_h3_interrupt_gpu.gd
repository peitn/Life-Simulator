extends SceneTree
## H3 disposable Xvfb/Mesa check: genuine interrupted idle->walk->idle GPU parity.
## One clean reverse sample per process, without pause/resume before sampling.
const Preview = preload("res://scripts/ui/character_preview.gd")
const Visual = preload("res://scripts/sim/sim_visual.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
var passed := 0
var failed := 0
var target := 0.05

func ck(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", message)

func hand(v: Node3D, name: String = "hand_l") -> Vector3:
	var s: Skeleton3D = v._skeleton()
	return s.get_bone_global_pose(s.find_bone(name)).origin

func snapshot(p: Node, draft: bool) -> Image:
	p.visual.visible = draft
	p.viewport.get_node("LiveVisual").visible = not draft
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return p.viewport.get_texture().get_image()

func compare(a: Image, b: Image, center: Vector2i) -> Dictionary:
	if a.is_empty() or b.is_empty() or a.get_size()!=b.get_size():
		return {"ok":false}
	var w := a.get_width()
	var h := a.get_height()
	var bg := Color(0.075,0.09,0.12)
	var fg_a := 0
	var fg_b := 0
	var intersection := 0
	var union := 0
	var color_error := 0.0
	var sampled := 0
	# Circular aperture around projected wrist/hand bone; not a semantic hand-only mesh mask.
	for dy in range(-20,21):
		for dx in range(-20,21):
			if dx*dx+dy*dy>400:
				continue
			var x := center.x+dx
			var y := center.y+dy
			if x<0 or y<0 or x>=w or y>=h:
				continue
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			var fa := absf(ca.r-bg.r)+absf(ca.g-bg.g)+absf(ca.b-bg.b)>0.15
			var fb := absf(cb.r-bg.r)+absf(cb.g-bg.g)+absf(cb.b-bg.b)>0.15
			if fa: fg_a += 1
			if fb: fg_b += 1
			if fa and fb: intersection += 1
			if fa or fb: union += 1
			color_error += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
			sampled += 1
	return {"ok":sampled>500 and fg_a>20 and fg_b>20 and union>0,
		"iou":float(intersection)/maxi(1,union),
		"rgb":color_error/maxf(1.0,float(sampled)*3.0),
		"fg_a":fg_a,"fg_b":fg_b,"sampled":sampled}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var lease := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lease="): lease = arg.trim_prefix("--lease=")
		if arg.begins_with("--reverse-target="): target = float(arg.trim_prefix("--reverse-target="))
	var G = load("res://tools/automation_lock.gd")
	if not lease.begins_with("main-fallback-") or not G.owns(lease):
		print("FAIL no owned lease")
		quit(2)
		return
	var old_scale := Engine.time_scale
	var old_assets := Assets.enabled
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
	p._hand_closeup = true
	p._frame_character()
	ck(p.visual.uses_model() and v.uses_model(), "independent authored meshes loaded")
	ck(p.visual._skeleton().find_bone("hand_l")>=0 and v._skeleton().find_bone("hand_l")>=0,"hand bone exists")
	pa.play("idle",0.0)
	va.play("idle",0.0)
	for i in 5: await process_frame
	pa.play("walk",0.25)
	va.play("walk",0.25)
	var ticks := 0
	while va.current_animation_position<0.10 and ticks<200:
		await process_frame
		ticks += 1
	var forward_time := va.current_animation_position
	ck(ticks<200 and forward_time>=0.10 and forward_time<0.20,"forward crossfade genuinely interrupted before 0.25s")
	var forward_hand := hand(v)
	pa.play("idle",0.12)
	va.play("idle",0.12)
	ticks = 0
	while va.current_animation_position<target and ticks<200:
		await process_frame
		ticks += 1
	await RenderingServer.frame_post_draw
	var reverse_time := va.current_animation_position
	var live_hand := hand(v)
	var draft_hand := hand(p.visual)
	ck(ticks<200 and absf(reverse_time-target)<0.025 and reverse_time<0.12,"real-clock reverse sample within blend")
	ck(pa.assigned_animation=="idle" and va.assigned_animation=="idle","reverse idle assigned on both")
	ck(absf(pa.current_animation_position-reverse_time)<0.01,"independent animation clocks match")
	ck(live_hand.distance_to(draft_hand)<0.001,"hand bone positions match")
	pa.pause()
	va.pause()
	var image_a: Image = await snapshot(p,true)
	var image_b: Image = await snapshot(p,false)
	var center := Vector2i(p.camera.unproject_position(p.visual._skeleton().to_global(draft_hand)).round())
	ck(center.x>=20 and center.x<340 and center.y>=20 and center.y<260,"circular hand aperture fully inside viewport")
	var m := compare(image_a,image_b,center)
	print("H3_REVERSE_GPU ",JSON.stringify({"forward_time":forward_time,"reverse_time":reverse_time,
		"bone_delta_m":live_hand.distance_to(draft_hand),"center":center,"mask":m}))
	ck(m.get("ok",false),"circular GPU hand aperture contains rendered geometry")
	ck(float(m.get("iou",0.0))>0.95,"GPU foreground agreement")
	ck(float(m.get("rgb",1.0))<0.04,"GPU color agreement")
	# Negative control: deliberately rotate only the live hand and require GPU pixels to react.
	var skeleton: Skeleton3D = v._skeleton()
	var hand_idx: int = skeleton.find_bone("hand_l")
	var original_rotation: Quaternion = skeleton.get_bone_pose_rotation(hand_idx)
	skeleton.set_bone_pose_rotation(hand_idx, original_rotation * Quaternion(Vector3.UP,1.1))
	var changed_img: Image = await snapshot(p,false)
	var negative := compare(image_b,changed_img,center)
	print("H3_GPU_NEGATIVE_CONTROL ",JSON.stringify(negative))
	ck(float(negative.get("rgb",0.0))>0.001 or float(negative.get("iou",1.0))<0.99,
		"aperture is sensitive to intentional hand rotation")
	skeleton.set_bone_pose_rotation(hand_idx,original_rotation)
	ck(skeleton.get_bone_pose_rotation(hand_idx).is_equal_approx(original_rotation),
		"intentional hand perturbation restored")
	p.visual.set_process(old_draft_tick)
	v.set_process(old_live_tick)
	p.visual.process_mode = old_draft_mode
	pa.process_mode = old_pa_mode
	va.process_mode = old_va_mode
	p.visual.visible = old_draft_visible
	v.visible = old_live_visible
	Engine.time_scale = old_scale
	Assets.enabled = old_assets
	ck(p.visual.is_processing()==old_draft_tick and v.is_processing()==old_live_tick
		and p.visual.process_mode==old_draft_mode and pa.process_mode==old_pa_mode
		and va.process_mode==old_va_mode and p.visual.visible==old_draft_visible
		and v.visible==old_live_visible and is_equal_approx(Engine.time_scale,old_scale)
		and Assets.enabled==old_assets,"processing, visibility, time and asset flag restored")
	p.queue_free()
	await process_frame
	print("H3_REVERSE_GPU_RESULT passed=",passed," failed=",failed)
	quit(0 if failed==0 else 1)
