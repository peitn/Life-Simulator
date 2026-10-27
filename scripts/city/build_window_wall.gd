extends RefCounted
# Reproducible window wall packer; caller must own shared city lease.
static func set_owners(root: Node, node: Node) -> void:
    for child in node.get_children():
        child.owner = root
        set_owners(root, child)

static func build(run_id: String) -> Dictionary:
    var G = load("res://tools/automation_lock.gd")
    var glb = "res://assets/city/wall_window_2m.glb"
    var dest = "res://scenes/city/wall_window_2m.scn"
    if not G.owns(run_id):
        return {"ok":false,"reason":"city lease not owned"}
    var previous = FileAccess.get_sha256(dest) if FileAccess.file_exists(dest) else ""
    if not FileAccess.file_exists(glb):
        return {"ok":false,"reason":"GLB missing"}
    var doc = GLTFDocument.new()
    var state = GLTFState.new()
    if doc.append_from_file(glb,state) != OK:
        return {"ok":false,"reason":"GLB import failed"}
    var model = doc.generate_scene(state)
    if not model is Node3D:
        if model != null: model.free()
        return {"ok":false,"reason":"invalid GLB root"}
    var root = Node3D.new()
    root.name = "WallWindow2m"
    root.add_child(model)
    var body = StaticBody3D.new()
    body.name = "Collision"
    body.collision_layer = 1
    body.collision_mask = 1
    root.add_child(body)
    var specs = [
        [Vector3(.2,1.4,0),Vector3(.4,2.8,.2)],
        [Vector3(1.8,1.4,0),Vector3(.4,2.8,.2)],
        [Vector3(1,.45,0),Vector3(1.2,.9,.2)],
        [Vector3(1,2.45,0),Vector3(1.2,.7,.2)]
    ]
    for i in specs.size():
        var collision = CollisionShape3D.new()
        collision.name = "WindowCollider" + str(i)
        collision.shape = BoxShape3D.new()
        collision.shape.size = specs[i][1]
        collision.position = specs[i][0]
        body.add_child(collision)
    set_owners(root,root)
    var packed = PackedScene.new()
    if packed.pack(root) != OK:
        root.free()
        return {"ok":false,"reason":"pack failed"}
    var now_hash = FileAccess.get_sha256(dest) if FileAccess.file_exists(dest) else ""
    if not G.owns(run_id) or now_hash != previous:
        root.free()
        return {"ok":false,"reason":"lease lost or target changed"}
    var save_result = ResourceSaver.save(packed,dest)
    root.free()
    if save_result != OK:
        return {"ok":false,"reason":"save failed","code":save_result}
    return {"ok":true,"sha256":FileAccess.get_sha256(dest)}
