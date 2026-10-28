extends "res://tests/test_base.gd"
## Schema-backed anatomy/face/skin controls through real HUD -> private draft ->
## isolated 3D preview -> Undo/Redo -> strict authoritative Apply; narrow UI.
const Main := preload("res://main.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")

var world: Node

func _ready() -> void:
    watchdog_seconds=60.0
    get_node("/root/GameClock").running=false
    Assets.enabled=false
    world=Main.new()
    world.net_config={"mode":"offline","hud":true,"camera":false,"visuals":false,
        "audio":false,"autosave":false,"autoload":false}
    add_child(world)
    _run.call_deferred()

func _run() -> void:
    await get_tree().process_frame
    section("Creator: actual visible anatomy controls")
    var hud=world.hud
    hud._create_button.pressed.emit()
    var creator=hud._character_creator
    check(creator!=null and is_instance_valid(creator),"creator opens")
    if creator==null:
        finish("test_appearance_slider_ui")
        return
    var a=creator._appearance
    var expected_available: int = a.available_count()
    check(a.available_count()>=55,"at least 55 real appearance controls wired")
    var expected_groups:Dictionary={}
    for group in a.GROUP_ORDER:
        var count=0
        for field in Schema.fields(group):
            var spec: Array=Schema.fields(group)[field]
            if spec[0]=="f" and not (group=="body" and field in a.EXCLUDED_BODY):
                check(a.slider(group,field)!=null,"schema slider is visible/selectable: "+group+"."+field)
                count+=1
        expected_groups[group]=count
        check(count>0,"non-empty appearance category "+group)
    check(a.slider("body","shoulders")!=null and a.slider("body","leg_length")!=null
        and a.slider("body","head_size")!=null and a.slider("body","neck_length")!=null,
        "existing body shape morphs exposed independently")
    check(a.slider("face","cheekbones")!=null and a.slider("face","chin_width")!=null
        and a.slider("face","forehead_slope")!=null and a.slider("face","teeth_gap")!=null,
        "cheekbone, chin, forehead and teeth detail exposed")
    check(a.slider("skin","tone")!=null and a.slider("skin","undertone")!=null
        and a.slider("skin","oiliness")!=null, "melanin, undertone and skin microtexture exposed")
    check(a.enum_button("hair","style")!=null and a.enum_button("skin","type")!=null,
        "hairstyle and skin type variations are selectable")
    check(creator._height.min_value==145.0 and creator._height.max_value==205.0
        and creator._age.min_value==18.0 and creator._age.max_value==95.0,
        "creator's numeric age/height input cannot leave canonical strict ranges")
    var initial:Dictionary=creator._session.draft()
    var living:int=world.sims.size()
    check(a.slider("body","hand_size")!=null,"hand size has a real schema-backed control")
    a.slider("body","hand_size").value=.73
    check(is_equal_approx(float(creator._session.draft()["body"]["hand_size"]),.73)
        and is_equal_approx(float(creator._visual_preview.public_snapshot()["body"]["hand_size"]),.73),
        "hand size slider updates isolated character and public preview")
    a.slider("body","shoulders").value=.91
    check(is_equal_approx(float(creator._session.draft()["body"]["shoulders"]),.91),
        "body shoulder slider edits live draft field")
    check(creator._visual_preview.public_snapshot()["body"]["shoulders"]==.91,
        "body preview uses changed shoulder without spawning")
    check(world.sims.size()==living,"moving body sliders cannot spawn a character")
    a._group_picker.select(1)
    a._group_picker.item_selected.emit(1)
    check(a._groups["face"].visible and not a._groups["body"].visible,
        "facial category switches controls without touching draft")
    a.slider("face","cheekbones").value=.78
    a.slider("face","nose_tip").value=-.46
    check(creator._session.draft()["face"]["cheekbones"]==.78
        and creator._visual_preview.public_snapshot()["face"]["nose_tip"]==-0.46,
        "facial sliders update isolated 3D preview")
    a._group_picker.select(2)
    a._group_picker.item_selected.emit(2)
    a.slider("skin","tone").value=.82
    check(is_equal_approx(float(creator._session.draft()["skin"]["tone"]),.82),
        "continuous skin tone reflected in transactional draft")
    var option:OptionButton=a.enum_button("skin","type")
    var dry_index: int=-1
    for i in option.item_count:
        if option.get_item_metadata(i)=="dry":
            dry_index=i
    check(dry_index>=0,"dry skin type exists")
    if dry_index>=0:
        option.select(dry_index)
        option.item_selected.emit(dry_index)
        check(creator._session.draft()["skin"]["type"]=="dry",
            "skin type picker writes canonical variant")
    var edited:Dictionary=creator._session.draft()
    check(Validator.validate(edited,{"mode":"strict","mental_health":"full"})["ok"],
        "many independent morphology/skin controls remain strict schema valid")
    creator._on_undo()
    check(creator._session.draft()["skin"]["type"]!=edited["skin"]["type"],
        "Undo reverts last appearance enum")
    creator._on_redo()
    check(creator._session.draft()["skin"]["type"]==edited["skin"]["type"],
        "Redo restores appearance enum")
    creator._on_cancel()
    await get_tree().process_frame
    check(world.sims.size()==living and not is_instance_valid(creator),
        "Cancel drops all face/body/skin edits and leaves household untouched")

    section("Live editor: face/skin/wardrobe changes with actual Apply")
    var target=world.get_selected_sim()
    var key:String=String(target.name)
    var canonical_before:Dictionary=world.read_character_edit(key)["data"]
    hud._edit_button.pressed.emit()
    var editor=hud._character_editor
    check(editor!=null and is_instance_valid(editor),"live editor opened from HUD")
    if editor==null:
        finish("test_appearance_slider_ui")
        return
    var ae=editor._appearance
    check(ae.available_count()==expected_available,"creator and editor expose identical appearance catalog")
    var cheek: HSlider=ae.slider("face","cheekbones")
    cheek.value=.63
    var skin: HSlider=ae.slider("skin","tone")
    skin.value=.72
    check(is_equal_approx(float(editor._session.draft()["face"]["cheekbones"]),.63)
        and is_equal_approx(float(editor._session.draft()["skin"]["tone"]),.72),
        "real editor modifies cheekbone and melanin axes")
    check(world.read_character_edit(key)["data"]==canonical_before,
        "live agent unchanged before explicit Apply")
    var public_draft=editor._visual_preview.public_snapshot()
    check(public_draft["skin"]["tone"]==.72 and public_draft["face"]["cheekbones"]==.63,
        "preview shows changed face and skin without private data")
    check(not public_draft.has("uid") and not public_draft.has("mind"),
        "preview strips private UID and mental history")
    var before_rev:int=int(world.read_character_edit(key)["revision"])
    editor._on_apply()
    var after:Dictionary=world.read_character_edit(key)
    check(after.get("ok",false) and int(after["revision"])==before_rev+1,
        "authority committed one canonical appearance revision")
    check(after["data"]["face"]["cheekbones"]==.63 and after["data"]["skin"]["tone"]==.72,
        "persisted anatomy/skin axes equal requested values")
    check(target.look.get("face",{}).get("cheekbones")==.63
        and target.look.get("skin",{}).get("tone")==.72,
        "actual live character/public appearance updated")
    var body_view=ae.slider("body","hips")
    var before:float=body_view.value
    body_view.value=.88 if before<.6 else .13
    check(editor._session.is_dirty(),"post-Apply editor accepts a second staged anatomy edit")
    editor._on_cancel()
    await get_tree().process_frame
    check(world.read_character_edit(key)["data"]["body"]["hips"]==canonical_before["body"]["hips"],
        "Cancel discards second unsaved edit, not previous committed anatomy")
    world.queue_free()
    await get_tree().process_frame
    Assets.enabled=true
    finish("test_appearance_slider_ui")
