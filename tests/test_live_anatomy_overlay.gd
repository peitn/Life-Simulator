extends "res://tests/test_base.gd"
## Real Blender-origin anatomy landmarks attached to the ACTUAL 17-bone
## animated in-world SimVisual, with local-only HUD and creator previews.
## No production rig swap, no Elmer/Godot physics changes or network RPC.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const Overlay := preload("res://scripts/assets/anatomy_overlay.gd")
const Preview := preload("res://scripts/ui/character_preview.gd")

var world: Node

func _ready() -> void:
    watchdog_seconds = 75.0
    get_node("/root/GameClock").running = false
    Assets.enabled = true
    world = Main.new()
    world.net_config = {"mode":"offline","hud":true,"camera":false,
        "visuals":true,"audio":false,"autoload":false,"autosave":false}
    add_child(world)
    _run.call_deferred()


func _count_nodes(parent: Node, classname: String) -> int:
    return parent.find_children("*",classname,true,false).size()


func _run() -> void:
    await get_tree().process_frame
    section("Blender anatomy source integrity")
    var data:Dictionary=Overlay.reference_data()
    check(data.get("schema")=="lifesim.blender.anatomy-proxy.v1",
        "actual Blender input atlas imported and schema checked")
    check(data.get("source")=="lifesim-anatomy-skeleton-v1/anatomy_skeleton_v1.blend",
        "data sourced from real persisted Blender skeleton and muscles")
    check(data.get("bones",[]).size()==194,"all 194 Blender bone landmarks included")
    check(data.get("muscles",[]).size()==60,"60 original authored muscle bundle endpoints included")
    check(data.get("cartilage",[]).size()==60,"60 Blender cartilage reference centers included")
    check(data.get("fat",[]).size()==6,"six original volumetric fat location/scale references")
    check(not bool(data.get("physically_simulated",true)) and
        not bool(data.get("overlay_is_exact_export_of_render_meshes",true)),
        "landmark-only render proxy is never misrepresented as original sculpt mesh/FEA")
    check(not data.has("mind") and not data.has("uid") and not data.has("identity"),
        "anatomy display source holds no sensitive player/mental identity fields")
    section("Actual offline live character and HUD")
    check(world.sims.size()>=2,"actual loaded household contains multiple residents")
    var actor=world.get_selected_sim()
    check(actor!=null and actor.visual!=null,"live in-world SimAgent has SimVisual")
    if actor==null or actor.visual==null:
        finish("test_live_anatomy_overlay")
        return
    var vis:Node3D=actor.visual
    check(vis.uses_model() and vis.anatomy_available(),
        "actual production character.glb 17-bone skeleton accepted for retarget")
    var skel:Skeleton3D=vis.get_node("Body/Model/Skeleton3D")
    check(skel.get_bone_count()==17,"production skeleton remains exactly 17 bones")
    var hud=world.hud
    check(hud!=null and hud._anatomy_button!=null,
        "player HUD contains new live anatomy layer entry")
    check(vis.anatomy_view()=="off","normal characters remain fully dressed by default")
    var original_visuals:Array=[]
    for mi in vis.get_node("Body/Model").find_children("*","MeshInstance3D",true,false):
        if not mi.is_in_group("lifesim_anatomy_visual"):
            original_visuals.append([mi,mi.visible])
    check(original_visuals.size()>10,"authored body/face/clothes/hair real visuals present")
    hud._anatomy_button.pressed.emit()
    check(vis.anatomy_view()=="bones","HUD click changes real selected character anatomy to bones")
    var overlay:Node3D=skel.get_node_or_null("LifeSimulator_AnatomyView")
    check(overlay!=null,"overlay is real child of the character Skeleton3D")
    if overlay==null:
        finish("test_live_anatomy_overlay")
        return
    var counts:Dictionary=overlay.get_meta("anatomy_counts",{})
    check(counts.get("bones")==194 and counts.get("muscles")==60 and
        counts.get("cartilage")==60 and counts.get("fat")==6,
        "194+60+60+6 rendered per-person anatomy instances created")
    check(overlay.get_child_count()==17,
        "exactly 17 BoneAttachment3D drivers follow existing game skeleton")
    check(_count_nodes(overlay,"MeshInstance3D")==320,
        "320 separate actual anatomy render proxies attached to one live actor")
    for attachment in overlay.get_children():
        check(attachment is BoneAttachment3D and attachment.use_external_skeleton,
            "driver binds existing animated skeleton (not static absolute coordinates)")
        check(attachment.get_child_count()==4,
            "each 17 body drivers groups four distinct tissue layers")
    var invisible_original:=true
    for item in original_visuals:
        if is_instance_valid(item[0]) and item[0].visible:
            invisible_original=false
    check(invisible_original,"normal opaque clothes and skin hidden for visible anatomy")
    var anim:AnimationPlayer=vis.get_node("Body/Model/Anim")
    check(anim.current_animation=="idle" or anim.is_playing(),
        "same authored animation player remains active under anatomy")
    var arm_attach:BoneAttachment3D=overlay.get_node("Drive_upper_arm_l")
    var arm_index:int=skel.find_bone("upper_arm_l")
    await get_tree().process_frame
    var old_basis:Basis=arm_attach.global_transform.basis
    anim.pause()
    skel.set_bone_pose_rotation(arm_index,Quaternion(Vector3.FORWARD,.42))
    await get_tree().process_frame
    check(not old_basis.is_equal_approx(arm_attach.global_transform.basis),
        "anatomical upper-arm bones truly follow changed 17-bone gameplay pose")
    var sample:MeshInstance3D=arm_attach.get_node("bones/Anatomy_upper_arm_l")
    check(sample.visible and sample.is_visible_in_tree(),
        "skinned-driver upper arm proxy remains visible during actual pose")
    anim.play("idle")
    for expected in ["muscles","cartilage","fat","all","off"]:
        hud._anatomy_button.pressed.emit()
        check(vis.anatomy_view()==expected,
            "in-game HUD cycles genuine anatomical mode "+expected)
    check(not overlay.visible,
        "default appearance restored and anatomy hidden on disable")
    var restore_correct:=true
    for item in original_visuals:
        if is_instance_valid(item[0]) and item[0].visible!=bool(item[1]):
            restore_correct=false
    check(restore_correct,"all original clothing, skin, face and hair visibility restored")
    check(overlay.get_child_count()==17,"toggling modes does not duplicate attachments")
    var other=world.sims[0] if actor!=world.sims[0] else world.sims[1]
    check(other.visual!=null and other.visual.anatomy_view()=="off",
        "other resident remains clothed and anatomy not enabled accidentally")
    section("Independent creator/editor preview")
    var preview:VBoxContainer=Preview.new()
    add_child(preview)
    await get_tree().process_frame
    var picker:OptionButton=preview.get_node_or_null("AnatomyLayerRow/AnatomyViewPicker")
    check(picker!=null and picker.item_count==6 and not picker.disabled,
        "creator/editor 3D SubViewport offers all six anatomical choices")
    check(preview.viewport.world_3d != get_viewport().world_3d,
        "anatomical preview has its own isolated 3D world")
    preview._on_anatomy_view_picked(5)
    check(preview.visual.anatomy_view()=="all",
        "preview really opens the full anatomy on a 17-bone skinned character")
    check(other.visual.anatomy_view()=="off" and vis.anatomy_view()=="off",
        "preview changes are isolated from all in-world characters")
    var shown:Dictionary=preview.public_snapshot()
    check(not shown.has("mind") and not shown.has("uid"),
        "preview/overlay never exposes private mental state or user ID")
    preview._on_anatomy_view_picked(0)
    check(preview.visual.anatomy_view()=="off",
        "creator/editor can restore normal body without character transaction")
    preview.queue_free()
    section("Network state unchanged")
    check(world.net.mode==world.net.Mode.OFFLINE,
        "anatomical display did not enter multiplayer/rpc mode")
    check(not vis.has_method("run_elmer_fem") and not vis.has_method("start_ragdoll"),
        "no fabricated live Elmer or anatomical dynamic-body physics")
    check(FileAccess.file_exists("res://assets/anatomy/anatomy_runtime_proxy_v1.json"),
        "actual Blender landmark atlas source persisted inside playable project")
    finish("test_live_anatomy_overlay")
