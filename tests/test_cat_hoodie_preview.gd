extends SceneTree
## Authored preview characterization: item selection preserves tint; preset supplies pink.
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const Wardrobe=preload("res://scripts/assets/subculture_wardrobe.gd")
const G=preload("res://tools/automation_lock.gd")
# AppearanceResolver documents RGB quantization to 0.001; expected colors use that contract.
var passed=0
var failed=0
func check(ok,label):
    if ok: passed+=1
    else: failed+=1
    print("PASS " if ok else "FAIL ",label)
func _init(): call_deferred("run")
func run():
    root.get_node("GameSettings").persist=false
    var clothing=load("res://scripts/assets/clothing_wardrobe.gd")
    var info={"name":"cat_face","category":"top","material":"cloth_cotton"}
    var cat={"outfit_top":"kawaii_kocici_mikina","top":Color.BLUE}
    var other={"outfit_top":"tricko","top":Color.RED}
    check(clothing.tint(info,other)==Color.RED,"non-cat same-name part keeps tint")
    var first=clothing.material_instance(info,cat)
    var second=clothing.material_instance(info,cat)
    first.albedo_color=Color.GREEN
    check(second.albedo_color.is_equal_approx(Color(.94,.91,.86)),"separate material instance isolation")
    check(clothing.material_instance(info,cat).albedo_color.is_equal_approx(Color(.94,.91,.86)),"material cache remains unmodified")
    var p=Preview.new()
    root.add_child(p)
    var data=CD.create().to_dict()
    var original=data.duplicate(true)
    data.clothing.bezne.top="kawaii_kocici_mikina"
    data.clothing.active="bezne"
    p.show_draft(data)
    check(p.visual.uses_model(),"authored character loaded")
    check(p.visual.look_params.outfit_top=="kawaii_kocici_mikina","cat garment resolved")
    check(p.visual.look_params.top.is_equal_approx(Color(0.357,0.420,0.478,1.0)),"item selection retains independent tint")
    var names=[]
    for mi in p.visual._c5_nodes:
        if mi.name.begins_with("C5_top_"):
            names.append(String(mi.name))
            check(mi.visible and mi.mesh!=null and mi.skin!=null,"visible skinned authored "+mi.name)
    for suffix in ["cat_ear_-1","cat_ear_1","cat_hood","cat_face","cat_nose"]:
        check(names.has("C5_top_"+suffix),"required cat detail "+suffix)
    var render=OS.get_cmdline_user_args().has("--render")
    var id=OS.get_cmdline_user_args()[-1] if render else ""
    if render and DisplayServer.get_name()=="headless":
        print("FAIL render requires graphics")
        quit(2)
        return
    for variant in ["item","preset"]:
        if variant=="preset":
            data=Wardrobe.apply_to_character(data,"kawaii_kocka","bezne")
            p.show_draft(data)
            check(p.visual.look_params.top.is_equal_approx(Color(0.961,0.651,0.816,1.0)),"preset supplies pink tint")
            check(p.visual.look_params.outfit_top=="kawaii_kocici_mikina","preset retains cat mesh")
            check(original.clothing.bezne.top=="tricko","original data unchanged")
        for mi in p.visual._c5_nodes:
            if mi.name == "C5_top_cat_face":
                check(mi.material_override.albedo_color.is_equal_approx(Color(.94,.91,.86)), variant+" applique independent of fabric")
            elif String(mi.name).begins_with("C5_top_cat_eye_") or String(mi.name).begins_with("C5_top_whisker_"):
                check(mi.material_override.albedo_color.is_equal_approx(Color(.06,.045,.065)), variant+" dark detail "+mi.name)
            elif mi.name == "C5_top_cat_nose":
                check(mi.material_override.albedo_color.is_equal_approx(Color(.55,.16,.28)), variant+" nose accent")
            elif mi.name == "C5_top_shell":
                check(mi.material_override.albedo_color.is_equal_approx(p.visual.look_params.top),variant+" fabric retains chosen tint")
        if render:
            p.viewport.size=Vector2i(480,560)
            p.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
            p.camera.size=2.25
            for view in ["front","rear"]:
                p.visual.rotation.y=0.0 if view=="front" else PI
                for i in 8: await process_frame
                await RenderingServer.frame_post_draw
                if not G.owns(id): quit(3); return
                var path="res://previews/"+id+"-cat-"+variant+"-"+view+".jpg"
                if FileAccess.file_exists(path): quit(4); return
                check(p.viewport.get_texture().get_image().save_jpg(path,.85)==OK,"render "+path)
    p.queue_free()
    await process_frame
    print("CAT_PREVIEW_RESULT=",passed," passed ",failed," failed")
    quit(0 if failed==0 else 1)
