extends SceneTree
## Ten real independently addressable GPU finger morphs in the skinned body,
## matching ten deformable fingernail surfaces and the user-visible preview.
## These remain procedural joint-like bends, NOT true skeletal phalanges.
const Preview := preload("res://scripts/ui/character_preview.gd")
const Data := preload("res://scripts/character/character_data.gd")
const G := preload("res://tools/automation_lock.gd")

var passes := 0
var failures := 0
func check(ok: bool, description: String) -> void:
    passes += int(ok)
    failures += int(not ok)
    if not ok:
        print("FAIL ",description)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var preview:=Preview.new()
    root.add_child(preview)
    var visual=preview.visual
    check(visual._hand_detail_nodes.size()==2,"hand skin+nails instances present")
    if visual._hand_detail_nodes.size()!=2:
        quit(2)
        return
    var skin:MeshInstance3D=visual._hand_detail_nodes[0]
    var nail:MeshInstance3D=visual._hand_detail_nodes[1]
    for part in [skin,nail]:
        var label:String=String(part.name)
        var mesh:Mesh=part.mesh
        check(mesh.get_blend_shape_count()==20,label+" includes original ten body morphs plus 10 curls")
        var source:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        var morphs:Array=mesh.surface_get_blend_shape_arrays(0)
        var chunk:int=51 if part==skin else 9
        check(source.size()==chunk*10,label+" deterministic per-digit vertex grouping")
        for digit in 10:
            var name:StringName=StringName("finger_curl_"+str(digit))
            var index:int=part.find_blend_shape_by_name(name)
            check(index==10+digit,label+" unique GPU blend shape for digit "+str(digit))
            if index<0:continue
            var verts:PackedVector3Array=morphs[index][Mesh.ARRAY_VERTEX]
            var norms:PackedVector3Array=morphs[index][Mesh.ARRAY_NORMAL]
            check(verts.size()==source.size() and norms.size()==source.size(),
                label+" curl vertex/normal target matches topology "+str(digit))
            var changed:=0
            var spill:=0
            var max_delta:=0.0
            for v in source.size():
                # RELATIVE target array stores zero for unaffected vertices,
                # not their rest-space absolute positions.
                var displacement:float=verts[v].length()
                max_delta=maxf(max_delta,displacement)
                if v/chunk==digit and displacement>.00001:
                    changed+=1
                elif v/chunk!=digit and displacement>.000000001:
                    spill+=1
            check(changed>=2 and max_delta>.002 and max_delta<.12,
                label+" actually bends only selected finger "+str(digit))
            check(spill==0,label+" no changes on neighboring 9 digits "+str(digit))
        for base_morph in 10:
            check(part.find_blend_shape_by_name(mesh.get_blend_shape_name(base_morph))==base_morph,
                label+" original body shape key index stable "+str(base_morph))
    check(visual.hand_pose_name()=="relaxed","natural relaxed hand pose initially selected")
    check(not visual.set_hand_pose("arbitrary"),"unknown hand gesture rejected")
    check(not visual.set_finger_curl("invalid",0,1.0),"invalid left/right side rejected")
    check(not visual.set_finger_curl("l",5,1.0),"out of range finger rejected")
    check(not visual.set_finger_curl("l",0,-.1),"negative bend rejected")
    check(not visual.set_finger_curl("l",0,INF),"nonfinite bend rejected")
    check(not visual.set_finger_curl("l",0,1.1),"overshoot rejected")
    check(visual.set_hand_pose("open"),"open hand gesture accepted")
    for digit in 10:
        check(is_zero_approx(skin.get_blend_shape_value(10+digit)),
            "open hand straightens finger "+str(digit))
    check(visual.set_finger_curl("l",2,.87),"one left ring finger can curl")
    check(is_equal_approx(skin.get_blend_shape_value(17),.87)
        and is_equal_approx(nail.get_blend_shape_value(17),.87),
        "nail follows curled left ring finger exactly")
    for digit in 10:
        if digit==7:continue
        check(is_zero_approx(skin.get_blend_shape_value(10+digit)),
            "all other fingers stay open including opposite hand "+str(digit))
    check(visual.set_hand_pose("fist"),"independent fingers make two closed fists")
    for side in [0,5]:
        for finger in 5:
            var expected:float=.84 if finger==4 else 1.0
            check(is_equal_approx(skin.get_blend_shape_value(10+side+finger),expected),
                "all requested five curled "+str(side)+"/"+str(finger))
    check(visual.set_hand_pose("point"),"pointing hand pose available")
    check(is_zero_approx(skin.get_blend_shape_value(10)) and
        is_zero_approx(skin.get_blend_shape_value(15)) and
        is_equal_approx(skin.get_blend_shape_value(11),.98),
        "point pose extends both index fingers and curls middle")
    check(visual.set_hand_pose("pinch"),"pinch gesture available")
    check(is_equal_approx(skin.get_blend_shape_value(14),.75) and
        is_equal_approx(nail.get_blend_shape_value(14),.75),
        "thumb and fingernail curl while other fingers differ")
    # Preview controls do not create, write, or validate private CharacterData.
    var data:Dictionary=Data.create().to_dict()
    data["identity"]["first_name"]="Nora"
    data["personality"]["traits"]=["optimista"]
    preview.show_draft(data)
    var before:Dictionary=preview.public_snapshot()
    var chooser:OptionButton=preview._hand_pose_picker
    check(chooser!=null and chooser.item_count==5,"creator/editor preview has five real hand poses")
    chooser.select(2)
    chooser.item_selected.emit(2)
    check(visual.hand_pose_name()=="fist","preview selector changes real finger GPU bends")
    check(preview.public_snapshot()==before,"preview gesture never modifies character data")
    preview._toggle_hand_detail()
    check(preview._hand_closeup and preview.camera.size<.5,"preview can zoom on hand geometry")
    preview._toggle_hand_detail()
    check(not preview._hand_closeup and preview.camera.size>2.0,"full character framing recoverable")
    var other:=Preview.new()
    root.add_child(other)
    check(other.visual._hand_detail_nodes[0].mesh==skin.mesh,
        "multiple agents share immutable geometry buffers")
    check(other.visual._hand_detail_nodes[0].get_blend_shape_value(10)!=
        skin.get_blend_shape_value(10),
        "but maintain per-agent separate finger pose")
    check(other.public_snapshot()!=before,"other agent preview does not inherit private draft")
    other.queue_free()
    if DisplayServer.get_name()!="headless":
        var args:=OS.get_cmdline_user_args()
        var rid:String=String(args[0]) if args.size()==1 else ""
        check(G.owns(rid),"visual captures require actual owned project lock")
        if not G.owns(rid):
            quit(3)
            return
        preview._hand_closeup=true
        preview._frame_character()
        preview.viewport.size=Vector2i(720,540)
        preview.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
        for pose in ["open","fist","point","pinch"]:
            visual.set_hand_pose(pose)
            for i in 8:await process_frame
            await RenderingServer.frame_post_draw
            var filename:String="res://previews/"+rid+"-fingers-"+pose+".jpg"
            check(preview.viewport.get_texture().get_image().save_jpg(filename,.89)==OK,
                "real Godot preview captured "+pose)
    preview.queue_free()
    await process_frame
    print("FINGER_ARTICULATION_RESULT checks=",passes+failures," passed=",passes," failed=",failures)
    quit(0 if failures==0 else 1)