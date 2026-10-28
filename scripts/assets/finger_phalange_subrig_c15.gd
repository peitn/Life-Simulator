extends RefCounted
## C15: independently articulated 28-bone FINGER SKELETON inside the
## production character hierarchy. Each hand is a 14-bone Skeleton3D,
## anchored by BoneAttachment3D to the corresponding existing hand bone.
## Reference lengths/rest positions come from the real 194-bone Blender atlas.
## Each bone has a small mesh attached, so its motion is actually bone-driven.
## No runtime collision, physics impulses, fingertip contact, or gameplay RPC.
const Atlas=preload("res://scripts/assets/anatomy_overlay.gd")
const Hand=preload("res://scripts/assets/hand_detail_builder.gd")
const SEGMENTS_PER_HAND := 14
const RADIAL := 9
const SUPPORTED_SIDES := ["l","r"]

static func _vec(a:Array)->Vector3:
    return Vector3(float(a[0]),float(a[1]),float(a[2]))

static func _bone_entries(side:String)->Array:
    if side not in SUPPORTED_SIDES:
        return []
    var data:Dictionary=Atlas.reference_data()
    if data.is_empty():return []
    var rows:Array=[]
    for raw in data.get("bones",[]):
        var entry:Dictionary=raw
        if (String(entry.get("n","")).begins_with("finger_") and
                String(entry.get("n","")).ends_with("_"+side)):
            rows.append(entry)
    rows.sort_custom(func(a,b):
        var x:String=str(a.get("n",""))
        var y:String=str(b.get("n",""))
        return x.naturalnocasecmp_to(y)<0)
    return rows

static func _cylinder(length:float,radius:float)->CylinderMesh:
    var mesh:=CylinderMesh.new()
    mesh.height=maxf(.004,length)
    mesh.top_radius=maxf(.0015,radius*.85)
    mesh.bottom_radius=maxf(.0015,radius*1.06)
    mesh.radial_segments=RADIAL
    mesh.rings=1
    return mesh


static func create_hand(production:Skeleton3D,side:String)->BoneAttachment3D:
    if production==null or side not in SUPPORTED_SIDES:
        return null
    if production.get_bone_count()!=17 or production.find_bone("hand_"+side)<0:
        return null
    var data:Array=_bone_entries(side)
    if data.size()!=SEGMENTS_PER_HAND:
        return null
    var names:Dictionary={}
    var parsed:Dictionary={}
    for item in data:
        var n:String=str(item.get("n",""))
        if names.has(n) or not n.begins_with("finger_"):
            return null
        names[n]=true
        parsed[n]=item
    # C16 diagnostic retarget: translate each digit from Blender atlas
    # coordinates to existing gameplay hand root; preserve lengths and pose.
    var rest_offsets:Dictionary={}
    for item in data:
        var token:PackedStringArray=String(item["n"]).split("_")
        if token.size()!=4 or int(token[2])!=1:
            continue
        var atlas_digit:int=int(token[1])
        var game_digit:int=4 if atlas_digit==1 else atlas_digit-2
        if game_digit<0 or game_digit>4:
            return null
        var game_index:int=game_digit+(5 if side=="l" else 0)
        var endpoint:Dictionary=Hand.finger_endpoints(game_index)
        if endpoint.is_empty():return null
        var delta:Vector3=(endpoint["root"] as Vector3)-_vec(item["h"])
        if not delta.is_finite() or delta.length()>.120:
            return null
        rest_offsets[atlas_digit]=delta
    if rest_offsets.size()!=5:return null
    var attachment:=BoneAttachment3D.new()
    attachment.name="C15_FingerRoot_"+side
    attachment.bone_name="hand_"+side
    production.add_child(attachment)
    var rig:=Skeleton3D.new()
    rig.name="PhalangeRig"
    attachment.add_child(rig)
    var hand_bone:int=production.find_bone("hand_"+side)
    var inv_hand:Transform3D=production.get_bone_global_rest(hand_bone).affine_inverse()
    var local_rest:Dictionary={}
    for item in data:
        var name:String=str(item["n"])
        var atlas_digit:int=int(name.split("_")[1])
        var offset:Vector3=rest_offsets[atlas_digit]
        var head:Vector3=inv_hand*(_vec(item["h"])+offset)
        var tail:Vector3=inv_hand*(_vec(item["t"])+offset)
        var axis:Vector3=tail-head
        if axis.length()<.004:
            attachment.queue_free()
            return null
        var rest:=Transform3D(Basis(Quaternion(Vector3.UP,axis.normalized())),head)
        local_rest[name]=rest
        rig.add_bone(name)
    for item in data:
        var name:String=str(item["n"])
        var tokens:PackedStringArray=name.split("_")
        if tokens.size()!=4:
            attachment.queue_free()
            return null
        var segment:int=int(tokens[2])
        var idx:int=rig.find_bone(name)
        var parent_name:String="finger_"+tokens[1]+"_"+str(segment-1)+"_"+side
        var rest:Transform3D=local_rest[name]
        if segment>1 and names.has(parent_name):
            var parent:int=rig.find_bone(parent_name)
            rig.set_bone_parent(idx,parent)
            rest=local_rest[parent_name].affine_inverse()*rest
        rig.set_bone_rest(idx,rest)
    var bone_mat:=StandardMaterial3D.new()
    bone_mat.resource_name="C15_BoneDiagnostic_"+side
    bone_mat.albedo_color=Color(.86,.77,.58) if side=="l" else Color(.78,.72,.57)
    bone_mat.roughness=.68
    for item in data:
        var name:String=str(item["n"])
        var idx:int=rig.find_bone(name)
        var head:Vector3=_vec(item["h"])
        var tail:Vector3=_vec(item["t"])
        var original_length:float=head.distance_to(tail)
        var driver:=BoneAttachment3D.new()
        driver.name="Drive_"+name
        driver.bone_name=name
        rig.add_child(driver)
        var mesh:=MeshInstance3D.new()
        mesh.name="Phalanx_"+name
        mesh.mesh=_cylinder(original_length,float(item["r"]))
        mesh.material_override=bone_mat
        mesh.position=Vector3(0,original_length*.5,0)
        mesh.set_meta("anatomy_source_bone",name)
        driver.add_child(mesh)
    rig.reset_bone_poses()
    rig.force_update_all_bone_transforms()
    rig.set_meta("actual_28_blender_bones_source",true)
    rig.set_meta("segment_count",SEGMENTS_PER_HAND)
    rig.set_meta("gameplay_collision_enabled",false)
    attachment.visible=false
    return attachment


## Pose either of the 2 proximal/distal controls for the appropriate digit.
## This rotates REAL separate Skeleton3D bones (not just skin morph deltas).
## The optional third phalanx follows the second with 30% of its angle.
static func bend(root:BoneAttachment3D,digit:int,
        joint:String,strength:float)->bool:
    if root==null or digit<0 or digit>=5:
        return false
    if joint not in ["proximal","distal"] or not is_finite(strength):
        return false
    if strength<0.0 or strength>1.0:
        return false
    var side:String="l" if root.name.ends_with("_l") else ("r" if root.name.ends_with("_r") else "")
    if side not in SUPPORTED_SIDES:
        return false
    var rig:Skeleton3D=root.get_node_or_null("PhalangeRig")
    if rig==null or rig.get_bone_count()!=SEGMENTS_PER_HAND:
        return false
    # UI digit order index,middle,ring,little,thumb differs from
    # anatomical atlas order thumb,index,middle,ring,little.
    var digit_number:int=1 if digit==4 else digit+2
    var segment:int=1 if joint=="proximal" else 2
    var name:String="finger_"+str(digit_number)+"_"+str(segment)+"_"+side
    var idx:int=rig.find_bone(name)
    if idx<0:
        return false
    var angle:float=.74*strength if joint=="proximal" else .66*strength
    rig.set_bone_pose_rotation(idx,Quaternion(Vector3.RIGHT,angle))
    if joint=="distal" and digit!=4:
        var end_bone:int=rig.find_bone("finger_"+str(digit_number)+"_3_"+side)
        if end_bone>=0:
            rig.set_bone_pose_rotation(end_bone,Quaternion(Vector3.RIGHT,angle*.30))
    rig.force_update_all_bone_transforms()
    return true


static func reset(root:BoneAttachment3D)->void:
    if root==null:return
    var rig:Skeleton3D=root.get_node_or_null("PhalangeRig")
    if rig!=null:rig.reset_bone_poses()