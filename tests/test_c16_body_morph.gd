extends SceneTree
const V=preload("res://scripts/sim/sim_visual.gd")
const CD=preload("res://scripts/character/character_data.gd")
const Hand=preload("res://scripts/assets/hand_detail_builder.gd")
var pass_count:=0
var fail_count:=0
func chk(b:bool,s:String)->void:
 if b:pass_count+=1
 else:fail_count+=1;print("FAIL "+s)
func _init()->void:call_deferred("run")
func run()->void:
 var v=V.new()
 root.add_child(v)
 await process_frame
 chk(v.set_finger_skeletal_view(true),"view enabled")
 var sk:Skeleton3D=v.get_node("Body/Model/Skeleton3D")
 var anchors:Dictionary=v.get("_finger_skeletal_anchors")
 var a=v.get("_anim") as AnimationPlayer
 if a!=null:a.pause()
 var cd=CD.create()
 for height in [145.0,172.0,205.0]:
  for fat in [0.0,1.0]:
   cd.body["height_cm"]=height
   cd.body["body_fat"]=fat
   cd.body["frame"]=fat
   v.apply_look(cd.public_snapshot())
   await process_frame
   chk(v.finger_skeletal_view(),"kept in-world skeletal view "+str(height))
   for side in ["l","r"]:
    var rig:Skeleton3D=anchors[side].get_node("PhalangeRig")
    chk(rig.get_bone_count()==14,"14 phalanx bones after reshape "+side)
    for digit in 5:
     var id:int=1 if digit==4 else digit+2
     var bone:int=rig.find_bone("finger_"+str(id)+"_1_"+side)
     var origin:Vector3=rig.to_global(rig.get_bone_global_pose(bone).origin)
     chk(origin.is_finite(),"finite bone position "+side+str(digit))
     chk(v.set_finger_joint_bend(side,digit,"proximal",.45),"bend valid after reshape "+side+str(digit))
     var r:Quaternion=rig.get_bone_pose_rotation(bone)
     chk(r.is_finite(),"finite bend rotation "+side+str(digit))
   print("C16_MORPH_PROFILE ",height," fat=",fat," scale=",v.get_node("Body/Model").scale)
 chk(v.set_finger_skeletal_view(false),"restore player normal hands")
 print("C16_MORPH_INVARIANT ",pass_count," PASS ",fail_count," FAIL")
 quit(0 if fail_count==0 else 1)
