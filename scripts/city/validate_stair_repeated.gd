extends "res://scripts/city/validate_stair_physics_walk.gd"
class Repeater extends Walker:
	var trips: Array=[]
	func _physics_process(delta:float) -> void:
		if finished:return
		super._physics_process(delta)
		if finished and reached_top and phase==1 and position.z>.8:
			trips.append({"ticks":ticks,"lifts":lifts,"floor":floor_ticks,"drop":ascent_min_dy,"distance":max_tick_distance})
			if trips.size()<2:
				finished=false; phase=0; reached_top=false; ticks=0; lifts=0; floor_ticks=0
				ascent_min_dy=0; max_y=0; max_tick_distance=0
func run() -> void:
	var fixture=load("res://scenes/city/stair_landing_demo.tscn").instantiate(); root.add_child(fixture)
	var walkers:Array=[]
	for x in [.23,.5,.77]:
		var w:=Repeater.new(); w.collision_layer=2; w.collision_mask=1; w.safe_margin=.001; w.floor_snap_length=.24
		var shape:=CollisionShape3D.new(); var cap:=CapsuleShape3D.new(); cap.height=1.6; cap.radius=.18; shape.shape=cap
		w.add_child(shape); fixture.add_child(w); w.position=Vector3(x,.82,.8); walkers.append(w)
	for frame in range(1920):
		var done:=true
		for w in walkers:
			if not w.finished:done=false
		if done:break
		await physics_frame
	for w in walkers:
		check(w.trips.size()==2,"two consecutive trips at x="+str(w.position.x))
		for trip in w.trips:
			check(trip.ticks>300 and trip.ticks<900,"bounded trip")
			check(trip.lifts>0 and trip.lifts<=18,"unchanged lift limit")
			check(trip.floor>trip.ticks*.8,"unchanged contact fraction")
			check(trip.drop>-.05,"ascent downward correction under5cm")
			check(trip.distance<.26,"bounded tick displacement")
		check(w.is_on_floor() and absf(w.position.y-.8)<.025,"final floor contact")
		print("REPEATED_SAMPLE x=",w.position.x," trips=",JSON.stringify(w.trips))
	fixture.free()
	print("STAIR_REPEATED ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
