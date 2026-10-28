extends SceneTree
const V=preload("res://scripts/sim/sim_visual.gd")
var passed:=0
var failed:=0
func ok(b:bool,s:String)->void:
 if b:passed+=1
 else:
  failed+=1
  print("FAIL "+s)
func _init()->void:call_deferred("go")
func go()->void:
 var v=V.new()
 root.add_child(v)
 await process_frame
 ok(v.uses_model(),"real live player character")
 var sk:Skeleton3D=v.get_node("Body/Model/Skeleton3D")
 ok(sk.get_bone_count()==17,"original 17 gameplay bones")
 ok(v.set_finger_skeletal_view(true),"skeletal hand mode available")
 var anchors:Dictionary=v.get("_finger_skeletal_anchors")
 ok(anchors.size()==2,"two real hand subrigs")
 var old_visibility:Array=[]
 for m in v._hand_detail_nodes:old_visibility.append(m.visible)
 ok(old_visibility==[false,false],"surface fingers hide while subrig visible")
 var animator:AnimationPlayer=v.get("_anim")
 if animator!=null:animator.pause()
 for side in ["l","r"]:
  var a:BoneAttachment3D=anchors[side]
  var rig:Skeleton3D=a.get_node("PhalangeRig")
  ok(rig.get_bone_count()==14,"14 separate phalanges "+side)
  for digit in 5:
   var atlas:int=1 if digit==4 else digit+2
   var b:int=rig.find_bone("finger_"+str(atlas)+"_1_"+side)
   var c:int=rig.find_bone("finger_"+str(atlas)+"_2_"+side)
   ok(b>=0 and c>=0,"mapped finger="+str(digit)+side)
   var before:Quaternion=rig.get_bone_pose_rotation(b)
   ok(v.set_finger_joint_bend(side,digit,"proximal",.7),"proximal accepted "+str(digit)+side)
   ok(not before.is_equal_approx(rig.get_bone_pose_rotation(b)),"real bone flex "+str(digit)+side)
   ok(v.set_finger_joint_bend(side,digit,"distal",.4),"distal accepted "+str(digit)+side)
   ok(not rig.get_bone_pose_rotation(c).is_equal_approx(rig.get_bone_rest(c).basis.get_rotation_quaternion()),"real second phalanx flex "+str(digit)+side)
   ok(v.set_finger_curl(side,digit,0.0),"reset combined "+str(digit)+side)
  var p:int=sk.find_bone("hand_"+side)
  var q:int=rig.find_bone("finger_2_1_"+side)
  sk.force_update_all_bone_transforms()
  var start:Vector3=rig.to_global(rig.get_bone_global_pose(q).origin)
  var old:Quaternion=sk.get_bone_pose_rotation(p)
  sk.set_bone_pose_rotation(p,old*Quaternion(Vector3.FORWARD,.55))
  sk.force_update_all_bone_transforms()
  rig.force_update_all_bone_transforms()
  await process_frame
  var next:Vector3=rig.to_global(rig.get_bone_global_pose(q).origin)
  print("WRIST_DEBUG ",side," before=",start," after=",next," anchor=",a.global_position," handpose=",sk.get_bone_pose_rotation(p))
  ok(start.distance_to(next)>.001,"finger rig follows actual gameplay wrist "+side)
  sk.set_bone_pose_rotation(p,old)
  sk.force_update_all_bone_transforms()
 ok(v.set_finger_skeletal_view(false),"can return to normal skinned finger meshes")
 ok(not v._finger_skeletal_anchors["l"].visible and v._hand_detail_nodes[0].visible,"normal hand skin restored")
 print("C16_LIVE_ATTACHMENT_TEST ",passed," PASS ",failed," FAIL")
 quit(0 if failed==0 else 1)
