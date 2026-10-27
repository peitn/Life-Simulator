extends RefCounted
## LIFESIM H2b optional playable anatomy view driven by the *real* Blender
## anatomy_skeleton_v1.blend rest landmark coordinates (194/60/60/6).
##
## This is lightweight procedural render-only anatomy mapped to the existing
## authenticated 17-bone Godot character rig. BoneAttachment3D makes anatomical
## fragments follow the local character's existing idle/walk/sit/lie animation.
## It does NOT import actual sculpt meshes, add physical phalange joints,
## activate Elmer, change CharacterData, or synchronize gameplay/network state.
const SOURCE := "res://assets/anatomy/anatomy_runtime_proxy_v1.json"
const VALID_LAYERS := ["off", "bones", "muscles", "cartilage", "fat", "all"]
const PRIMARY_BONE_COUNT := 194
const MUSCLE_COUNT := 60
const CARTILAGE_COUNT := 60
const FAT_COUNT := 6
const CORE_BONES := [
    "hips", "spine", "chest", "neck", "head",
    "upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r",
    "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"
]
static var _data: Dictionary = {}

static func reference_data() -> Dictionary:
    if not _data.is_empty():
        return _data
    if not FileAccess.file_exists(SOURCE):
        return {}
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    var body: Dictionary = raw
    if body.get("schema") != "lifesim.blender.anatomy-proxy.v1":
        return {}
    if body.get("bones", []).size() != PRIMARY_BONE_COUNT or        body.get("muscles", []).size() != MUSCLE_COUNT or        body.get("cartilage", []).size() != CARTILAGE_COUNT or        body.get("fat", []).size() != FAT_COUNT:
        return {}
    if body.get("production_rig_anchor_count") != 17 or        body.get("physically_simulated") != false or        body.get("overlay_is_exact_export_of_render_meshes") != false:
        return {}
    _data = body
    return _data


static func available(skeleton: Skeleton3D) -> bool:
    if skeleton == null or reference_data().is_empty() or skeleton.get_bone_count() != 17:
        return false
    for name in CORE_BONES:
        if skeleton.find_bone(name) < 0:
            return false
    return true


static func _vec(v: Array) -> Vector3:
    return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _material(c: Color, transparent := false) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = c
    material.roughness = .63
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    if transparent:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
    return material


static func _add_cylinder(parent: Node3D, label: String,
        a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = label
    var distance := a.distance_to(b)
    var mesh := CylinderMesh.new()
    mesh.top_radius = maxf(.001, r * .88)
    mesh.bottom_radius = maxf(.001, r * 1.06)
    mesh.height = maxf(.003, distance)
    mesh.radial_segments = 7
    mesh.rings = 1
    instance.mesh = mesh
    instance.material_override = mat
    instance.position = (a+b)*.5
    if distance > .00001:
        instance.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
    instance.add_to_group("lifesim_anatomy_visual")
    parent.add_child(instance)
    return instance


static func _add_ellipsoid(parent: Node3D, label: String, center: Vector3,
        extents: Vector3, mat: Material, slices := 10) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = slices
    mesh.rings = 6
    var instance := MeshInstance3D.new()
    instance.name = label
    instance.mesh = mesh
    instance.position = center
    instance.scale = extents
    instance.material_override = mat
    instance.add_to_group("lifesim_anatomy_visual")
    parent.add_child(instance)
    return instance


## Returns the root or null. This builder should ONLY run when local display
## explicitly asks for anatomy: default gameplay has zero anatomy draw calls.
static func create_overlay(skeleton: Skeleton3D) -> Node3D:
    if not available(skeleton):
        return null
    var data: Dictionary = reference_data()
    var root := Node3D.new()
    root.name = "LifeSimulator_AnatomyView"
    skeleton.add_child(root)
    var materials := {
        "bones": _material(Color(.88,.80,.64)),
        "muscles": _material(Color(.65,.14,.15)),
        "cartilage": _material(Color(.27,.75,.70,.83),true),
        "fat": _material(Color(.96,.76,.30,.52),true)
    }
    var driver_nodes := {}
    var driver_rests := {}
    var layer_nodes := {}
    for layer in ["bones","muscles","cartilage","fat"]:
        layer_nodes[layer] = []
    for name in CORE_BONES:
        var bone_index: int = skeleton.find_bone(name)
        var att := BoneAttachment3D.new()
        att.name = "Drive_" + name
        att.bone_name = name
        # The overlay root sits between attachment and the live Skeleton3D.
        # Explicitly bind external skeleton; otherwise no bones follow animation.
        att.use_external_skeleton = true
        att.external_skeleton = NodePath("../..")
        root.add_child(att)
        driver_nodes[name] = att
        driver_rests[name] = skeleton.get_bone_global_rest(bone_index).affine_inverse()
        for layer in ["bones","muscles","cartilage","fat"]:
            var branch := Node3D.new()
            branch.name = layer
            att.add_child(branch)
            layer_nodes[layer].append(branch)
    var count := {"bones":0,"muscles":0,"cartilage":0,"fat":0}
    for layer in ["bones","muscles","cartilage","fat"]:
        for raw in data.get(layer, []):
            var entry: Dictionary = raw
            var driver: String = str(entry.get("d",""))
            if not driver_nodes.has(driver):
                root.queue_free()
                return null
            var attachment: BoneAttachment3D = driver_nodes[driver]
            var holder: Node3D = attachment.get_node(layer)
            var inverse: Transform3D = driver_rests[driver]
            var label: String = str(entry.get("n","unnamed"))
            if layer == "bones" or layer == "muscles":
                var a := inverse * _vec(entry["h"])
                var b := inverse * _vec(entry["t"])
                _add_cylinder(holder,"Anatomy_"+label,a,b,float(entry["r"]),materials[layer])
            else:
                var pos := inverse * _vec(entry["p"])
                var radius := _vec(entry["e"])
                _add_ellipsoid(holder,"Anatomy_"+label,pos,radius,materials[layer],
                    14 if layer=="fat" else 10)
            count[layer] += 1
    root.set_meta("anatomy_counts",count)
    root.set_meta("proxy_from_real_blender_194_landmarks",true)
    root.set_meta("real_blender_surface_meshes_transferred",false)
    root.set_meta("live_elmer_physics",false)
    apply_mode(root,"off")
    return root


static func apply_mode(overlay_root: Node3D, mode: String) -> bool:
    if overlay_root == null or mode not in VALID_LAYERS:
        return false
    for driver in overlay_root.get_children():
        for layer in driver.get_children():
            var item: Node3D = layer
            item.visible = mode == "all" or mode == item.name
    overlay_root.visible = mode != "off"
    return true