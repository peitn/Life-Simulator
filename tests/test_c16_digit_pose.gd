extends SceneTree
## C16 isolated contract: UI mapping index,middle,ring,little,thumb
## to real Blender phalanges 2,3,4,5,1 for both hands.
const Assets=preload("res://scripts/assets/asset_library.gd")
const Sub=preload("res://scripts/assets/finger_phalange_subrig_c15.gd")
var passed:=0
var failed:=0
func ok(v:bool,n:String)->void:
 if v:passed+=1
 else:
  failed+=1
  print("FAIL "+n)
func _init()->void:
 call_deferred("run")
func run()->void:
 var actor=Assets.instantiate("character")
 root.add_child(actor)
 var sk=actor.get_node("Skeleton3D") as Skeleton3D
 ok(sk.get_bone_count()==17,"production player skeleton remains 17 bones")
 for side in ["l","r"]:
  var anchor=Sub.create_hand(sk,side)
  ok(anchor!=null,"real standalone 14-phalange rig "+side)
  if anchor==null:continue
  var rig:Skeleton3D=anchor.get_node("PhalangeRig")
  ok(rig.get_bone_count()==14,"all 14 segment bones exist "+side)
  for digit in 5:
   var atlas_id:int=1 if digit==4 else digit+2
   var first=rig.find_bone("finger_"+str(atlas_id)+"_1_"+side)
   var second=rig.find_bone("finger_"+str(atlas_id)+"_2_"+side)
   var third=rig.find_bone("finger_"+str(atlas_id)+"_3_"+side)
   ok(first>=0 and second>=0,"UI digit "+str(digit)+" maps to unique bone "+str(atlas_id)+side)
   ok((third<0)==(digit==4),"only thumb has two phalanges "+str(digit)+side)
   if first<0 or second<0:continue
   Sub.reset(anchor)
   var initial_first=rig.get_bone_pose_rotation(first)
   var initial_second=rig.get_bone_pose_rotation(second)
   ok(Sub.bend(anchor,digit,"proximal",.67),"UI proximal bends "+str(digit)+side)
   var f_rotation=rig.get_bone_pose_rotation(first)
   var s_rotation=rig.get_bone_pose_rotation(second)
   ok(not f_rotation.is_equal_approx(initial_first) and s_rotation.is_equal_approx(initial_second),
    "proximal rotates ONLY mapped finger base "+str(digit)+side)
   Sub.reset(anchor)
   ok(Sub.bend(anchor,digit,"distal",.85),"UI distal bends "+str(digit)+side)
   var d_rotation=rig.get_bone_pose_rotation(second)
   ok(not d_rotation.is_equal_approx(initial_second),"mapped distal bone rotates "+str(digit)+side)
   if third>=0:
    ok(not rig.get_bone_pose_rotation(third).is_equal_approx(Quaternion.IDENTITY),
     "third phalanx follows distal for 4 long fingers "+str(digit)+side)
   Sub.reset(anchor)
   ok(rig.get_bone_pose_rotation(first).is_equal_approx(initial_first)
     and rig.get_bone_pose_rotation(second).is_equal_approx(initial_second),
     "reset clears both real hinge angles "+str(digit)+side)
   var other:int=(digit+1)%5
   var other_atlas:int=1 if other==4 else other+2
   var oi=rig.find_bone("finger_"+str(other_atlas)+"_1_"+side)
   ok(rig.get_bone_pose_rotation(oi).is_equal_approx(rig.get_bone_rest(oi).basis.get_rotation_quaternion()),
     "other digit stays at rest "+str(digit)+side)
  ok(not Sub.bend(anchor,5,"proximal",.5) and
   not Sub.bend(anchor,0,"distal",NAN) and
   not Sub.bend(anchor,0,"x",.5),"invalid digit/finite/joint rejects "+side)
 print("C16_DIGIT_POSE_TEST ",passed," PASS ",failed," FAIL")
 quit(0 if failed==0 else 1)
