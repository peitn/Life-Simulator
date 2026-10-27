# M1 modular ceiling tile, original Life Simulator asset. Blender 4.x; run under city v3 lease.
import bpy, bmesh, os, json, hashlib
from mathutils import Vector
OUT="/tmp/city-1792909801-152206-ceiling"
os.makedirs(OUT,exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system="METRIC"
scene.unit_settings.scale_length=1.0
def material(name,color,roughness):
    m=bpy.data.materials.new(name)
    m.use_nodes=True
    bsdf=m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value=(*color,1)
    bsdf.inputs["Roughness"].default_value=roughness
    return m
concrete=material("Foundation concrete",(.39,.40,.39),.9)
finish=material("Warm ceiling plastering",(.72,.70,.65),.85)
root=bpy.data.objects.new("ceiling_tile_2m",None)
scene.collection.objects.link(root)
parts=[]
def box(name,center,dimensions,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=center)
    o=bpy.context.object
    o.name=name
    o.dimensions=dimensions
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat)
    # World-meter planar UVs on each face; no texture maps in prototype.
    uv=o.data.uv_layers.active
    for face in o.data.polygons:
        n=face.normal
        axes=(0,1) if abs(n.z)>.5 else ((1,2) if abs(n.x)>.5 else (0,2))
        for li in face.loop_indices:
            v=o.data.vertices[o.data.loops[li].vertex_index].co+o.location
            uv.data[li].uv=(v[axes[0]],v[axes[1]])
    bevel=o.modifiers.new("Edge highlights 2mm","BEVEL")
    bevel.width=.002
    bevel.segments=2
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    o.parent=root
    parts.append(o)
# Godot +X, -Z square: Blender +X,+Y. Pivot (0,0,0) at underside corner,
# underside y=0; slab extends upward .20m. Place at y=2.8 above wall.
box("ceiling_concrete_slab",(1,1,.11),(2,2,.18),concrete)
box("ceiling_plaster_finish",(1,1,.01),(2,2,.02),finish)
tris=0
for o in parts:
    o.data.calc_loop_triangles()
    tris+=len(o.data.loop_triangles)
    bm=bmesh.new()
    bm.from_mesh(o.data)
    assert all(e.is_manifold for e in bm.edges),o.name
    assert all(f.calc_area()>1e-10 for f in bm.faces),o.name
    assert all(abs(v.normal.length-1)<1e-4 for v in bm.verts),o.name
    bm.free()
    assert o.data.uv_layers.active is not None
assert len(parts)==2 and tris<3000
manifest={
 "asset":"ceiling_tile_2m","version":"0.1",
 "license":"Original Life Simulator asset; all rights reserved",
 "source":"tools/blender/city/ceiling_tile.py",
 "units":"meters","axes":"Blender Z-up -> Godot Y-up",
 "pivot":[0,0,0],"grid_m":.5,"dimensions_godot":[2,.2,2],
 "bounds_godot":{"min":[0,0,-2],"max":[2,.2,0]},
 "sockets_godot":[[0,0,0],[2,0,0],[0,0,-2],[2,0,-2]],
 "underside_y":0,"placement_y":2.8,"mesh_count":len(parts),"triangles":tris,
 "materials":["Foundation concrete","Warm ceiling plastering"],
 "textures":[],"uv":"1 UV unit per meter projected before bevel",
 "collision_boxes":[{"center":[1,.1,-1],"size":[2,.2,2]}],
 "notes":"Original two-layer ceiling, no texture maps/navigation. Game collider built separately."
}
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+"/ceiling_tile_2m.glb",export_format="GLB",use_selection=True,export_yup=True)
with open(OUT+"/manifest.json","w") as f:json.dump(manifest,f,indent=2)
# Render-only scene elements excluded from GLB.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.22))
backdrop=bpy.context.object
backdrop.data.materials.append(material("Backdrop",(.18,.20,.23),.9))
scene.world.color=(.3,.3,.3)
for pos,power,sz in [((0,-3,5),650,4),((4,3,6),550,4),((0,2,-3),500,4)]:
    bpy.ops.object.light_add(type="AREA",location=pos)
    light=bpy.context.object
    light.data.energy=power
    light.data.shape="DISK"
    light.data.size=sz
    light.rotation_euler=(Vector((1,1,.1))-light.location).to_track_quat("-Z","Y").to_euler()
bpy.ops.object.camera_add()
cam=bpy.context.object
scene.camera=cam
cam.data.type="ORTHO"
cam.data.ortho_scale=3.9
scene.render.engine="CYCLES"
scene.cycles.samples=12
scene.cycles.use_denoising=False
scene.render.resolution_x=320
scene.render.resolution_y=320
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="JPEG"
scene.render.image_settings.quality=78
for name,loc in [("top",(3,-4,6)),("edge",(4,-4,2.0)),("underside",(3,4,-3))]:
    cam.location=loc
    cam.rotation_euler=(Vector((1,1,.1))-cam.location).to_track_quat("-Z","Y").to_euler()
    backdrop.hide_render=(name=="underside")
    scene.render.filepath=OUT+"/"+name+".jpg"
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/ceiling_tile.blend",compress=True)
print("CITY_CEILING_RESULT="+json.dumps({"manifest":manifest,"files":{f:{"bytes":os.path.getsize(OUT+"/"+f),"sha256":hashlib.sha256(open(OUT+"/"+f,"rb").read()).hexdigest()} for f in os.listdir(OUT)}}))