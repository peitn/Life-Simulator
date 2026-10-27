extends SceneTree
const EditorPanel=preload("res://scripts/ui/character_editor_panel.gd")
const CD=preload("res://scripts/character/character_data.gd")
class Net:
    extends Node
    enum Mode {OFFLINE,HOST,DEDICATED,CLIENT}
    var mode=Mode.CLIENT
    var my_sim="Actor"
    var character_edit_read_ui_enabled=true
    var pending=""
    var accepted=true
    signal character_edit_snapshot_correlated(token,key,data,revision)
    signal character_edit_snapshot_timed_out(token)
    signal disconnected(reason)
    func request_character_edit_snapshot(token):
        pending=token if accepted else ""
        return accepted
    func cancel_character_edit_snapshot(token=""):
        if token=="" or token==pending: pending=""
class World:
    extends Node
    var net
    var applies=0
    func apply_character_edit(_key,_data,_revision):
        applies+=1
        return {"ok":false}
var world
var passed=0
var failed=0
func check(ok,label):
    if ok: passed+=1
    else: failed+=1
    print("PASS " if ok else "FAIL ",label)
func _init(): call_deferred("run")
func panel():
    var p=EditorPanel.new()
    p.main=world
    root.add_child(p)
    return p
func run():
    root.size=Vector2i(960,720)
    world=World.new()
    root.add_child(world)
    world.net=Net.new()
    world.add_child(world.net)
    var p=panel()
    world.net.character_edit_read_ui_enabled=false
    check(not p.open_network_character("Actor"),"default gate denies network panel")
    world.net.character_edit_read_ui_enabled=true
    check(not p.open_network_character("Other"),"other actor denied before request")
    check(p.open_network_character("Actor"),"own pending panel opens")
    var token=p._read_token
    check(token.length()==32 and not p._session.is_open() and not p._body_scroll.visible,"fresh token and no draft while waiting")
    check(p._apply_button.disabled,"Apply disabled while pending")
    var data=CD.create().to_dict()
    world.net.character_edit_snapshot_correlated.emit("f".repeat(32),"Actor",data,2)
    check(not p._session.is_open(),"unmatched response ignored")
    world.net.character_edit_snapshot_correlated.emit(token,"Other",data,2)
    check(not p._session.is_open(),"wrong target ignored")
    world.net.character_edit_snapshot_correlated.emit(token,"Actor",data,2)
    check(p._session.is_open() and p._revision==2 and p._body_scroll.visible,"matching owner response opens draft")
    var draft=p._session.draft()
    draft["clothing"]["bezne"]["top"]="kawaii_kocici_mikina"
    p._session.replace_draft(draft,"test")
    p._refresh()
    check(p._session.is_dirty(),"network draft supports local editing")
    p._on_undo()
    check(not p._session.is_dirty(),"Undo restores server snapshot")
    p._on_redo()
    check(p._session.is_dirty(),"Redo restores local draft")
    p._on_apply()
    check(world.applies==0 and p._apply_button.disabled,"programmatic Apply also denied")
    if OS.get_cmdline_user_args().has("--render"):
        var G=load("res://tools/automation_lock.gd")
        var id=OS.get_cmdline_user_args()[-1]
        for width in [960,390]:
            root.size=Vector2i(width,720)
            for i in 8: await process_frame
            await RenderingServer.frame_post_draw
            if not G.owns(id): quit(3); return
            var path="res://previews/"+id+"-"+str(width)+".jpg"
            print("RENDER=",path," err=",root.get_texture().get_image().save_jpg(path,.75))
    p._on_cancel()
    check(not p._session.is_open(),"Cancel discards draft synchronously")
    await process_frame
    p=panel()
    check(p.open_network_character("Actor"),"reopen allowed")
    var previous=p._read_token
    world.net.pending="e".repeat(32)
    p._on_cancel()
    check(world.net.pending=="e".repeat(32),"old panel cleanup preserves newer pending read")
    world.net.character_edit_snapshot_correlated.emit(previous,"Actor",data,3)
    check(not p._session.is_open(),"queued panel cannot reopen")
    await process_frame
    p=panel()
    p.open_network_character("Actor")
    world.net.character_edit_snapshot_timed_out.emit("wrong")
    check(not p._read_token.is_empty(),"unmatched timeout ignored")
    token=p._read_token
    world.net.character_edit_snapshot_timed_out.emit(token)
    check(p._read_token.is_empty() and not p._session.is_open() and not p._body_scroll.visible,"timeout leaves no private draft")
    world.net.character_edit_snapshot_correlated.emit(token,"Actor",data,4)
    check(not p._session.is_open(),"late reply after timeout ignored")
    p._on_cancel()
    await process_frame
    p=panel()
    p.open_network_character("Actor")
    world.net.disconnected.emit("test")
    check(p.is_queued_for_deletion() and world.net.pending=="","disconnect closes pending panel")
    await process_frame
    p=panel()
    p.open_network_character("Actor")
    world.net.character_edit_snapshot_correlated.emit(p._read_token,"Actor",data,2)
    world.net.my_sim="Reassigned"
    p._process(0.0)
    check(p.is_queued_for_deletion() and not p._session.is_open(),"assignment change closes loaded private draft")
    await process_frame
    world.net.my_sim="Actor"
    world.net.accepted=false
    p=panel()
    check(not p.open_network_character("Actor"),"failed local launch returns false")
    check(p._read_net==null and p._read_token=="","failed launch disconnects handlers")
    p.queue_free()
    await process_frame
    world.net.accepted=true
    p=panel()
    p.open_network_character("Actor")
    world.net.free()
    p._process(0.0)
    check(p.is_queued_for_deletion() and not p._session.is_open(),"destroyed transport closes panel safely")
    world.queue_free()
    await process_frame
    print("NETWORK_PANEL_RESULT=",passed," passed ",failed," failed")
    quit(0 if failed==0 else 1)
