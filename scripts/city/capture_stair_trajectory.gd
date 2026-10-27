extends SceneTree
## Diagnostic only: real controller samples, no production movement changes.
const Harness = preload("res://scripts/city/validate_stair_physics_walk.gd")
const G = preload("res://tools/automation_lock.gd")
class Recorder extends Harness.Walker:
	var samples: Array = []
	func _physics_process(delta: float) -> void:
		if finished: return
		var old := global_position
		var old_phase := phase
		super._physics_process(delta)
		samples.append({"tick": ticks, "phase": old_phase, "x": position.x, "y": position.y, "z": position.z, "dy": position.y-old.y, "grounded": is_on_floor(), "lifts": lifts})
var run_id := ""
func _init() -> void:
	call_deferred("run")
func writable(path: String) -> bool:
	return G.owns(run_id) and not FileAccess.file_exists(path)
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2); return
	run_id=args[0]
	if not G.owns(run_id) or DisplayServer.get_name()=="headless":
		quit(2); return
	var settings=root.get_node_or_null("GameSettings")
	if settings!=null: settings.persist=false
	var viewport=SubViewport.new()
	viewport.size=Vector2i(800,520)
	viewport.world_3d=World3D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var demo=load("res://scenes/city/stair_landing_demo.tscn").instantiate()
	viewport.add_child(demo)
	var walker=Recorder.new()
	walker.collision_layer=2
	walker.collision_mask=1
	walker.safe_margin=.001
	walker.floor_snap_length=.24
	walker.floor_stop_on_slope=true
	var shape=CollisionShape3D.new()
	var capsule=CapsuleShape3D.new()
	capsule.radius=.18
	capsule.height=1.6
	shape.shape=capsule
	walker.add_child(shape)
	demo.add_child(walker)
	walker.position=Vector3(.5,.82,.8)
	while not walker.finished:
		await physics_frame
	var min_up_dy=0.0
	var max_up_dy=0.0
	var descent_rises=0
	for s in walker.samples:
		if s.phase==0:
			min_up_dy=min(min_up_dy,s.dy)
			max_up_dy=max(max_up_dy,s.dy)
		elif s.dy>.005: descent_rises+=1
	var metrics={"ticks":walker.ticks,"lifts":walker.lifts,"floor_ticks":walker.floor_ticks,"grounded_fraction":float(walker.floor_ticks)/walker.ticks,"ascent_min_dy_m":min_up_dy,"ascent_max_dy_m":max_up_dy,"descent_rise_ticks_above_5mm":descent_rises,"max_tick_distance_m":walker.max_tick_distance,"reached_top":walker.reached_top,"returned":walker.phase==1 and walker.position.z>.8,"samples":walker.samples.size()}
	print("TRAJECTORY ",JSON.stringify(metrics))
	if not walker.reached_top or walker.ticks>=900 or walker.floor_ticks<=walker.ticks*.8 or walker.lifts>18 or walker.position.z<=.8:
		quit(1);return
	var prefix="res://docs/city/trajectory-"+run_id
	var path=prefix+".json"
	if not writable(path): quit(2);return
	var f=FileAccess.open(path,FileAccess.WRITE)
	if f==null: quit(3);return
	f.store_string(JSON.stringify({"run_id":run_id,"controller_sha256":FileAccess.get_sha256("res://scripts/city/validate_stair_physics_walk.gd"),"physics_hz":Engine.physics_ticks_per_second,"metrics":metrics,"samples":walker.samples},"  "))
	f.close()
	# Measured capsule-center path. Colors distinguish ascent (cyan) / descent (orange).
	for phase in [0,1]:
		var mesh=ImmediateMesh.new()
		var material=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color(0.05,.85,1) if phase==0 else Color(1,.35,.05)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,material)
		for s in walker.samples:
			if s.phase==phase: mesh.surface_add_vertex(Vector3(s.x,s.y,s.z))
		mesh.surface_end()
		var node=MeshInstance3D.new()
		node.mesh=mesh
		demo.add_child(node)
	# Sparse true-size capsule silhouettes show footprint, not extra collision bodies.
	for i in range(30,walker.samples.size(),85):
		var s=walker.samples[i]
		var node=MeshInstance3D.new()
		var m=CapsuleMesh.new()
		m.radius=.18
		m.height=1.6
		node.mesh=m
		var mat=StandardMaterial3D.new()
		mat.albedo_color=Color(.1,.75,.9,.3)
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		node.material_override=mat
		demo.add_child(node)
		node.position=Vector3(s.x,s.y,s.z)
	var light=DirectionalLight3D.new()
	demo.add_child(light)
	light.rotation_degrees=Vector3(-45,-35,0)
	light.light_energy=1.5
	var camera=Camera3D.new()
	demo.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8.5
	camera.current=true
	var label=Label.new()
	label.text="Measured capsule-center trajectory | cyan: up / orange: down\n15 risers | "+str(walker.lifts)+" lifts | "+str(walker.floor_ticks)+"/"+str(walker.ticks)+" grounded ticks\nStatic trajectory diagnostic; not an animation or FPS benchmark"
	label.position=Vector2(14,12)
	label.add_theme_color_override("font_color",Color.WHITE)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	viewport.add_child(label)
	for spec in [["side",Vector3(10,2.2,-2.2)],["oblique",Vector3(8,6,4)]]:
		camera.position=spec[1]
		camera.look_at(Vector3(.5,2.2,-2.2),Vector3.UP)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		path=prefix+"-"+spec[0]+".jpg"
		if not writable(path): quit(2);return
		var err=viewport.get_texture().get_image().save_jpg(path,.90)
		print("RENDER ",path," ERROR ",err)
		if err!=OK: quit(3);return
	demo.free()
	viewport.free()
	quit(0)
