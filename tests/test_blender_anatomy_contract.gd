extends SceneTree
## Safety contract for OPTIONAL Blender anatomy reference, not live-game integration.
## Checks shared 17-bone mapping against the actual character GLB and readable
## physics/prototype metadata. Physics numbers are illustrative uncalibrated.
const Assets := preload("res://scripts/assets/asset_library.gd")
const MANIFEST := "res://docs/anatomy/anatomy-physics-v1.json"

var pass_count := 0
var fail_count := 0
func check(ok: bool, label: String) -> void:
    pass_count += int(ok)
    fail_count += int(not ok)
    if not ok:
        print("FAIL ",label)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var manifest_raw: String = FileAccess.get_file_as_string(MANIFEST)
    var model: Variant = JSON.parse_string(manifest_raw)
    check(typeof(model)==TYPE_DICTIONARY,"JSON anatomy manifest readable")
    if typeof(model)!=TYPE_DICTIONARY:
        quit(2)
        return
    var m: Dictionary = model
    check(m.get("version")=="0.1.0","versioned separate anatomy model")
    check(m.get("blender_library_asset")=="lifesim-anatomy-skeleton-v1",
        "references persisted Blender-only anatomy asset")
    check(m.get("rig_bones")==194 and m.get("reference_bone_meshes")==201,
        "full-body skeletal proxy mesh and control rig inventory")
    check(m.get("vertebrae")==24 and m.get("ribs")==24,
        "cervical/thoracic/lumbar vertebrae and 12 mirrored ribs")
    check(m.get("finger_phalanges")==28 and m.get("toe_phalanges")==28,
        "hands and feet have many distinct reference phalanges")
    check(m.get("cartilage_meshes")==60 and m.get("muscle_bundles")==60,
        "separate articular/cartilage and muscle volumes")
    check(m.get("tendon_and_ligament_objects")==136,
        "tendons and simplified ligaments inventoried")
    check(m.get("rigid_bodies")==17,"Bullet proxy scaffold includes 17 bodies")
    check(not bool(m.get("physics_in_live_gameplay",true))
        and not bool(m.get("muscle_contraction_solver",true))
        and not bool(m.get("medically_calibrated",true)),
        "prototype cannot be silently presented as live/validated physics")
    check(m.get("coordinate_system")=="Blender Z-up meters; GLB Godot Y-up meters",
        "explicit conversion of Blender Z-up to Godot Y-up")
    var names: Array=m.get("legacy_rig_names",[])
    check(names.size()==17 and names.has("hips") and names.has("foot_l"),
        "preserves original 17 production controls")
    var real_scene: Node3D = Assets.instantiate("character")
    check(real_scene != null,"existing production authored character remains unchanged")
    if real_scene != null:
        root.add_child(real_scene)
        var skeleton: Skeleton3D=real_scene.get_node_or_null("Skeleton3D")
        check(skeleton!=null and skeleton.get_bone_count()==17,
            "legacy game character still uses exact 17-bone skeleton")
        if skeleton != null:
            for name in names:
                check(skeleton.find_bone(String(name))>=0,
                    "blender interface name matches existing real skin rig "+String(name))
        real_scene.queue_free()
    var masses: Dictionary=m.get("rigid_body_mass_kg",{})
    var joints: Dictionary=m.get("joints",{})
    check(masses.size()==17 and joints.size()==16,
        "complete masses and bounded dynamics for all 16 joints")
    var sum_mass:=0.0
    for name in masses:
        var mass: float=float(masses[name])
        sum_mass+=mass
        check(mass>0 and mass<=50,
            "positive finite plausible illustration mass "+String(name))
    check(absf(sum_mass-63.0)<.001,"illustrative total segment mass of 63 kg")
    check(absf(sum_mass-float(m.get("rigid_body_total_mass_kg",0)))<.001,
        "declared body mass equals all actual proxy segment masses")
    for name in joints:
        var j: Array=joints[name]
        check(j.size()==4,"joint definition includes two proxies plus two ranges "+String(name))
        if j.size()!=4:
            continue
        check(masses.has(String(j[0])) and masses.has(String(j[1])),
            "joint bodies exist in explicit physics scaffold "+String(name))
        for limits in [j[2],j[3]]:
            check(typeof(limits)==TYPE_ARRAY and limits.size()==2
                and float(limits[0])<=float(limits[1])
                and absf(float(limits[0]))<3.15
                and absf(float(limits[1]))<3.15,
                "finite bounded hinge/swing angles "+String(name))
    check(FileAccess.file_exists("res://tools/blender/anatomy_skeleton_v1.py"),
        "original canonical Blender generator retained in Godot source")
    check(FileAccess.file_exists("res://tools/blender/anatomy_export_musculature_v1.py"),
        "repeatable Blender separate muscle GLB exporter retained")
    print("ANATOMY_BLENDER_CONTRACT checks=",pass_count+fail_count,
        " passed=",pass_count," failed=",fail_count)
    quit(0 if fail_count==0 else 1)
