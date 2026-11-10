extends Node
## Test-only cold hair geometry vs skin/morph transfer; wall-clock, not acceptance.
const HairRig = preload("res://scripts/assets/hair_rig.gd")
const HairBuilder = preload("res://scripts/assets/hair_builder.gd")
const SOURCE_SHA = {"res://scripts/assets/hair_rig.gd":"9a424585912a8fbb6334f920de91846c15e7e98e850b9b30dfad17c7b90bcb31","res://scripts/assets/hair_builder.gd":"0b9a8276f1d20a8981192968608704d30b55800655b4f16b51271d7fe40b719b"}
func _ready() -> void:
    _run.call_deferred()
func _emit(phase:String,t:int,count:int=-1) -> void:
    print("H3_HAIR_SPLIT "+JSON.stringify({"phase":phase,"ms":(Time.get_ticks_usec()-t)/1000.0,"count":count}))
func _run() -> void:
    for p in SOURCE_SHA:
        if FileAccess.get_sha256(p) != SOURCE_SHA[p]:
            push_error("Source SHA changed: "+p)
            get_tree().quit(2)
            return
    var t:int=Time.get_ticks_usec()
    var src:Dictionary=HairRig.source()
    _emit("source",t,src.size())
    if src.is_empty():
        get_tree().quit(2)
        return
    t=Time.get_ticks_usec()
    var ctx:Dictionary=HairRig.context()
    _emit("context",t,ctx.size())
    if ctx.is_empty():
        get_tree().quit(2)
        return
    t=Time.get_ticks_usec()
    var g:Dictionary=HairRig.geometry("scalp","kratke")
    var verts:int=(g.get("pos",PackedVector3Array()) as PackedVector3Array).size()
    _emit("geometry",t,verts)
    if verts==0:
        get_tree().quit(2)
        return
    t=Time.get_ticks_usec()
    var split:Dictionary=HairRig._arrays_from(g,false)
    _emit("arrays_from_skin_morph",t,(split.get("names",[]) as Array).size())
    split["tris"]=HairBuilder.tri_count(g)
    split["verts"]=verts
    t=Time.get_ticks_usec()
    var canonical:Dictionary=HairRig.build_pack("scalp","kratke")
    _emit("canonical_build_pack",t,int(canonical.get("verts",0)))
    var ok:bool=true
    for key in ["arrays","blend","names","flags","tris","verts"]:
        if not split.has(key) or not canonical.has(key) or split[key]!=canonical[key]:
            print("H3_HAIR_SPLIT_MISMATCH "+key)
            ok=false
    print("H3_HAIR_SPLIT_RESULT "+JSON.stringify({"ok":ok,"verts":verts,"tris":int(split.get("tris",0)),"keys":(split.get("names",[]) as Array).size(),"exact_pack_equal":ok}))
    get_tree().quit(0 if ok else 2)
