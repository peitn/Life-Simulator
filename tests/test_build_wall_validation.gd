extends SceneTree
const V = preload("res://scripts/world/build_wall_validation.gd")
var total := 0
var fail := 0
func _init() -> void:
	check([], "", "empty")
	check([s(1,1,4,1),s(3,1,6,1)], "overlap", "horizontal")
	check([s(1,1,1,5),s(1,4,1,7)], "overlap", "vertical")
	check([s(1,1,5,1),s(3,0,3,4)], "crossing", "cross")
	check([s(3,0,3,4),s(1,1,5,1)], "crossing", "cross reversed")
	check([s(1,1,3,1),s(3,1,6,1)], "", "join")
	check([s(1,1,5,1),s(5,1,5,4)], "", "corner")
	check([s(1,1,4,1),s(2,1,3,1)], "overlap", "contained")
	check([s(1,1,4,1),s(4,1,1,1)], "duplicate", "duplicate")
	check([s(1,1,5,1),s(3,1,3,4)], "", "T junction")
	check([s(1,1,1,5),s(1,3,4,3)], "", "T vertical")
	check([s(1,1,5,1),s(3,2,3,4)], "", "disjoint")
	var edges: Array = []
	for i in range(256):
		edges.append(s(i,0,i,1))
	check_custom(edges,256,1,"","max segments boundary")
	edges.append(s(256,0,256,1))
	check_custom(edges,257,1,"invalid_segments","over limit")
	check_custom([s(0,0,1,0)],0,1,"invalid_grid","zero width")
	check_custom([s(0,0,1,0)],201,201,"invalid_grid","grid area limit")
	check_custom([s(0,0,200,0)],200,200,"","exact area boundary")
	var crowded: Array = []
	for i in range(255):
		crowded.append(s(i,0,i,1))
	crowded.append(s(1,0,1,2))
	check_custom(crowded,256,2,"overlap","max segment overlap")
	print("WALL_REGRESSION %d/%d PASS" % [total-fail,total])
	quit(0 if fail==0 else 1)
func s(x0:int,z0:int,x1:int,z1:int) -> Dictionary:
	return {"x0":x0,"z0":z0,"x1":x1,"z1":z1}
func check(segments:Array, expected:String, label:String) -> void:
	total+=1
	var got:String=V.validate(segments,10,10)
	if got!=expected:
		fail+=1
		push_error("%s expected=%s got=%s" % [label,expected,got])

func check_custom(segments:Array, width:int, height:int, expected:String, label:String) -> void:
	total+=1
	var got:String=V.validate(segments,width,height)
	if got!=expected:
		fail+=1
		push_error("%s expected=%s got=%s" % [label,expected,got])
