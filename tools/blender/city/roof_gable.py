# Life Simulator original M1 dual-pitch roof prototype, Blender 4.x, meters.
# Blender Z-up -> Godot Y-up. Invoke only with an acquired city v3 lease.
import bpy, bmesh, os, json, math
from mathutils import Vector
OUT=os.environ.get("CITY_ROOF_OUT","/tmp/lifesim-city-roof")
os.makedirs(OUT,exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system="METRIC"
scene.unit_settings.scale_length=1.0
mat=bpy.data.materials.new("Muted slate roofing")
mat.use_nodes=True
bsdf=mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value=(.16,.19,.23,1)
bsdf.inputs["Roughness"].default_value=.83
root=bpy.data.objects.new("roof_gable_2m",None)
scene.collection.objects.link(root)
parts=[]
def slope(name,x0,x1,z0,z1):
    verts=[(x0,0,z0),(x1,0,z1),(x1,2,z1),(x0,2,z0),
           (x0,0,z0+.12),(x1,0,z1+.12),(x1,2,z1+.12),(x0,2,z0+.12)]
    faces=[(4,5,6,7),(3,2,1,0),(0,1,5,4),(2,3,7,6),(3,0,4,7),(1,2,6,5)]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    uv=mesh.uv_layers.new(name="UVMap")
    for face in mesh.polygons:
        for li in face.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            if abs(face.normal.z)>.5:
                coord=(v.x*math.sqrt(1+.6**2),v.y)
            elif abs(face.normal.y)>.5:
                coord=(v.x*math.sqrt(1+.6**2),v.z)
            else:
                coord=(v.y,v.z)
            uv.data[li].uv=coord
    obj.parent=root
    parts.append(obj)
    bm=bmesh.new()
    bm.from_mesh(mesh)
    assert all(e.is_manifold for e in bm.edges)
    assert all(f.calc_area()>1e-10 for f in bm.faces)
    bm.free()
    assert mesh.uv_layers.active is not None
slope("roof_left_slope",0,1,0,.6)
slope("roof_right_slope",1,2,.6,0)
tris=sum(len(o.data.polygons)*2 for o in parts)
assert len(parts)==2 and tris==24
manifest={"asset":"roof_gable_2m","version":"0.1-prototype",
 "license":"Original Life Simulator asset; all rights reserved",
 "source":"tools/blender/city/roof_gable.py","units":"meters",
 "axes":"Blender Z-up -> Godot Y-up","pivot_godot":[0,0,0],
 "placement_y":3.0,"grid_m":.5,
 "bounds_godot":{"min":[0,0,-2],"max":[2,.72,0]},
 "roof_type":"dual pitch gable","rise_m":.6,"vertical_thickness_m":.12,
 "eave_sockets_godot":[[0,0,0],[2,0,0],[0,0,-2],[2,0,-2]],
 "ridge_sockets_godot":[[1,.6,0],[1,.6,-2]],
 "meshes":2,"triangles":24,"materials":["Muted slate roofing"],
 "uv":"physical roof slope length and span; 1 UV unit/m",
 "collision":"not yet integrated; Godot source import and convex collision pending",
 "textures":[],"status":"Blender source/GLB/render prototype; Godot integration pending"}
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+"/roof_gable_2m.glb",export_format="GLB",use_selection=True,export_yup=True)
with open(OUT+"/manifest.json","w") as f:
    json.dump(manifest,f,indent=2)
# Render-only objects, excluded from GLB.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.4))
backdrop=bpy.context.object
for pos,power,size in [((0,-3,5),700,4),((4,3,6),550,4),((0,2,-3),450,4)]:
    bpy.ops.object.light_add(type="AREA",location=pos)
    lamp=bpy.context.object
    lamp.data.energy=power
    lamp.data.shape="DISK"
    lamp.data.size=size
    lamp.rotation_euler=(Vector((1,1,.3))-lamp.location).to_track_quat("-Z","Y").to_euler()
bpy.ops.object.camera_add()
cam=bpy.context.object
scene.camera=cam
cam.data.type="ORTHO"
cam.data.ortho_scale=4.2
scene.render.engine="CYCLES"
scene.cycles.samples=12
scene.cycles.use_denoising=False
scene.render.resolution_x=320
scene.render.resolution_y=320
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="JPEG"
scene.render.image_settings.quality=80
for label,location in [("front",(3,-4,3)),("ridge",(3,3,4)),("underside",(3,4,-2))]:
    cam.location=location
    cam.rotation_euler=(Vector((1,1,.3))-cam.location).to_track_quat("-Z","Y").to_euler()
    backdrop.hide_render=(label=="underside")
    scene.render.filepath=OUT+"/"+label+".jpg"
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/roof_gable.blend",compress=True)
print("ROOF_SOURCE_GENERATION_OK="+str(tris))
