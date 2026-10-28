extends SceneTree
const Assets=preload("res://scripts/assets/asset_library.gd")
const Sub=preload("res://scripts/assets/finger_phalange_subrig_c15.gd")
const Hand=preload("res://scripts/assets/hand_detail_builder.gd")
const Atlas=preload("res://scripts/assets/anatomy_overlay.gd")
var failures:int=0
var passed:int=0

func check(flag:bool,label:String)->void:
 if flag:
  passed+=1
 else:
  failures+=1
  print("FAIL "+label)

func _init()->void:
 call_deferred("go")

func go()->void:
 var c=Assets.instantiate("character")
 root.add_child(c)
 var sk:Skeleton3D=c.get_node("Skeleton3D")
 var body:MeshInstance3D
 for m in Assets.parts_in_group(c,"body"):
  if Assets.part_material_name(m)=="skin_body":
   body=m
   break
 check(body!=null,"body source found")
 if body==null:quit(3);return
 var vertices:PackedVector3Array=body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 for side in ["l","r"]:
  var anchor=Sub.create_hand(sk,side)
  check(anchor!=null,"true subrig exists "+side)
  var rig:Skeleton3D=anchor.get_node("PhalangeRig")
  check(rig.get_bone_count()==14,"14 true articulated bones "+side)
  for digit in 5:
   var phalange_id:int=[2,3,4,5,1][digit]
   var finger_global_id:int=digit+(5 if side=="l" else 0)
   var ref:Vector3=Hand.finger_endpoints(finger_global_id)["root"]
   var name:String="finger_"+str(phalange_id)+"_1_"+side
   var idx:int=rig.find_bone(name)
   check(idx>=0,"real corresponding Blender bone "+name)
   var actual:Vector3=rig.to_global(rig.get_bone_global_rest(idx).origin)
   var alignment:float=actual.distance_to(ref)
   check(alignment<.0001,"bone root matches existing playable hand reference "+name)
   var min_distance:float=INF
   for pt in vertices:
    var gp:Vector3=body.to_global(pt)
    min_distance=minf(min_distance,gp.distance_to(actual))
   check(min_distance<.010,"root within 10mm nearest neutral palm vertex "+name)
   print("ROOT_REST "+side+" "+str(digit)+"="+str(snappedf(min_distance*1000,.01))+"mm; residual="+str(snappedf(alignment*1000,.01))+"mm")
   var parent:Transform3D=rig.get_bone_global_rest(idx)
   var end_idx:int=rig.find_bone("finger_"+str(phalange_id)+"_2_"+side)
   check(end_idx>=0 and rig.get_bone_parent(end_idx)==idx,"original phalange parent hierarchy preserved "+name)
   var before:Transform3D=rig.get_bone_global_pose(end_idx)
   check(Sub.bend(anchor,digit,"proximal",.75),"real independent proximal bone rotation "+name)
   var after:Transform3D=rig.get_bone_global_pose(end_idx)
   check(not before.is_equal_approx(after),"descendant moves with new aligned proximal joint "+name)
 check(passed>=62,"expected test coverage")
 print("C16_ISOLATED_REALIGN "+str(passed)+" PASS "+str(failures)+" FAIL")
 quit(0 if failures==0 else 2)
