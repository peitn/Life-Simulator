extends "res://tests/test_base.gd"
## Visual-only bed occupancy/soft silhouette: no server logic or save changes.
const Main := preload("res://main.gd")
const Quilt := preload("res://scripts/world/quilt_visual.gd")

func _ready() -> void:
    watchdog_seconds=40.0
    _run.call_deferred()

func _run() -> void:
    section("Prebuilt cloth mesh geometry and face/pillow clearance")
    var m=Quilt.mesh(1.52,1.48,true)
    var a=m.surface_get_arrays(0)
    check(a[Mesh.ARRAY_VERTEX].size()==221, "12×16 patch has 221 reusable vertices")
    check(a[Mesh.ARRAY_INDEX].size()==1152, "quilt triangulation has 384 triangles")
    var top:float=-INF
    var bottom:float=INF
    for p in a[Mesh.ARRAY_VERTEX]:
        top=maxf(top,p.y)
        bottom=minf(bottom,p.y)
    check(top > 0.24 and top < 0.27, "quilt roof arches above the legs without being a floating slab",str(top))
    check(absf(bottom) < 0.0001, "quilt hem stays seated on the mattress",str(bottom))
    check(Quilt.mesh(1.52,1.48,false).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==221, "flat variant has identical topology")

    section("Actual household occupancy toggles without runtime mesh rebuilding")
    var world=Main.new()
    world.net_config={"mode":"offline","hud":false,"camera":false,"visuals":false,
        "audio":false,"autoload":false,"autosave":false}
    add_child(world)
    world.clock.running=false
    await get_tree().process_frame
    var beds=[]
    for obj in world.smart_objects:
        if obj.object_tag=="bed":beds.append(obj)
    check(beds.size()==2, "real starter scene has two usable beds")
    for bed in beds:
        var flat=bed.get_node_or_null("DuvetCover") as MeshInstance3D
        var occupied=bed.get_node_or_null("DuvetRaised") as MeshInstance3D
        check(flat!=null and occupied!=null and flat.mesh is ArrayMesh and occupied.mesh is ArrayMesh,
            "two stable authored fabrics for "+bed.display_name)
        check(flat.visible and not occupied.visible, "empty "+bed.display_name+" keeps unoccupied cover")
        check(absf(flat.position.z-0.40)<0.001, "cover leaves face/pillow zone exposed")
    var bed=beds[0]
    var sim=world.sims[0]
    bed.reserve(sim)
    sim.current_action={"id":"sleep","posture":"lie"}
    await get_tree().process_frame
    check(bed.get_node("DuvetRaised").visible and not bed.get_node("DuvetCover").visible,
        "lying resident receives draped blanket")
    bed.release(sim)
    sim.current_action={}
    await get_tree().process_frame
    check(bed.get_node("DuvetCover").visible and not bed.get_node("DuvetRaised").visible,
        "blanket returns to flat state after leaving bed")
    world.queue_free()
    await get_tree().process_frame
    finish("hq_bedding_visual")
