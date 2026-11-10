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

func isolate(v: Node3D) -> Dictionary:
	var sk: Skeleton3D = v._skeleton()
	var hid: int = sk.find_bone("hand_l")
	var src: MeshInstance3D = null
	for node in sk.get_children():
		if node is MeshInstance3D and node.name.begins_with("body__body__skin_body"):
			src = node
			break
	if src == null or hid < 0: return {"ok":false,"why":"no source"}
	var arrays: Array = src.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if bones.size()!=verts.size()*4 or weights.size()!=bones.size(): return {"ok":false,"why":"skin layout"}
	var picked := PackedInt32Array()
	for i in range(0,indices.size(),3):
		var hits := 0
		for k in 3:
			var vi: int = indices[i+k]
			if vi<0 or vi>=verts.size(): return {"ok":false,"why":"bad index"}
			for j in 4:
				if bones[vi*4+j]==hid and weights[vi*4+j]>0.2:
					hits+=1
					break
		if hits==3:
			picked.append(indices[i])
			picked.append(indices[i+1])
			picked.append(indices[i+2])
	if picked.size()<90: return {"ok":false,"why":"too few hand triangles"}
	var clean: Array = []
	clean.resize(Mesh.ARRAY_MAX)
	clean[Mesh.ARRAY_VERTEX]=arrays[Mesh.ARRAY_VERTEX]
	clean[Mesh.ARRAY_NORMAL]=arrays[Mesh.ARRAY_NORMAL]
	clean[Mesh.ARRAY_BONES]=bones
	clean[Mesh.ARRAY_WEIGHTS]=weights
	clean[Mesh.ARRAY_INDEX]=picked
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,clean)
	if mesh.get_surface_count()!=1: return {"ok":false,"why":"mesh surface creation failed"}
	var hand_mesh := MeshInstance3D.new()
	hand_mesh.name="H3_Isolated_Hand"
	hand_mesh.mesh=mesh
	hand_mesh.skin=src.skin
	hand_mesh.skeleton=src.skeleton
	hand_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color.WHITE
	mat.no_depth_test=true
	hand_mesh.material_override=mat
	for node in sk.get_children():
		if node is MeshInstance3D: node.visible=false
	sk.add_child(hand_mesh)
	return {"ok":true,"triangles":picked.size()/3}

func snapshot(p: Node, draft: bool) -> Image:
	p.visual.visible = draft
	p.viewport.get_node("LiveVisual").visible = not draft
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return p.viewport.get_texture().get_image()

func compare(a: Image, b: Image, center: Vector2i) -> Dictionary:
	if a.is_empty() or b.is_empty() or a.get_size()!=b.get_size(): return {"ok":false}
	var na:=0
	var nb:=0
	var inter:=0
	var uni:=0
	var delta:=0.0
	var total:=a.get_width()*a.get_height()
	for y in a.get_height():
		for x in a.get_width():
			var ca:=a.get_pixel(x,y)
			var cb:=b.get_pixel(x,y)
			var fa:=ca.r>0.8 and ca.g>0.8 and ca.b>0.8
			var fb:=cb.r>0.8 and cb.g>0.8 and cb.b>0.8
			if fa: na+=1
			if fb: nb+=1
			if fa and fb: inter+=1
			if fa or fb: uni+=1
			delta+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
	return {"ok":na>10 and nb>10 and na<total/2 and nb<total/2,
		"iou":float(inter)/maxi(1,uni),"rgb":delta/maxf(1.0,total*3.0),
		"fg_a":na,"fg_b":nb,"sampled":total}

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
	var iso_a: Dictionary = isolate(p.visual)
	var iso_b: Dictionary = isolate(v)
	ck(iso_a.get("ok",false) and iso_b.get("ok",false),"isolated skinned hand meshes exist")
	ck(iso_a.get("triangles",0)>30 and iso_a.get("triangles",0)==iso_b.get("triangles",0),"same hand-only triangles on both skeletons")
	print("H3_ISOLATED_TRIANGLES ",JSON.stringify({"preview":iso_a,"live":iso_b}))
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
	print("H3_HAND_ONLY_GPU ",JSON.stringify({"forward_time":forward_time,"reverse_time":reverse_time,
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
	print("H3_HAND_ONLY_NEGATIVE ",JSON.stringify(negative))
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
	print("H3_HAND_ONLY_RESULT passed=",passed," failed=",failed)
	quit(0 if failed==0 else 1)
