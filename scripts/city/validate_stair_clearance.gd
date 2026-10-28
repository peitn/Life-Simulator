extends "res://scripts/city/validate_stair_physics_walk.gd"
## Whole capsule traversal at three lateral offsets, with real overhead bodies.
func run() -> void:
	var fixtures: Array=[]
	for ceiling_y in [1.65,4.8]:
		for x in [.23,.50,.77]:
			var demo=load("res://scenes/city/stair_landing_demo.tscn").instantiate()
			root.add_child(demo); demo.position.x=fixtures.size()*3
			var ceiling:=StaticBody3D.new(); var col:=CollisionShape3D.new(); var slab:=BoxShape3D.new()
			slab.size=Vector3(1.4,.2,7); col.shape=slab; ceiling.add_child(col); demo.add_child(ceiling)
			ceiling.position=Vector3(.5,ceiling_y+.1,-2.25)
			var walker:=Walker.new(); walker.collision_layer=2; walker.collision_mask=1
			walker.safe_margin=.001; walker.floor_snap_length=.24; walker.floor_stop_on_slope=true
			var shape:=CollisionShape3D.new(); var cap:=CapsuleShape3D.new(); cap.radius=.18; cap.height=1.6; shape.shape=cap
			walker.add_child(shape); demo.add_child(walker); walker.position=Vector3(x,.82,.8)
			fixtures.append({"demo":demo,"walker":walker,"ceiling":ceiling,"height":ceiling_y,"x":x})
	for frame in range(930):
		var done:=true
		for item in fixtures:
			if not item.walker.finished: done=false
		if done: break
		await physics_frame
	for item in fixtures:
		var w:CharacterBody3D=item.walker
		var label="ceiling="+str(item.height)+" x="+str(item.x)
		check(w.finished,label+" bounded watchdog")
		check(absf(w.position.x-item.x)<.005,label+" no sideways escape")
		check(w.max_tick_distance<.26,label+" bounded motion")
		if item.height<2:
			check(not w.reached_top and w.phase==0,label+" low ceiling prevents ascent")
			check(w.max_y+.8<=item.height+.002,label+" capsule head never crosses ceiling")
			check(w.position.z>-.3,label+" stopped before penetrating first riser")
			check(w.lifts==0,label+" no forbidden upward lift")
		else:
			check(w.reached_top and w.phase==1 and w.position.z>.8,label+" complete return trip")
			check(w.is_on_floor() and absf(w.position.y-.8)<.025,label+" grounded at finish")
			check(w.floor_ticks>w.ticks*.8 and w.lifts<=18,label+" unchanged contact/lift gates")
			check(w.ascent_min_dy>-.05,label+" downward correction under5cm")
		print("CLEARANCE_SAMPLE ",label," ticks=",w.ticks," max_y=",w.max_y," lifts=",w.lifts," top=",w.reached_top)
		item.demo.free()
	print("STAIR_CLEARANCE ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
