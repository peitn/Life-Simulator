extends SceneTree
func _init():
    var args=OS.get_cmdline_user_args()
    var G=load("res://tools/automation_lock.gd")
    if args.size()!=1 or not G.owns(args[0]): quit(2);return
    var path="res://scenes/city/staircase_straight_3m.scn"
    if FileAccess.file_exists(path): quit(3);return
    var doc=GLTFDocument.new()
    var state=GLTFState.new()
    if doc.append_from_file("res://assets/city/staircase_straight_3m.glb",state)!=OK: quit(4);return
    var root=doc.generate_scene(state)
    if not root is Node3D: quit(5);return
    root.name="StaircaseStraight3m"
    var body=StaticBody3D.new(); body.name="SolidSteps"
    root.add_child(body);body.owner=root;body.collision_layer=1;body.collision_mask=1
    for i in range(15):
        var c=CollisionShape3D.new();c.name="Step%02d"%i
        var s=BoxShape3D.new();s.size=Vector3(1,(i+1)*.2,.3)
        c.shape=s;c.position=Vector3(.5,s.size.y/2,-(i+.5)*.3)
        body.add_child(c);c.owner=root
    for item in [["Bottom",Vector3.ZERO],["Top",Vector3(0,3,-4.5)]]:
        var m=Marker3D.new();m.name=item[0];m.position=item[1];root.add_child(m);m.owner=root
    var packed=PackedScene.new()
    if packed.pack(root)!=OK: root.free();quit(6);return
    if not G.owns(args[0]) or FileAccess.file_exists(path): root.free();quit(7);return
    var err=ResourceSaver.save(packed,path)
    print("SAVE=",err," SHA=",FileAccess.get_sha256(path))
    root.free();quit(0 if err==OK else 8)
