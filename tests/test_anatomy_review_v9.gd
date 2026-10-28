extends SceneTree
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const Codec=preload("res://scripts/character/character_codec.gd")
const Validator=preload("res://scripts/character/character_validator.gd")
const Resolver=preload("res://scripts/character/appearance_resolver.gd")
const Hands=preload("res://scripts/assets/hand_detail_builder.gd")
const Randomizer=preload("res://scripts/character/character_randomizer.gd")
const Schema=preload("res://scripts/character/character_schema.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
    checks+=1
    if not ok:
        failures+=1
        print("FAIL ",label)
func _init():call_deferred("run")
func run():
    var d:Dictionary=CD.create().to_dict()
    d.identity.first_name="Nora"
    d.personality.traits=["optimista"]
    var old:Dictionary=d.duplicate(true)
    old.v=8
    old.body.erase("hand_size")
    var before:String=JSON.stringify(old)
    var migrated:Dictionary=Codec.from_dict(old)
    check(migrated.get("ok",false),"v8 adult imports")
    # Anatomy "v9" was renumbered to schema v18 (chained after psyche v9-v17) in the
    # 28 Oct rollback recovery; every older save still migrates to the current version.
    check(Schema.VERSION==18 and migrated.get("data",{}).get("v")==Schema.VERSION and migrated.get("data",{}).get("body",{}).get("hand_size")==0.0,"v8 migrates to neutral v18 hands")
    check(before==JSON.stringify(old),"migration preserves caller's old data")
    var v17:Dictionary=d.duplicate(true)
    v17.v=17
    v17.body.erase("hand_size")
    var m17:Dictionary=Codec.from_dict(v17)
    check(m17.get("ok",false) and m17.get("data",{}).get("v")==18 and m17.get("data",{}).get("body",{}).get("hand_size")==0.0 and not v17.body.has("hand_size"),"v17 (psyche J) migrates to v18 with neutral hands, input untouched")
    for value in [-1.0,0.0,1.0]:
        d.body.hand_size=value
        check(Validator.validate(d,{"mode":"strict"}).get("ok",false),"valid hand size")
        var decoded:Dictionary=Codec.decode_code(Codec.encode_code(d),{"mode":"strict"})
        check(decoded.get("ok",false) and is_equal_approx(float(decoded.get("data",{}).get("body",{}).get("hand_size",99)),value),"hand size survives share/save codec")
        check(is_equal_approx(Resolver.resolve(d).hand_scale,1.0+.2*value),"deterministic physical hand scale")
    d.body.hand_size=1.1
    check(not Validator.validate(d,{"mode":"strict"}).get("ok",false),"reject out of range hand size")
    d.body.hand_size=0.0
    var preview=Preview.new()
    root.add_child(preview)
    preview.show_draft(d)
    var v=preview.visual
    for anim in v.find_children("*","AnimationPlayer",true,false):anim.stop()
    var skin:MeshInstance3D=v._hand_detail_nodes[0]
    var nail:MeshInstance3D=v._hand_detail_nodes[1]
    check(skin.material_override==v._mats.get("skin_body"),"finger and palm share exact skin shader")
    check(v._foot_detail_nodes[0].material_override==skin.material_override,"feet share actual body material")
    check(bool(skin.mesh.surface_get_format(0)&Mesh.ARRAY_FORMAT_CUSTOM0),"skin rest coordinates supplied to shader")
    var sm:Array=skin.mesh.surface_get_blend_shape_arrays(0)
    var nm:Array=nail.mesh.surface_get_blend_shape_arrays(0)
    for digit in 10:
        for morph in 10:
            var a:PackedVector3Array=sm[morph][Mesh.ARRAY_VERTEX]
            var b:PackedVector3Array=nm[morph][Mesh.ARRAY_VERTEX]
            check(a[digit*51].distance_to(b[digit*9])<.000001,"nail and digit have identical body displacement")
        var root_pos:Vector3=Hands.finger_endpoints(digit).root
        if digit%5==4:
            check(absf(root_pos.x)<.307,"thumb sits on medial edge of palm")
    for side in [0,5]:
        var lengths: Array=[]
        for finger in 4:
            var e=Hands.finger_endpoints(side+finger)
            lengths.append(e.root.distance_to(e.tip))
        check(lengths[1]>lengths[0] and lengths[1]>lengths[2] and lengths[3]<lengths[0] and lengths[3]<lengths[2],"middle longest and little shortest")
    var sizes: Array=[]
    for value in [-1.0,1.0,0.0]:
        d.body.hand_size=value
        preview.show_draft(d)
        var sk:Skeleton3D=v._skeleton()
        sk.force_update_all_bone_transforms()
        check(is_equal_approx(sk.get_bone_pose_scale(sk.find_bone("hand_l")).x,1.0+.2*value),"left hand uses requested scale")
        check(is_equal_approx(sk.get_bone_pose_scale(sk.find_bone("hand_r")).x,1.0+.2*value),"right hand uses requested scale")
        var points:PackedVector3Array=posed(v,skin)
        sizes.append(points[50].distance_to(points[0]))
    check(absf(sizes[1]/sizes[0]-1.5)<.005,"actual GPU-source geometry is 50% larger at opposite size endpoints")
    check(absf(sizes[2]/sizes[0]-1.25)<.005,"reset returns actual geometry to neutral size")
    var foot:MeshInstance3D=v._foot_detail_nodes[0]
    var sk:Skeleton3D=v._skeleton()
    var reference:PackedVector3Array=posed(v,foot)
    sk.set_bone_pose_rotation(sk.find_bone("foot_l"),Quaternion(Vector3.RIGHT,.6))
    sk.force_update_all_bone_transforms()
    var bent:PackedVector3Array=posed(v,foot)
    var raw:PackedVector3Array=foot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var max_top:=0.0
    var max_toe:=0.0
    for i in raw.size():
        if raw[i].x>0 and raw[i].y>.17:max_top=maxf(max_top,reference[i].distance_to(bent[i]))
        if raw[i].x>0 and raw[i].z>.15:max_toe=maxf(max_toe,reference[i].distance_to(bent[i]))
    check(max_top<.0001,"ankle upper shaft stays attached to shin when foot bends")
    check(max_toe>.015,"toes genuinely follow foot flexion")
    sk.set_bone_pose_rotation(sk.find_bone("foot_l"),Quaternion.IDENTITY)
    var rng=RandomNumberGenerator.new()
    rng.seed=92321
    var seen:Dictionary={}
    for i in 24:
        var generated:Dictionary=Randomizer.generate(rng)
        seen[snappedf(generated.body.hand_size,.01)]=true
    check(seen.size()>12,"generated people have varied hand proportions")
    for body in [{"frame":0.0,"body_fat":0.0,"muscle":0.0,"shoulders":0.0,"hips":0.0},{"frame":1.0,"body_fat":1.0,"muscle":1.0,"shoulders":1.0,"hips":1.0}]:
        d.body.merge(body,true)
        for hand_size in [-1.0,1.0]:
            d.body.hand_size=hand_size
            preview.show_draft(d)
            for gesture in ["open","relaxed","fist","point","pinch"]:
                check(v.set_hand_pose(gesture),"gesture accepted across body and hand-size extremes")
                for mi in v._hand_detail_nodes+v._foot_detail_nodes:
                    var points:PackedVector3Array=posed(v,mi)
                    var ids:PackedInt32Array=mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
                    var valid:=true
                    for t in range(0,ids.size(),3):
                        var a:Vector3=points[ids[t]]
                        var b:Vector3=points[ids[t+1]]
                        var c:Vector3=points[ids[t+2]]
                        if not a.is_finite() or (b-a).cross(c-a).length_squared()<1e-17: valid=false
                    check(valid,"actual posed anatomy has finite, noncollapsed faces")
    preview.free()
    await process_frame
    print("ANATOMY_V9_RESULT checks=",checks," failures=",failures)
    quit(0 if failures==0 else 1)
func posed(v,mi:MeshInstance3D)->PackedVector3Array:
    var m:Mesh=mi.mesh
    var ar:Array=m.surface_get_arrays(0)
    var base:PackedVector3Array=ar[Mesh.ARRAY_VERTEX]
    var points:PackedVector3Array=base.duplicate()
    var blends:Array=m.surface_get_blend_shape_arrays(0)
    for k in blends.size():
        var weight:float=mi.get_blend_shape_value(k)
        if is_zero_approx(weight):continue
        var target:PackedVector3Array=blends[k][Mesh.ARRAY_VERTEX]
        for i in points.size():points[i]+=(target[i] if m.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_RELATIVE else target[i]-base[i])*weight
    var sk:Skeleton3D=v._skeleton()
    sk.force_update_all_bone_transforms()
    var xfs:Array=[]
    for i in mi.skin.get_bind_count():
        var name:String=mi.skin.get_bind_name(i)
        var bone:int=sk.find_bone(name) if name!="" else mi.skin.get_bind_bone(i)
        xfs.append(sk.get_bone_global_pose(bone)*mi.skin.get_bind_pose(i))
    var bones:PackedInt32Array=ar[Mesh.ARRAY_BONES]
    var weights:PackedFloat32Array=ar[Mesh.ARRAY_WEIGHTS]
    for i in points.size():
        var point:=Vector3.ZERO
        for j in 4:point+=(xfs[bones[i*4+j]]*points[i])*weights[i*4+j]
        points[i]=point
    return points
