extends SceneTree
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const G=preload("res://tools/automation_lock.gd")
func _init():call_deferred("run")
func run():
    var args=OS.get_cmdline_user_args()
    if args.size()!=1 or not G.owns(args[0]):quit(2);return
    var lease:String=args[0]
    var p=Preview.new()
    root.add_child(p)
    var d:Dictionary=CD.create().to_dict()
    d.identity.first_name="Nora"
    d.hair.style="mikado"
    d.clothing.bezne.top="kawaii_kocici_mikina"
    d.clothing.bezne.shoes="bosy"
    d.clothing.bezne.top_color="#c470a0"
    p.viewport.size=Vector2i(720,720)
    p.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    var cases=[
        {"id":"small","hand":-1.0,"body":{},"pose":"open","camera":Vector3(0,.85,3),"target":Vector3(0,.85,0),"extent":.52},
        {"id":"large","hand":1.0,"body":{},"pose":"open","camera":Vector3(0,.85,3),"target":Vector3(0,.85,0),"extent":.52},
        {"id":"relaxed","hand":0.0,"body":{},"pose":"relaxed","camera":Vector3(.4,1.1,3),"target":Vector3(0,.86,0),"extent":.64},
        {"id":"fist","hand":1.0,"body":{"frame":1.0,"body_fat":1.0,"shoulders":1.0},"pose":"fist","camera":Vector3(.5,1.2,3),"target":Vector3(0,.86,0),"extent":.70},
        {"id":"whole","hand":0.0,"body":{},"pose":"relaxed","camera":Vector3(.9,1.8,3),"target":Vector3(0,.88,0),"extent":2.0},
        {"id":"feet","hand":0.0,"body":{},"pose":"open","camera":Vector3(.22,.50,1.1),"target":Vector3(0,.08,.06),"extent":.44},
        {"id":"flexed_ankle","hand":0.0,"body":{},"pose":"open","camera":Vector3(.22,.50,1.1),"target":Vector3(0,.08,.06),"extent":.44}]
    for c in cases:
        d.body=CD.create().to_dict().body
        d.body.merge(c.body,true)
        d.body.hand_size=c.hand
        p.show_draft(d)
        var v=p.visual
        for anim in v.find_children("*","AnimationPlayer",true,false):anim.stop()
        var sk:Skeleton3D=v._skeleton()
        for name in ["forearm_l","forearm_r","foot_l","foot_r"]:sk.set_bone_pose_rotation(sk.find_bone(name),Quaternion.IDENTITY)
        if c.id=="flexed_ankle":sk.set_bone_pose_rotation(sk.find_bone("foot_l"),Quaternion(Vector3.RIGHT,.6))
        sk.force_update_all_bone_transforms()
        v.set_hand_pose(c.pose)
        p.camera.size=c.extent
        p.camera.position=c.camera
        p.camera.look_at(c.target)
        for i in 8:await process_frame
        await RenderingServer.frame_post_draw
        if not G.owns(lease):quit(2);return
        var path="res://previews/"+lease+"/v9-"+c.id+".jpg"
        print("CAPTURE ",path," rc=",p.viewport.get_texture().get_image().save_jpg(path,.92))
    p.free()
    await process_frame
    quit()
